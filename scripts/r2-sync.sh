#!/usr/bin/env bash
#
# Uploads chapter podcasts and video explainers to Cloudflare R2, using
# media-manifest.json to map each local file to its clean bucket key
# (e.g. Ch_1_Escape_the_cage_of_modern_labels.m4a -> podcasts/ch-01.m4a).
#
# ONE-TIME SETUP (do this once per machine):
#   1. Install rclone: https://rclone.org/downloads/
#   2. Get from the Cloudflare dashboard (R2 > Manage R2 API Tokens):
#        - Account ID
#        - Access Key ID + Secret Access Key (create an R2 API token)
#   3. Configure an rclone remote named "r2":
#        rclone config
#        > n (new remote)
#        > name: r2
#        > type: Amazon S3 Compliant Storage Providers (s3)
#        > provider: Cloudflare R2
#        > access_key_id / secret_access_key: (from step 2)
#        > endpoint: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
#      (rclone will prompt for these interactively -- accept defaults elsewhere)
#   4. Create the bucket once (only needs doing the first time):
#        rclone mkdir r2:tao-media
#
# EVERY TIME you add new chapter files:
#   1. Drop the new Ch_N_Title.m4a / Ch_N_Title.mp4 files into
#      r2-podcasts/ and r2-explainers/
#   2. Regenerate the manifest:      python3 scripts/generate-media-manifest.py
#   3. Run this script:              bash scripts/r2-sync.sh
#   4. Ask Claude to re-merge the manifest into chaptersData.js and rebuild
#      the site (or run scripts/merge-media-manifest.js yourself and hand the
#      updated chaptersData.js back to Claude to reassemble app.js/index.html).
#
# This script only uploads files that are new or changed (rclone copyto
# compares size/checksum), so it's safe to re-run any time.

set -euo pipefail

# --- Configuration -----------------------------------------------------
R2_REMOTE="r2"          # the rclone remote name you configured above
R2_BUCKET="tao-media"   # TODO: change to your actual bucket name
# ------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$ROOT_DIR/media-manifest.json"

if ! command -v rclone >/dev/null 2>&1; then
    echo "ERROR: rclone is not installed or not on PATH. See the setup instructions at the top of this script." >&2
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: $MANIFEST not found. Run 'python3 scripts/generate-media-manifest.py' first." >&2
    exit 1
fi

echo "Reading manifest and uploading to r2:$R2_BUCKET ..."

python3 - "$MANIFEST" "$ROOT_DIR" "$R2_REMOTE" "$R2_BUCKET" << 'PYEOF'
import json
import subprocess
import sys

manifest_path, root_dir, remote, bucket = sys.argv[1:5]

with open(manifest_path, encoding='utf-8') as f:
    manifest = json.load(f)

def upload(kind, folder, entries):
    for num, entry in sorted(entries.items(), key=lambda kv: int(kv[0])):
        local_path = f"{root_dir}/{folder}/{entry['localFile']}"
        remote_path = f"{remote}:{bucket}/{entry['r2Key']}"
        print(f"  [{kind} ch {num}] {entry['localFile']} -> {remote_path}")
        subprocess.run(['rclone', 'copyto', local_path, remote_path, '--progress'], check=True)

upload('podcast', 'r2-podcasts', manifest.get('podcasts', {}))
upload('explainer', 'r2-explainers', manifest.get('explainers', {}))

print("Done.")
PYEOF
