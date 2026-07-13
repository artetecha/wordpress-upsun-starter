#!/usr/bin/env bash

set -euo pipefail

cd wordpress

if ! wp core is-installed; then
	echo "WordPress is not installed yet; see the README for the one-time wp core install."
	exit 0
fi

wp core update-db

# Ordered once-per-database migrations from migrations/ (see the upsun-wp
# plugin). Non-zero exit aborts the deploy before traffic (set -e above).
wp upsun migrate

wp redis enable || true
wp cron event run --due-now || true
