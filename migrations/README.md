# Deploy Migrations

Ordered PHP files that run once per WordPress database during deployment,
applied by `wp upsun migrate` from the deploy hook. The directory is wired
via `UPSUN_MIGRATIONS_DIR` in `wp-config.php`.

Use these for one-time runtime changes such as activating a newly installed
plugin or switching themes. Composer installs the code; migrations change
WordPress state.

Filenames must use this format (anything else fails the deploy):

```text
YYYYMMDD_NNNN_short_name.php
```

Each file returns a callable; throwing or returning `false` marks it failed,
aborts the deploy before traffic, and leaves it pending:

```php
<?php

return static function () {
	update_option( 'some_option', 'value' );
};
```

Successful migrations are recorded in non-autoloaded `upsun_migration_*`
options — clones carry the markers together with the migrated data, so
nothing re-runs on previews. Pending migrations are surfaced by
`wp upsun doctor` and Site Health.
