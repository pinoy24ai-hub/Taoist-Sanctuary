#!/usr/bin/env python3
"""
Regenerates media-manifest.json from whatever files currently sit in
r2-podcasts/ and r2-explainers/.

Run this any time you add new chapter podcasts or video explainers to those
two folders, BEFORE running the R2 upload script (scripts/r2-sync.sh) and
before re-merging the manifest into chaptersData on the website side.

Expected filename pattern in both folders: Ch_<number>_<Title_With_Underscores>.<ext>
  e.g. Ch_1_Escape_the_cage_of_modern_labels.m4a
       Ch_23_Some_Chapter_Title.mp4

Usage:
    python3 scripts/generate-media-manifest.py

Requires ffprobe (part of ffmpeg) on PATH to read clip durations; falls back
to null duration if ffprobe isn't available.
"""
import re
import os
import json
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def humanize(title_part):
    text = ' '.join(title_part.split('_'))
    # fix the common "_s_" contraction artifact, e.g. "Heaven s Impartial" -> "Heaven's Impartial"
    text = re.sub(r"\b([A-Za-z]+) s\b", r"\1's", text)
    return text


def get_duration(path):
    try:
        out = subprocess.run(
            ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
             '-of', 'default=noprint_wrappers=1:nokey=1', path],
            capture_output=True, text=True, timeout=30
        )
        return round(float(out.stdout.strip()))
    except Exception:
        return None


def scan(folder, ext, kind):
    entries = {}
    if not os.path.isdir(folder):
        print(f'WARNING: folder not found, skipping: {folder}')
        return entries
    for fname in sorted(os.listdir(folder)):
        if not fname.lower().endswith(ext):
            continue
        m = re.match(r'^Ch_(\d+)_(.+)\.' + ext.lstrip('.') + r'$', fname, re.IGNORECASE)
        if not m:
            print(f'WARNING: filename did not match expected "Ch_N_Title.{ext.lstrip(".")}" pattern, skipping: {fname}')
            continue
        num = int(m.group(1))
        title = humanize(m.group(2))
        path = os.path.join(folder, fname)
        size = os.path.getsize(path)
        dur = get_duration(path)
        r2_key = f"{kind}/ch-{num:02d}{ext}"
        entries[num] = {
            "chapter": num,
            "title": title,
            "localFile": fname,
            "r2Key": r2_key,
            "sizeBytes": size,
            "durationSeconds": dur
        }
    return entries


def main():
    podcasts = scan(os.path.join(ROOT, 'r2-podcasts'), '.m4a', 'podcasts')
    explainers = scan(os.path.join(ROOT, 'r2-explainers'), '.mp4', 'explainers')

    manifest = {
        "generatedNote": "Auto-generated from filenames in r2-podcasts/ and r2-explainers/. Re-run this script whenever new chapter media is added to either folder, then re-run the chaptersData merge step.",
        "podcasts": podcasts,
        "explainers": explainers
    }

    out_path = os.path.join(ROOT, 'media-manifest.json')
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    total_size = sum(e['sizeBytes'] for e in podcasts.values()) + sum(e['sizeBytes'] for e in explainers.values())
    print(f"Wrote {out_path}")
    print(f"podcasts: {len(podcasts)} chapters, explainers: {len(explainers)} chapters")
    print(f"combined size of files scanned this run: {total_size / (1024*1024):.1f} MB")

    missing_podcasts = sorted(set(range(1, 82)) - set(podcasts.keys()))
    missing_explainers = sorted(set(range(1, 82)) - set(explainers.keys()))
    if missing_podcasts:
        print(f"chapters still missing a podcast: {missing_podcasts}")
    if missing_explainers:
        print(f"chapters still missing an explainer video: {missing_explainers}")


if __name__ == '__main__':
    main()
