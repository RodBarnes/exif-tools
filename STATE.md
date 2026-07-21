# exif-tools — Project State

_Last updated: 2026-07-19_

## Current state

- `exif-classify.sh` and `exif-photos.sh` are functionally complete and
  unchanged this session. Both confirmed working against the Google Photos
  collection (`media`), which has already been fully imported into Immich.
- Repo docs reorganized this session:
  - `README.md` kept as the lean usage/reference doc (purpose, directory
    assumption, dependencies, tool usage, workflow) — unchanged in content.
  - `DESIGN.md` created — captures design rationale, decisions, resolved
    edge cases, and open threads, sourced from a Claude.web project
    ("Immitch") where this tooling was originally investigated.
  - `claude-web/` scratch import directory (files pulled from the Claude.web
    project for comparison) was reviewed and deleted — the `.sh` files there
    were confirmed byte-identical (modulo whitespace) to the repo root
    versions, so nothing needed merging. `import.sh` (Immich CLI Docker
    upload wrapper) and `immitch.md` (import/Nextcloud process notes, home
    GPS coordinates) were reviewed and determined to be out of scope for
    this repo — they describe the broader import workflow on `boss`, not
    EXIF preparation.
- `data/tree-bard.txt` and `data/tree-boss.txt` (untracked) hold `tree -d`
  output of the staging structure for reference.
- Git: `DESIGN.md` has been committed (`4dcb041 Create DESIGN.md`). Local
  branch is 1 commit ahead of `origin/main` (not pushed). `data/` is
  untracked.

## What was last worked on

Reviewing the actual directory structure of `bard`'s staged photos
(`rod@boss:~/tmp/staging/bard`) to prepare for running the classify → report
→ update process against them — the next real task for this project, now
that the Google Photos migration is done and bard is next in line for
Immich import.

That review surfaced a structural gap: both tools only recognize
`YYYY/MM/...` paths. A significant portion of `bard`'s content sits in
`YYYY/DescriptiveFolder/...` with **no `MM` level** (years 1986, 1988, 2020
entirely; years 2013/2014/2016/2017/2018/2019/2021 partially — 2017 is
almost all non-MM). As written, the tools would silently skip all of this
rather than flag it. Full detail and the two candidate resolutions (manual
reorg vs. extending the tools) are recorded in `DESIGN.md` under "Known gap:
descriptive folders directly under `YYYY`".

## What's next

1. **Decide** how to handle the non-`YYYY/MM` folders in `bard` — manual
   reorganization (consistent with how the pre-2000 case was handled
   before) vs. extending `exif-classify.sh`/`exif-photos.sh` to recognize
   `YYYY/DescriptiveName/...` directly. This is a blocking decision before
   proceeding.
2. Once resolved, run the established workflow against `bard`'s staged copy
   on `boss` (`~/tmp/staging/bard`, or wherever it ends up after any
   reorg): `exif-classify.sh` → review `DESCRIPTIVE` output → `exif-photos.sh
   report` → review `MISSING` output → back up → `exif-photos.sh update`.
3. After EXIF prep, import into Immich using `import.sh` (lives on `boss`,
   not this repo) the same way the Google Photos batches were imported.
