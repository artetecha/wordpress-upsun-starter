#!/usr/bin/env bash
#
# Raise one PR per vendored premium package that has an update available.
#
# Discovery and vendoring are delegated to scripts/vendor-update.sh, which
# drives the upsun-wp vendoring engine on a licensed Upsun environment (license
# tokens never leave the container). A single `check --porcelain` reports
# pending updates as "slug local remote fetcher"; each becomes a branch
# vendor/<slug> and a PR labelled vendored-update.
#
# Each branch is rebuilt from origin/<BASE_BRANCH> on every run, so sibling PRs
# that went stale when one merged (composer.json/lock overlap) self-heal on the
# next run. A marker in the PR body encodes the proposed version so an unchanged
# PR is skipped instead of force-pushed.
#
# Driven by .github/workflows/vendor-update.yml; runs from the repo root.
#
# Expects: GH_TOKEN (a PAT, NOT the workflow GITHUB_TOKEN — PRs created by
# GITHUB_TOKEN never trigger the pull_request test workflows), an authenticated
# upsun CLI, composer, php, python3, a configured git author, and the UPSUN_*
# env that vendor-update.sh reads (UPSUN_PROJECT required).
#
# Usage: vendor-update-prs.sh [slugs...]   (no args = all available updates)

set -euo pipefail

BASE_BRANCH="${BASE_BRANCH:-main}"
VENDOR_DIR="${VENDOR_DIR:-private-packages}"
DRIVER="scripts/vendor-update.sh"
LABEL="vendored-update"
REQUESTED=("$@")

# retry <attempts> <cmd...>: exponential-ish backoff (30s, 60s, 120s...).
# The Upsun API occasionally answers 503; one transient error must not kill a
# whole scheduled run.
retry() {
	local attempts="$1" delay=30 i
	shift
	for (( i = 1; i <= attempts; i++ )); do
		"$@" && return 0
		if (( i < attempts )); then
			echo "==> attempt $i/$attempts failed, retrying in ${delay}s" >&2
			sleep "$delay"
			delay=$(( delay * 2 ))
		fi
	done
	echo "ERROR: all $attempts attempts failed: $*" >&2
	return 1
}

git fetch origin "$BASE_BRANCH"

echo "==> checking every vendored package via the vendoring engine"
updates=$(retry 3 "$DRIVER" check --porcelain)

echo "--- updates ---"; echo "${updates:-none}"

failures=()
raised=0

while read -r slug local_ver remote_ver fetcher; do
	[ -n "$slug" ] || continue

	if [ "${#REQUESTED[@]}" -gt 0 ]; then
		wanted=false
		for r in "${REQUESTED[@]}"; do [ "$r" = "$slug" ] && wanted=true; done
		$wanted || { echo "==> $slug: not in requested set, skipping"; continue; }
	fi

	branch="vendor/$slug"
	marker="<!-- vendored-update: ${slug}@${remote_ver} -->"

	pr_json=$(gh pr list --head "$branch" --base "$BASE_BRANCH" --state open --json number,body,mergeable --jq '.[0] // empty')
	if [ -n "$pr_json" ] && grep -qF "$marker" <<<"$pr_json"; then
		# Same version already proposed — skip only if still mergeable.
		# Conflicted branches (lock overlap after a sibling merged) MUST
		# rebuild or they stay stale forever; the self-heal hinges on this.
		mergeable=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("mergeable",""))' "$pr_json")
		if [ "$mergeable" != "CONFLICTING" ]; then
			echo "==> $slug: open PR already proposes $remote_ver, skipping"
			continue
		fi
		echo "==> $slug: open PR is conflicted, rebuilding from $BASE_BRANCH"
	fi

	echo "==> $slug: $local_ver -> $remote_ver (via $fetcher)"
	# </dev/null: commands inside (upsun ssh) must not slurp the porcelain
	# lines this loop reads from stdin. Subshell exit codes: 0 = PR
	# raised/refreshed, 3 = nothing to vendor (benign), other = failure.
	rc=0
	(
		set -euo pipefail
		git checkout -B "$branch" "origin/$BASE_BRANCH"
		git reset --hard "origin/$BASE_BRANCH"
		git clean -fd "$VENDOR_DIR"

		"$DRIVER" update "$slug"

		git add -A "$VENDOR_DIR" composer.json composer.lock
		# An up-to-date race between check and update stages nothing; benign.
		if git diff --cached --quiet; then
			echo "==> $slug: engine vendored nothing (up-to-date race), skipping"
			exit 3
		fi
		git commit -m "Update ${slug} ${local_ver} -> ${remote_ver} (vendored premium)"
		git push --force origin "$branch"

		body=$(printf '%s\n\nAutomated update of `%s` from **%s** to **%s** via the %s fetcher (`wp upsun vendor`).\n\nMerging deploys to production — review the CI results and the preview environment first. This PR is human-merged by design.\n' \
			"$marker" "$slug" "$local_ver" "$remote_ver" "$fetcher")

		if [ -n "$pr_json" ]; then
			pr_number=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["number"])' "$pr_json")
			gh pr edit "$pr_number" \
				--title "Update ${slug} ${local_ver} → ${remote_ver}" --body "$body"
		else
			# Create the label lazily (idempotent) so the first run needs no setup.
			gh label create "$LABEL" --color 5319e7 \
				--description "Automated vendored premium update" --force >/dev/null 2>&1 || true
			gh pr create --head "$branch" --base "$BASE_BRANCH" \
				--title "Update ${slug} ${local_ver} → ${remote_ver}" \
				--label "$LABEL" --body "$body"
		fi
	) </dev/null || rc=$?

	case "$rc" in
		0) raised=$(( raised + 1 )) ;;
		3) : ;; # nothing to vendor; already logged, not a failure
		*) echo "ERROR: failed to raise PR for $slug, continuing with the rest" >&2
		   failures+=("$slug") ;;
	esac
done <<<"$updates"

git checkout --detach "origin/$BASE_BRANCH" >/dev/null 2>&1 || true

scanned=$(find "$VENDOR_DIR/plugins" "$VENDOR_DIR/themes" \
	-mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

echo "==> scanned ${scanned} vendored package(s); raised/refreshed ${raised} PR(s)"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "## Vendored premium updates"
		echo
		echo "- Packages scanned: ${scanned}"
		echo "- Update PRs raised/refreshed: ${raised}"
	} >> "$GITHUB_STEP_SUMMARY"
fi

if [ "${#failures[@]}" -gt 0 ]; then
	echo "ERROR: failed packages: ${failures[*]}" >&2
	exit 1
fi
