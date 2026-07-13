# Chapter media workflow (podcasts + video explainers)

This folder holds the tools for the R2-based media pipeline, kept deliberately
separate from the Netlify/GitHub code deploy. Reasoning: 81 podcasts + 81
video explainers add up to several gigabytes, which is a poor fit for git
(GitHub blocks any file over 100MB outright, and Git LFS's free tier is only
10GiB/month) and would blow through Netlify's free bandwidth allowance almost
immediately. Cloudflare R2 charges nothing for egress regardless of volume,
so media is served from there while the site itself (`index.html`, `js/`,
`css/`) keeps shipping through the existing git → Netlify pipeline, unchanged.

## The pieces

- `r2-podcasts/` and `r2-explainers/` -- drop new chapter files here on your
  own machine. Expected filename pattern: `Ch_<number>_<Title_With_Underscores>.<ext>`
  (`.m4a` for podcasts, `.mp4` for explainers). This is just a local staging
  area; nothing in here gets deployed to Netlify.
- `media-manifest.json` -- auto-generated. Maps each chapter number to its
  local filename, a clean R2 key (`podcasts/ch-01.m4a`), file size, and
  duration. Regenerate it any time the two folders above change.
- `chaptersData.js` -- the canonical source of truth for all 81 chapters'
  text, essays, and (once uploaded) media metadata. This mirrors what's baked
  into `js/app.js` and the standalone HTML file, kept here as a plain,
  readable reference and as the input/output for the merge script below.
- `generate-media-manifest.py` -- scans `r2-podcasts/`/`r2-explainers/` and
  (re)writes `media-manifest.json`.
- `merge-media-manifest.js` -- merges `media-manifest.json` into
  `chaptersData.js`, adding/refreshing each chapter's `podcast`/`explainer`
  fields. Chapters with no media simply get no field, and the site's UI
  already hides Listen/Watch buttons accordingly.
- `r2-sync.sh` -- uploads whatever's in the manifest to your Cloudflare R2
  bucket via the `wrangler` CLI, using the clean key names rather than the
  original descriptive filenames.

## Workflow for adding new chapter media

1. Drop new files into `r2-podcasts/` and `r2-explainers/` (only add the ones
   you have ready -- partial batches are fine, the site only shows Listen/
   Watch for chapters that actually have media).
2. `python3 scripts/generate-media-manifest.py`
3. `bash scripts/r2-sync.sh` (uses wrangler, already authenticated on this
   machine -- see the setup notes inside that script if it ever needs re-auth)
4. `node scripts/merge-media-manifest.js` -- updates `chaptersData.js` in this
   folder.
5. Hand the updated `chaptersData.js` to Claude (or run the equivalent build
   step yourself) to reassemble `js/app.js` and the standalone HTML file, then
   push the code change to GitHub as usual so Netlify redeploys.

Steps 2-4 don't touch the website's code at all -- only step 5 does, and only
because `app.js`/the HTML currently have the chapter data baked in rather than
loaded from `chaptersData.js` at runtime. If this becomes a frequent, ongoing
task, it's worth revisiting that -- having the site `fetch()` `chaptersData.js`
(or a JSON export of it) at load time instead of inlining it would let steps
2-4 update the live site on their own, without a rebuild step. Worth a
separate conversation once the cadence of adding chapters is clearer.

## One-time setup (already done on this machine)

- The R2 bucket (`taoism`) exists, has public access enabled, and is served
  at `https://pub-67ec229a129543a2968c7362a1737135.r2.dev` -- this is already
  wired into `R2_MEDIA_BASE_URL` in `js/app.js` and the `media-src` entry in
  `netlify.toml`'s Content-Security-Policy. Only touch those two if you ever
  move to a different bucket or a custom domain.
- `wrangler` is installed and authenticated (`wrangler whoami` should show
  your Cloudflare account). If it ever says "not logged in": run
  `npm install -g wrangler` then `wrangler login` and approve the browser
  prompt.
