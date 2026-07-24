# private-packages

Vendored premium plugins and themes, committed as Composer **path packages**
(they can't self-update on Upsun's read-only filesystem). `composer.json`
already declares the two path repositories:

```
private-packages/plugins/<slug>/   # type: wordpress-plugin
private-packages/themes/<slug>/    # type: wordpress-theme
```

Each `<slug>/` is a full source tree plus a generated `composer.json` whose
`version` is the source of truth — require the package pinned to `"*"` in the
root manifest.

Onboard and update these with `scripts/vendor-update.sh` (see the
"Vendoring premium plugins" section of the top-level README). This directory
starts empty; the `.gitkeep` files keep `plugins/` and `themes/` present so
the path-repository globs resolve in a fresh clone.
