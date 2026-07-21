# exif-tools — Project State

_Last updated: 2026-07-21_

## Current state

- `exif-classify.sh` and `exif-photos.sh` are functionally complete and
  unchanged this session. Confirmed working against the Google Photos
  collection (`media`, fully imported into Immich) and now also against the
  first `bard` batch (see below).
- Working pattern established for processing `bard` in sets, to work around
  the non-`YYYY/MM` structural gap (see `DESIGN.md`) without modifying the
  tools: move the `YYYY/MM` directories that are confirmed ready into a
  `staging/bard/ready/` subfolder on `boss`, then run the normal
  classify → report → backup → update sequence against that subfolder only.
  This also naturally gives set-by-set (batch) processing, since the tools
  don't support scoping to a single year/month directly (the `YYYY/MM`
  structure must be visible relative to `BASE_DIR` — see `DESIGN.md`).
- Note: `BASE_DIR` must not have a trailing slash (e.g. use `.../ready`, not
  `.../ready/`) — a trailing slash breaks the relative-path stripping and
  causes every file to be silently skipped as "outside structure". Not
  considered worth fixing in the tools; just avoid trailing slashes when
  invoking them.
- First `ready` batch (10 years: 1979–1999, 19 files, pre-2000 content)
  processed successfully on `boss`:
  - `exif-classify.sh` confirmed correct classification (18 DESCRIPTIVE, 1
    DATE-LIKE).
  - `exif-photos.sh report` confirmed 18 files missing date+description, 1
    already complete.
  - Backup taken, then `exif-photos.sh update` run: 18 files updated
    (directory-derived date + filename-derived description), 0 errors.
- Git: `DESIGN.md` has been committed (`4dcb041 Create DESIGN.md`, plus
  `3f5319d` state update). `data/` remains untracked.

## What was last worked on

Ran the full classify → report → update workflow against the first `bard`
batch (`staging/bard/ready` on `boss`), consisting of 10 pre-2000 years
that were moved into the `ready/` staging subfolder as being confirmed
ready to process. Completed successfully with no errors.

## What's next

1. Identify and move the next set of `bard` directories into
   `staging/bard/ready/` (or empty/refill that folder) and repeat the same
   classify → report → backup → update sequence.
2. The larger open decision from `DESIGN.md` — how to handle `bard` years
   with descriptive folders directly under `YYYY` (no `MM` level: 1986,
   1988, 2020 entirely; 2013/2014/2016/2017/2018/2019/2021 partially) —
   is still unresolved. Those years can't be processed via the `ready/`
   staging pattern until either manually reorganized into `YYYY/MM/...` or
   the tools are extended to recognize `YYYY`-only structure. Not blocking
   for years that are already in valid `YYYY/MM` form.
3. After EXIF prep for each batch, import into Immich using `import.sh`
   (lives on `boss`, not this repo) the same way the Google Photos batches
   were imported.
