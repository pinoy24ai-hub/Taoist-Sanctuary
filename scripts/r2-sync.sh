#!/usr/bin/env bash
#
# Uploads chapter podcasts and video explainers to Cloudflare R2, using
# media-manifest.json to map each local file to its clean bucket key
# (e.g. Ch_1_Escape_the_cage_of_modern_labels.m4a -> podcasts/ch-01.m4a).
#
# Uses the Wrangler CLI (Cloudflare's official tool), not rclone -- Wrangler
# is already installed and authenticated on this machine.
#
# ONE-TIME SETUP (only if wrangler isn't installed/authenticated yet):
#   1. npm install -g wrangler
#   2. wrangler login   (opens a browser tab to authorize against your
#      Cloudflare account -- click Allow)
#   3. Confirm it worked: wrangler whoami
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
# This script always re-uploads whatever's listed in the manifest (wrangler's
# object put has no built-in skip-if-unchanged check), so it's safe to re-run
# but re-uploads everything each time -- fine at this file count/size.

set -euo pipefail

# --- Configuration -----------------------------------------------------
R2_BUCKET="taoism"   # bucket name as shown in the Cloudflare R2 dashboard
# ------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MANIFEST="$ROOT_DIR/media-manifest.json"

if ! command -v wrangler >/dev/null 2>&1; then
    echo "ERROR: wrangler is not installed or not on PATH. See the setup instructions at the top of this script." >&2
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: $MANIFEST not found. Run 'python3 scripts/generate-media-manifest.py' first." >&2
    exit 1
fi

echo "Reading manifest and uploading to R2 bucket \"$R2_BUCKET\" via wrangler..."

python3 - "$MANIFEST" "$ROOT_DIR" "$R2_BUCKET" << 'PYEOF'
import json
import shutil
import subprocess
import sys

manifest_path, root_dir, bucket = sys.argv[1:4]

with open(manifest_path, encoding='utf-8') as f:
    manifest = json.load(f)

# shutil.which resolves the real executable (e.g. wrangler.cmd on Windows) --
# subprocess.run() without shell=True won't apply PATHEXT resolution itself.
wrangler_path = shutil.which('wrangler')
if not wrangler_path:
    print("ERROR: wrangler not found on PATH.", file=sys.stderr)
    sys.exit(1)

def content_type(ext):
    return 'audio/x-m4a' if ext == '.m4a' else 'video/mp4'

def upload(kind, folder, entries):
    for num, entry in sorted(entries.items(), key=lambda kv: int(kv[0])):
        local_path = f"{root_dir}/{folder}/{entry['localFile']}"
        r2_key = entry['r2Key']
        ext = '.' + r2_key.rsplit('.', 1)[-1]
        print(f"  [{kind} ch {num}] {entry['localFile']} -> {bucket}/{r2_key}")
        subprocess.run([
            wrangler_path, 'r2', 'object', 'put', f"{bucket}/{r2_key}",
            '--file', local_path,
            '--ct', content_type(ext),
            '--remote'
        ], check=True)

upload('podcast', 'r2-podcasts', manifest.get('podcasts', {}))
upload('explainer', 'r2-explainers', manifest.get('explainers', {}))

print("Done.")
PYEOF
