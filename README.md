# wordpress-upsun-starter

A deploy-ready, Composer-managed WordPress for [Upsun](https://upsun.com),
pre-wired with the [upsun-wp mu-plugin](https://github.com/artetecha/upsun-wp)
— environment awareness, router-cache friendliness, safe preview clones,
deploy migrations, Upsun-specific health checks, and a `wp upsun` CLI.

**Plugin site & docs: [upsun.artetecha.com](https://upsun.artetecha.com/)**

## What you get

- **Composer owns everything**: WordPress core (`johnpbloch/wordpress-core`),
  plugins and themes from [wpackagist](https://wpackagist.org), the
  filesystem read-only in production. Redis object cache pre-wired
  (service, drop-in, per-environment key prefix).
- **The upsun-wp plugin, correctly installed**: staged into
  `composer-mu-plugins/` and copied into the build by `postbuild` (Composer's
  alphabetical install order would otherwise let the core extraction delete
  it), loader shim in place, migrations directory wired.
- **Safe previews out of the box**: every non-production environment
  intercepts outbound mail, forces WooCommerce Stripe into test mode, pauses
  webhooks, and sends noindex — with a sanitize flow triggered from the
  post_deploy hook after every clone and data sync. Declare your
  sanitization policy in one line ([scripts/post-deploy.sh](scripts/post-deploy.sh)).
- **Deploy migrations**: ordered, once-per-database PHP files in
  [migrations/](migrations/README.md), applied by `wp upsun migrate`; a
  failure aborts the deploy before traffic.
- **Observability**: an "Upsun" dashboard in wp-admin, Upsun-specific Site
  Health checks, and `wp upsun doctor` / `cache-check` / `mounts` /
  `relationships --health` for self-service diagnosis.

## Quickstart

1. **Get the code** — "Use this template" on GitHub (or
   `composer create-project artetecha/wordpress-upsun-starter my-site`).
2. **Create the Upsun project**:
   ```bash
   upsun project:create --title my-site
   git remote add upsun <project-git-url>   # or use the GitHub integration
   git push upsun main
   ```
   The first deploy builds everything; WordPress itself isn't installed yet.
3. **Install WordPress once**:
   ```bash
   upsun ssh 'cd wordpress && wp core install \
     --url="$(echo $PLATFORM_ROUTES | base64 -d | php -r "foreach (json_decode(file_get_contents(\"php://stdin\"), true) as \$u => \$r) if ((\$r[\"type\"] ?? \"\") === \"upstream\") { echo \$u; break; }")" \
     --title="My Site" --admin_user=admin --admin_email=you@example.com'
   ```
   (or just pass `--url=https://<your-environment-url>/` by hand). The
   generated admin password is printed once — store it.
4. **Verify**: `upsun ssh 'cd wordpress && wp upsun doctor'` — all checks
   should pass — and open `/wp-admin` → the "Upsun" menu.

Branch away: every environment is a full clone of production, already
protected by the preview safeguards.

## Where things go

```
.upsun/config.yaml   App, services (MariaDB + Redis), routes + cache cookies
composer.json        The site manifest; postbuild copies config + mu-plugins
wp-config.php        Upsun-aware config (relationships via config-reader)
mu-plugins/          Your site code + site-config.php (plugin filter tuning)
migrations/          Once-per-database deploy migrations
scripts/             deploy.sh, post-deploy.sh + vendor-update.sh (premium updates)
private-packages/    Vendored premium plugins/themes (Composer path packages)
wordpress/           Build output - gitignored, never edit by hand
```

Site-specific behavior belongs in [mu-plugins/site-config.php](mu-plugins/site-config.php)
via the plugin's filters — never by forking the plugin. If you change the
route cache cookies in `.upsun/config.yaml`, mirror them there too.

## Vendoring premium plugins

Premium plugins and themes can't self-update on a read-only filesystem, so
they're committed as Composer **path packages** under `private-packages/`
(`plugins/<slug>/` and `themes/<slug>/`, each a full source tree plus a
generated `composer.json`). The two `path` repositories and this convention
are already wired in `composer.json`.

**Onboard one** with the upsun-wp CLI, from a checkout that has the plugin
installed:

```bash
wp upsun vendor learnpress-stripe --to=private-packages/plugins --vendor=private-plugin
# then require it pinned to "*", so the vendored composer.json owns the version:
composer require "private-plugin/learnpress-stripe:*"
```

**Keep them current** with `scripts/vendor-update.sh`, which drives the
engine on a licensed Upsun environment so the authenticated download is
resolved from the site's own state (the WordPress update transient, or a
vendor's DB registration) — the license token never leaves the container:

```bash
UPSUN_PROJECT=<id> scripts/vendor-update.sh check          # pending updates
UPSUN_PROJECT=<id> scripts/vendor-update.sh update <slug>  # re-vendor in place, then commit
```

Running Eduma / thim-core / LearnPress? Nothing extra to require — upsun-wp
0.6+ ships a built-in ThimPress fetcher that auto-detects thim-core.

Automate it with [.github/workflows/vendor-update.yml](.github/workflows/vendor-update.yml):
a scheduled job that opens one `vendor/<slug>` PR per available update (each
human-merged, since merging deploys production). Its header documents the
one-time repo variables/secrets (`UPSUN_PROJECT`, `UPSUN_CLI_TOKEN`, `BOT_PAT`).

## Local development

Off Upsun the plugin fully no-ops. Point `wp-config-local.php` (project
root, gitignored) at your local database and serve `wordpress/` however you
prefer.

## License

MIT © [Vince Russo](https://artetecha.com)
