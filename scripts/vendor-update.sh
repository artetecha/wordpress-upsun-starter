#!/usr/bin/env bash
#
# Update vendored premium packages in <VENDOR_DIR>/ by driving the upsun-wp
# vendoring engine (`wp upsun vendor`, upsun-wp >= 0.6) ON a licensed Upsun
# environment, so every request carries the site's activated license and the
# license token never leaves the container.
#
# Discovery uses the engine's machine-readable resolve contract
# (`--dry-run --format=json` — the token-bearing download URL is never
# emitted). The actual re-vendor downloads, extracts, and regenerates the
# package's composer.json ON the container; the finished tree is streamed back
# (tar over base64) and dropped into <VENDOR_DIR>/. Nothing is committed —
# review `git diff` and push (the CI pipeline in vendor-update-prs.sh does
# that per package).
#
# Config (environment):
#   UPSUN_PROJECT     required — Upsun project id
#   UPSUN_ENV         environment to drive, must carry the licenses (default: main)
#   UPSUN_APP         application name (default: wordpress)
#   VENDOR_DIR        vendored-packages dir under the repo root (default: private-packages)
#   VENDOR_NS_PLUGIN  Composer vendor namespace for plugins (default: private-plugin)
#   VENDOR_NS_THEME   Composer vendor namespace for themes  (default: private-theme)
#
# Usage:
#   scripts/vendor-update.sh check [--porcelain]     # pending updates
#   scripts/vendor-update.sh update <slug> [...]     # re-vendor new versions
#
# Requires: upsun CLI (authenticated), composer, php, python3.

set -euo pipefail

PROJECT="${UPSUN_PROJECT:?set UPSUN_PROJECT to your Upsun project id}"
ENVIRONMENT="${UPSUN_ENV:-main}"
APP="${UPSUN_APP:-wordpress}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="${ROOT_DIR}/${VENDOR_DIR:-private-packages}"
NS_PLUGIN="${VENDOR_NS_PLUGIN:-private-plugin}"
NS_THEME="${VENDOR_NS_THEME:-private-theme}"

# Slugs and vendor namespaces are interpolated into commands run on the
# credential-bearing container, so every one must match this before it goes
# near SSH. A single quote (or anything outside this set) could break out of
# the remote quoting.
SLUG_RE='^[A-Za-z0-9._-]+$'

# A safe slug: matches SLUG_RE and is not a path traversal (., ..).
slug_ok() { [[ "$1" =~ $SLUG_RE ]] && [ "$1" != "." ] && [ "$1" != ".." ]; }

# Fail fast on a misconfigured (or malicious) vendor namespace — it reaches
# the remote --vendor='...' the same way a slug does.
for _ns in "$NS_PLUGIN" "$NS_THEME"; do
	[[ "$_ns" =~ $SLUG_RE ]] || { echo "ERROR: invalid vendor namespace '$_ns' (allowed: A-Z a-z 0-9 . _ -)" >&2; exit 1; }
done
unset _ns

# Whole-vendor-step timeout on the container (seconds); the engine's own
# wp_remote_get already caps the download at 120s. Run container-side (Linux
# `timeout`) so no `timeout` binary is needed locally (macOS lacks one).
REMOTE_TIMEOUT=600

# Run an inline bash snippet on the licensed Upsun environment over SSH.
remote() { upsun ssh -p "$PROJECT" -e "$ENVIRONMENT" --app "$APP" --no-interaction "$1"; }

