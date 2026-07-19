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

## Open thread

The same classify → report → update process needs to be run against bard's
staged content — this is the next actual task for the project, not yet
started as of this writing.
