#!/bin/sh
# Copies the built travel data (server/public.nosync/v1) into the R2 bucket, as it is. Needs rclone (brew install
# rclone) with a remote called "r2" set up once with the R2 access key from Cloudflare (rclone config: type s3, provider
# Cloudflare, your account's endpoint). Run from the wya?! folder: sh server/launch/upload-data.sh
set -e
SRC="server/public.nosync/v1"
[ -d "$SRC" ] || { echo "No $SRC here. Run it from the wya?! folder, after python3 server/build_api.py."; exit 1; }
command -v rclone >/dev/null || { echo "rclone is not installed: brew install rclone"; exit 1; }
rclone listremotes | grep -q '^r2:$' || { echo "No rclone remote called r2 yet: rclone config"; exit 1; }
rclone copy "$SRC" r2:wya-data/v1 --s3-no-check-bucket --transfers 16 --progress
echo "Done. Now the app's address: in src/api.js set API_BASE to https://<your data worker>/v1/"
