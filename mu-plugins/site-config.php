<?php
/**
 * Plugin Name: Site configuration for the Upsun plugin
 * Description: Site-specific tuning of the upsun-wp mu-plugin. Filters only — the plugin itself stays generic. Docs: https://github.com/artetecha/upsun-wp
 *
 * This file loads before the plugin boots its modules (muplugins_loaded
 * priority 0), so every filter registered here is always in time.
 */

defined( 'ABSPATH' ) || exit;

/**
 * Mirror the route cache block from .upsun/config.yaml so `wp upsun
 * cache-check` reports your real cookie allowlist (Upsun does not expose
 * it at runtime). KEEP IN SYNC with .upsun/config.yaml.
 */
add_filter( 'upsun_cache_check_route_cache', function ( array $config ) {
	return array(
		'enabled'     => true,
		'default_ttl' => 0,
		'cookies'     => array(
			'/^wordpress_logged_in_/',
			'/^wordpress_sec_/',
			'wordpress_test_cookie',
			'/^wp-settings-/',
			'/^wp-postpass/',
			'PHPSESSID',
		),
		'known'       => true,
	);
} );

/*
 * More examples — uncomment and adapt. The full public API (filters,
 * constants, helpers, interfaces, and the wp upsun subcommands) is frozen
 * as of upsun-wp 1.0 and documented here:
 * https://github.com/artetecha/upsun-wp/blob/main/docs/api-reference.md
 */

// Team accounts exempt from the email/password anonymizers (the
// sanitization policy itself lives in scripts/post-deploy.sh --enable):
// add_filter( 'upsun_sanitize_preserved_emails', fn () => array( '@example.com' ) );

// Shared-cache TTL (seconds) for anonymous pages:
// add_filter( 'upsun_page_cache_ttl', fn () => 1200 );

// A staging domain that must send real mail:
// add_filter( 'upsun_safe_previews_mail', fn () => 'allow' );

// Skip cache headers for a plugin-specific dynamic page:
// add_filter( 'upsun_page_cache_skip', fn ( $skip ) => $skip || function_exists( 'my_is_dynamic_page' ) && my_is_dynamic_page() );

// Invalidate the shared cache after publishing, without this file needing to
// know which CDN (if any) is in front. Upsun's router cache has no purge API,
// so purge_paths() dispatches to whatever backend is available — the
// cloudflare module registers one when CLOUDFLARE_ZONE_ID and
// CLOUDFLARE_API_TOKEN are set — and reports plainly when there is none.
// New in upsun-wp 1.0.
// add_action( 'transition_post_status', function ( $new, $old, $post ) {
// 	if ( 'publish' !== $new || 'publish' === $old ) {
// 		return;
// 	}
//
// 	$result = Upsun\purge_paths( array( '/', get_permalink( $post ) ) );
//
// 	if ( ! $result['purged'] ) {
// 		error_log( 'Upsun purge skipped: ' . $result['message'] );
// 	}
// }, 10, 3 );

// Register your own purge backend (Fastly, Varnish, …). Return true when you
// handled it, false to let the next backend try:
// add_filter( 'upsun_purge_backends', function ( array $backends ) {
// 	$backends['fastly'] = fn ( array $urls ) => my_fastly_purge( $urls );
//
// 	return $backends;
// } );
