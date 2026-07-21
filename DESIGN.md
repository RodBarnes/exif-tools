# exif-tools — Design Notes

Design rationale, decisions, and open threads for `exif-classify.sh` /
`exif-photos.sh`. For usage, see `README.md`. For current project state, see
`STATE.md`.

---

## Origin and scope

These tools exist to process photos on `bard` (a Plex server) — older photos
with no EXIF data, many of which have filenames that encode a usable date
(camera/scanner sequential names, phone timestamp names, etc.). The goal is
to derive `DateTimeOriginal` and a `Description` for those photos so they can
be imported into Immich correctly. Scope is bounded to this EXIF-preparation
step, not the broader import/Nextcloud workflow (that lives in Immich-side
process notes, not this repo).

`exif-classify.sh` is not an end in itself — it's a diagnostic tool to
validate the filename-classification logic before trusting `exif-photos.sh`
to act on it.

## Classification design

Filenames (within a `YYYY/MM` structure) are classified in priority order,
most-confident pattern first: DATE-LIKE → CAMERA-PREFIX → CAMERA-SERIAL →
DESCRIPTIVE (catch-all). Order matters — e.g. `NNN_NNNN` (Olympus/Fuji) must
be checked before the broader `NNN_NNA` pattern, or the more specific match
never fires.

**Key technical constraint:** complex regexes with character classes or
alternation must be stored in a variable before use in `[[ =~ ]]` — inline
complex patterns fail silently in bash. This is now a standing rule for any
future pattern work in these scripts.

## Date derivation design

1. Parse from filename (`YYYYMMDD_HHMMSS`, `MMDDYYHHMM`, or `YYYYMMDD`
   anywhere in the name).
2. Fall back to `YYYY/MM` from the directory path, defaulting to day 01,
   00:00:00.

This applies uniformly whether a file has no EXIF at all or has EXIF but is
missing `DateTimeOriginal` specifically — both get the same derivation
treatment.

## Description derivation design

A filename alone can't reliably signal "descriptive vs. camera-generated," so
the agreed logic is:

1. Check the immediate subdirectory beneath `YYYY/MM` — if descriptive, use it.
2. Check the filename (minus extension) — if descriptive, use it.
3. If both are descriptive, combine as `"SubDir - Filename"`.
4. If neither is descriptive, leave blank rather than guessing.

Written to both `ImageDescription` and `XMP-dc:Description` (mirrors Immich's
read priority). Applies to any file missing a description, not just files
also missing a date. Files with an existing description are never
overwritten.

## Report mode

`report` mode shows what an `update` run *would* derive (date + source,
description), not just a bare `MISSING` flag — so results can be reviewed
before committing to a write pass.

## Resolved edge cases

- `Grad060703A.jpg`-style `MMDDYY` names fall back correctly to the
  directory date when not explicitly parsed.
- `Day1`/`Day2` subdirectories under a "50-miler" trip were judged not worth
  a special classification rule — handled by one-off manual cleanup instead
  of adding pattern complexity for a single case.
- No built-in backup: `exiftool -overwrite_original` modifies files in place.
  A manual backup (iDrive) is taken before any `update` mode run against real
  data.

## Status

`exif-classify.sh` and `exif-photos.sh` are considered functionally finished
for their stated scope. Confirmed via a full run against the already-migrated
Google Photos collection (`media`):

```
Files processed (photo types in YYYY/MM): 8868
Already had DateTimeOriginal            : 8101
Missing DateTimeOriginal                : 767
Skipped (outside YYYY/MM structure)     : 7858
Skipped (unsupported file type)         : 807
```

`YYYY`-only directories (pre-2000) were manually reorganized into `YYYY/MM`
to fit the tools' directory assumption. `Family/` and `USB/` flat collections
were explicitly deferred/out of scope.

## Batch processing pattern

The tools don't support scoping directly to a single year or month —
`BASE_DIR` must be a directory whose *contents* are `YYYY/MM/...`
(scoping to `BASE_DIR/YYYY` breaks the structural match, since the
relative path from there is only `MM/...`). To process `bard`'s content in
sets, the working pattern is: move whichever `YYYY/MM` directories are
confirmed ready into a `staging/bard/ready/` subfolder, then run
classify → report → backup → update against that subfolder only. Repeat
per batch. This also sidesteps the non-`YYYY/MM` gap below on a
batch-by-batch basis — only years already in valid `YYYY/MM` form get
moved into `ready/`.

**Gotcha:** `BASE_DIR` must not have a trailing slash. A trailing slash
(e.g. `staging/bard/ready/` instead of `staging/bard/ready`) breaks the
relative-path stripping (`${file#$BASE_DIR/}`), causing every file to
silently fall into "skipped (structure)" with no error. Not considered
worth fixing in the tools — just avoid trailing slashes when invoking
them.

## Open thread

The same classify → report → update process needs to be run against bard's
staged content — this is the next actual task for the project. The first
batch (10 pre-2000 years, 19 files) has been completed via the batch
pattern above; remaining batches are ongoing.

### Known gap: descriptive folders directly under `YYYY` (no `MM` level)

Both tools only recognize `YYYY/MM/...`; anything else counts as "skipped
(outside YYYY/MM)" and is left completely untouched — it won't even surface
in `exif-classify.sh` output. A `tree -d` of `bard`'s staged content
(`rod@boss:~/tmp/staging/bard`, also saved locally as `data/tree-bard.txt`)
shows this is far more common there than in the Google Photos set:

- `1986`, `1988`, `2020` have **no `MM` level at all** — files/folders sit
  directly under the year.
- `2013`, `2014`, `2016`, `2017`, `2018`, `2019`, `2021` have `MM` folders
  **and** sibling descriptive event folders directly under `YYYY` (e.g.
  `2013/Vacation/`, `2014/DC Trip/`, `2017/OAT2017/`). 2017 in particular is
  almost entirely non-MM content.

This is a bigger version of the pre-2000 flat-`YYYY` case seen in the Google
Photos migration, which was resolved there by manually reorganizing into
`YYYY/MM`. For `bard`, two options were identified and are undecided:

1. Manually reorganize each of these into `YYYY/MM/EventName/` based on the
   actual event date (same approach as before), or
2. Extend the tools to also recognize `YYYY/DescriptiveName/...` (no `MM`
   level), deriving date from the year alone (`YYYY:01:01`) or requiring
   filename/manual resolution.

No decision made yet — needs to be resolved before running
`exif-classify.sh` against `bard`, since as-is the run would silently skip
this content rather than flag it.
