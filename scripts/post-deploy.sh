#!/usr/bin/env bash

set -euo pipefail

cd wordpress

if ! wp core is-installed; then
	echo "WordPress is not installed yet; skipping post-deploy tasks."
	exit 0
fi

# Refresh the environment stamp (production) or fire the preview sanitize
# actions when the data was just cloned or synced (previews). post_deploy
# is the only hook that runs on every redeploy, including data syncs.
#
# This line is also your project-level SANITIZATION POLICY: force the
# opt-in sanitizers per run with --enable, e.g.
#
#   wp upsun sanitize --if-needed --enable="anonymize-user-emails,anonymize-user-passwords:password-{ID}"
#
# (pair password anonymization with Upsun's HTTP access control on previews).
wp upsun sanitize --if-needed
