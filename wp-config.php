<?php
/**
 * Upsun-aware WordPress configuration. This file is copied into wordpress/
 * by the Composer postbuild script; all platform values come from the
 * PLATFORM_* environment via platformsh/config-reader. Off-platform it
 * falls back to wp-config-local.php at the project root (gitignored).
 */

use Platformsh\ConfigReader\Config;

require __DIR__ . '/../vendor/autoload.php';

$config = new Config();

$site_host   = 'localhost';
$site_scheme = 'http';

if ( isset( $_SERVER['HTTP_HOST'] ) ) {
	$site_host = $_SERVER['HTTP_HOST'];
}

if (
	( ! empty( $_SERVER['HTTPS'] ) && 'off' !== $_SERVER['HTTPS'] )
	|| ( ! empty( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && 'https' === $_SERVER['HTTP_X_FORWARDED_PROTO'] )
) {
	$site_scheme       = 'https';
	$_SERVER['HTTPS'] = 'on';
}

if ( $config->isValidPlatform() ) {
	if ( $config->hasRelationship( 'database' ) ) {
		$database = $config->credentials( 'database' );

		define( 'DB_NAME', $database['path'] );
		define( 'DB_USER', $database['username'] );
		define( 'DB_PASSWORD', $database['password'] );
		define( 'DB_HOST', $database['host'] . ':' . $database['port'] );
		define( 'DB_CHARSET', 'utf8mb4' );
		define( 'DB_COLLATE', '' );
	}

	if ( $config->routes() ) {
		foreach ( $config->routes() as $url => $route ) {
			if ( 'upstream' !== ( $route['type'] ?? '' ) || ( $route['upstream'] ?? '' ) !== $config->applicationName ) {
				continue;
			}

			$route_host   = parse_url( $url, PHP_URL_HOST );
			$route_scheme = parse_url( $url, PHP_URL_SCHEME ) ?: 'http';

			if ( $route_host && ( 'https' === $route_scheme || 'http' === $site_scheme ) ) {
				$site_host   = $route_host;
				$site_scheme = $route_scheme;
			}
		}
	}

	// Deterministic per-project salts: no generator step, and clones share
	// them (auth cookies survive environment branching).
	if ( $config->projectEntropy ) {
		foreach ( [
			'AUTH_KEY',
			'SECURE_AUTH_KEY',
			'LOGGED_IN_KEY',
			'NONCE_KEY',
			'AUTH_SALT',
			'SECURE_AUTH_SALT',
			'LOGGED_IN_SALT',
			'NONCE_SALT',
		] as $key ) {
			if ( ! defined( $key ) ) {
				define( $key, hash( 'sha256', $config->projectEntropy . $key ) );
			}
		}
	}

	if ( $config->hasRelationship( 'rediscache' ) ) {
		$redis = $config->credentials( 'rediscache' );
		define( 'WP_REDIS_CLIENT', 'phpredis' );
		define( 'WP_REDIS_HOST', $redis['host'] );
		define( 'WP_REDIS_PORT', $redis['port'] );
		if ( ! empty( $redis['password'] ) ) {
			define( 'WP_REDIS_PASSWORD', $redis['password'] );
		}
		// Per-environment prefix: preview clones never share cache entries
		// with production.
		define( 'WP_REDIS_PREFIX', 'wp:' . $config->environment . ':' );
		define( 'WP_CACHE_KEY_SALT', WP_REDIS_PREFIX );
		define( 'WP_REDIS_SELECTIVE_FLUSH', true );
		define( 'WP_REDIS_GRACEFUL', true );
		define( 'WP_REDIS_IGBINARY', true );
		define( 'WP_REDIS_TIMEOUT', 0.5 );
		define( 'WP_REDIS_READ_TIMEOUT', 0.5 );
		define( 'WP_REDIS_DISABLE_METRICS', true );
		define( 'WP_REDIS_DISABLE_ADMINBAR', true );
		define( 'WP_REDIS_DISABLE_BANNERS', true );
		define( 'WP_REDIS_DISABLE_COMMENT', true );
		define( 'WP_REDIS_DISABLE_DROPIN_CHECK', true );
		define( 'WP_REDIS_DISABLE_DROPIN_AUTOUPDATE', true );
	}

	if ( ! defined( 'WP_DEBUG' ) ) {
		define( 'WP_DEBUG', false );
	}

	if ( ! defined( 'WP_ENVIRONMENT_TYPE' ) ) {
		define( 'WP_ENVIRONMENT_TYPE', $config->onProduction() ? 'production' : 'staging' );
	}

	// Composer owns all code changes; the tree is read-only anyway.
	if ( ! defined( 'DISALLOW_FILE_MODS' ) ) {
		define( 'DISALLOW_FILE_MODS', true );
	}
} elseif ( file_exists( dirname( __FILE__, 2 ) . '/wp-config-local.php' ) ) {
	include dirname( __FILE__, 2 ) . '/wp-config-local.php';
}

if ( ! defined( 'WP_DEBUG' ) ) {
	define( 'WP_DEBUG', false );
}

if ( ! defined( 'DB_CHARSET' ) ) {
	define( 'DB_CHARSET', 'utf8mb4' );
}

if ( ! defined( 'DB_COLLATE' ) ) {
	define( 'DB_COLLATE', '' );
}

if ( ! defined( 'WP_HOME' ) ) {
	define( 'WP_HOME', $site_scheme . '://' . $site_host );
}

if ( ! defined( 'WP_SITEURL' ) ) {
	define( 'WP_SITEURL', WP_HOME );
}

define( 'WP_CONTENT_DIR', __DIR__ . '/wp-content' );
define( 'WP_CONTENT_URL', WP_HOME . '/wp-content' );

if ( ! defined( 'WP_TEMP_DIR' ) ) {
	define( 'WP_TEMP_DIR', sys_get_temp_dir() );
}

if ( ! defined( 'FS_METHOD' ) ) {
	define( 'FS_METHOD', 'direct' );
}

if ( ! defined( 'DISALLOW_FILE_EDIT' ) ) {
	define( 'DISALLOW_FILE_EDIT', true );
}

// The platform cron runs `wp cron event run --due-now` every 5 minutes
// (see .upsun/config.yaml); loopback cron stays off.
if ( ! defined( 'DISABLE_WP_CRON' ) ) {
	define( 'DISABLE_WP_CRON', true );
}

// Deploy migrations for `wp upsun migrate` (this file is copied into
// wordpress/, so one level up is the app root).
if ( ! defined( 'UPSUN_MIGRATIONS_DIR' ) ) {
	define( 'UPSUN_MIGRATIONS_DIR', dirname( __DIR__ ) . '/migrations' );
}

$table_prefix = 'wp_';

if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