# Every vendored package as "slug type" (type is plugin|theme). Slugs that fail
# SLUG_RE are skipped loudly rather than interpolated into a remote shell.
vendored_entries() {
	local sub type pkg slug
	for sub in plugins themes; do
		[ -d "$PKG_DIR/$sub" ] || continue
		type=plugin; [ "$sub" = themes ] && type=theme
		for pkg in "$PKG_DIR/$sub"/*/; do
			[ -f "${pkg}composer.json" ] || continue
			slug="$(basename "$pkg")"
			if ! slug_ok "$slug"; then
				echo "WARN: skipping unsafe package name '$slug'" >&2
				continue
			fi
			echo "$slug $type"
		done
	done
}

# Resolve a slug to "kind type vendor-namespace" from its location.
slug_layout() {
	if [ -d "$PKG_DIR/themes/$1" ]; then
		echo "themes theme $NS_THEME"
	elif [ -d "$PKG_DIR/plugins/$1" ]; then
		echo "plugins plugin $NS_PLUGIN"
	else
		return 1
	fi
}

cmd_check() { # cmd_check [table|porcelain]
	local format="${1:-table}"
	local entries args raw slug type
	entries="$(vendored_entries)"
	if [ -z "$entries" ]; then
		[ "$format" = table ] && echo "No vendored packages found in $PKG_DIR."
		return 0
	fi

	args=""
	while read -r slug type; do
		[ -n "$slug" ] && args+=" ${slug}:${type}"
	done <<<"$entries"

	# One SSH round-trip. The `wp cli has-command` preflight runs WITHOUT
	# `|| true`, so a missing engine (bad deploy) or unreachable container
	# fails the block under `set -e` and propagates a non-zero exit that the
	# PR pipeline's retry re-attempts — instead of empty output that reads as
	# "everything up to date". Each dry-run emits a JSON array ([] or [plan]).
	raw="$(remote "
		set -e
		cd /app/wordpress
		wp cli has-command 'upsun vendor'
		wp eval 'wp_update_plugins(); wp_update_themes();' >/dev/null 2>&1 || true
		for pair in ${args}; do
			s=\"\${pair%%:*}\"; t=\"\${pair##*:}\"
			timeout ${REMOTE_TIMEOUT} wp upsun vendor \"\$s\" --update --type=\"\$t\" --dry-run --format=json 2>/dev/null || true
		done
	")"

	# Aggregate the JSON-per-line plans into "slug local remote fetcher" rows.
	printf '%s\n' "$raw" | python3 -c '
import json, sys
rows = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
    except ValueError:
        continue
    if isinstance(data, list):
        for p in data:
            rows.append((p.get("slug", ""), p.get("from", "") or "?", p.get("to", ""), p.get("fetcher", "")))
fmt = sys.argv[1]
if fmt == "porcelain":
    for r in rows:
        print(r[0], r[1], r[2], r[3])
elif not rows:
    print("Everything up to date.")
else:
    print("%-40s %-12s %-12s %s" % ("PACKAGE", "LOCAL", "AVAILABLE", "FETCHER"))
    for r in rows:
        print("%-40s %-12s %-12s %s" % (r[0], r[1], r[2], r[3]))
' "$format"
}

cmd_update() { # cmd_update <slug>
	local slug="$1" layout kind type ns tmp version
	if ! slug_ok "$slug"; then
		echo "ERROR: refusing unsafe package name '$slug'" >&2; return 1
	fi
	layout="$(slug_layout "$slug")" || { echo "ERROR: $slug is not in $PKG_DIR/" >&2; return 1; }
	read -r kind type ns <<<"$layout"

	tmp="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" RETURN

	echo "==> $slug: resolving + downloading on the container (license token stays on the container)"
	# Prime the transient, re-vendor into the container's /tmp, then stream the
	# finished package back. wp's own output is redirected to stderr so only the
	# tarball reaches the pipe.
	remote "
		set -e
		cd /app/wordpress
		wp eval 'wp_update_plugins(); wp_update_themes();' >/dev/null 2>&1 || true
		rm -rf /tmp/upsun-vendor && mkdir -p /tmp/upsun-vendor
		timeout ${REMOTE_TIMEOUT} wp upsun vendor '$slug' --update --type='$type' --to=/tmp/upsun-vendor --vendor='$ns' 1>&2
		if [ -d /tmp/upsun-vendor/'$slug' ]; then
			tar -C /tmp/upsun-vendor -cf - '$slug' | base64
		fi
		rm -rf /tmp/upsun-vendor
	" | python3 -c 'import base64, sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read()))' > "$tmp/pkg.tar"

	if [ ! -s "$tmp/pkg.tar" ]; then
		echo "==> $slug: up to date; nothing vendored."
		return 0
	fi

	echo "==> $slug: vendoring the new version"
	rm -rf "${PKG_DIR:?}/$kind/$slug"
	mkdir -p "$PKG_DIR/$kind"
	tar -C "$PKG_DIR/$kind" -xf "$tmp/pkg.tar"

	version="$(php -r '$c = json_decode(file_get_contents($argv[1]), true); echo is_array($c) ? ($c["version"] ?? "") : "";' "$PKG_DIR/$kind/$slug/composer.json")"

	# Root composer.json pins path packages as "*" (the vendored composer.json
	# is the version authority), so only this package's own lock entry changes.
	( cd "$ROOT_DIR" && composer update --no-install --no-scripts --quiet "$ns/$slug" )
	echo "==> $slug: done (${version:-unknown}). Review with git diff, then commit & push."
}

case "${1:-}" in
	check)
		shift
		format="table"
		[ "${1:-}" = "--porcelain" ] && format="porcelain"
		cmd_check "$format"
		;;
	update)
		shift
		[ $# -ge 1 ] || { echo "usage: $0 update <slug> [...]" >&2; exit 1; }
		for slug in "$@"; do cmd_update "$slug"; done
		;;
	*) echo "usage: $0 check [--porcelain] | update <slug> [...]" >&2; exit 1 ;;
esac
