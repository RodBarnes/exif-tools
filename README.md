# exif-tools — Photo EXIF Preparation for Immich Import

Tools for auditing and updating EXIF metadata on a photo archive prior to import
into [Immich](https://immich.app/). Designed for a collection organized in a
`YYYY/MM` directory structure.

---

## Background

Immich relies on `DateTimeOriginal` for timeline placement and uses
`ImageDescription` / `XMP-dc:Description` for photo descriptions. Photos that
predate smartphones, were scanned from film, or passed through various software
over the years frequently lack one or both fields. These tools identify and
fill those gaps without altering files that already have correct metadata.

---

## Directory Structure Assumption

Currently both tools expect photos to live under a `YYYY/MM` hierarchy:

```
/path/to/pictures/
  2013/
    04/
      vacation/
        IMG_0042.jpg
        beach.jpg
    09/
      DSC00273.jpg
  2024/
    01/
      20240115_143022.jpg
```

Files outside a `YYYY/MM` path are skipped and counted separately.

---

## Dependencies

- **bash** (4.0+) — uses `[[ =~ ]]` with ERE patterns stored in variables
- **exiftool** (`libimage-exiftool-perl`) — required by `exif-photos.sh` only

```bash
sudo apt install libimage-exiftool-perl
```

---

## Tools

### exif-classify.sh

This is an analysis tool used to help identify the types of issues which need to be addressed before using exif-photos.sh.  It classifies every photo filename in the tree into one of four categories.
**Read-only — no files are modified.**

Used to validate that the filename pattern logic correctly identifies
camera-generated names before running the update pass.

**Usage:**
```bash
./exif-classify.sh <base_dir> [logfile]
```

**Categories:**

| Category        | Description                                           | Examples                                         |
| --------------- | ----------------------------------------------------- | ------------------------------------------------ |
| `DATE-LIKE`     | Filename contains a recognizable date/timestamp       | `20141008_135239.jpg`, `2013-09-04 12.09.33.jpg` |
| `CAMERA-PREFIX` | Starts with a known camera-generated prefix           | `IMG_0042.jpg`, `DSC00273.jpg`, `DSCF0001.jpg`   |
| `CAMERA-SERIAL` | Matches a camera/scanner sequential numbering pattern | `100_0626.jpg`, `009_6A.jpg`, `013.jpg`          |
| `DESCRIPTIVE`   | None of the above — assumed to be a human-given name  | `beach sunset.jpg`, `graduation.jpg`             |

The `DESCRIPTIVE` category is the catch-all. Review its output to identify any
camera-generated names that slipped through before proceeding to the update step.

**Date patterns recognized:**

| Pattern               | Example                 |
| --------------------- | ----------------------- |
| `YYYY-MM-DD HH.MM.SS` | `2013-09-04 12.09.33`   |
| `YYYYMMDD_HHMMSS`     | `20141008_135239`       |
| `YYYYMMDD`            | `IMG_20141008`          |
| `MMDDYY`              | six-digit date fragment |

**Camera prefix patterns recognized:**

`DSC` / `DSCF` (Fujifilm), `SAM_` (Samsung), `IMG_`, `DSCN`, `MVI_`, `VID_`,
`MOV_`, `P[0-9]`, `downsized`, `Attach[0-9]`

**Camera serial patterns recognized:**

`NNN_NNNN` (Olympus/Fuji), `NNN_NNA` (film scanner frames), `imgNN` (scanner
sequential), `NNNNAsuffix` (film roll/frame), `NNN+` (plain sequential numbers)

---

### exif-photos.sh

Audits or updates `DateTimeOriginal`, `CreateDate`, `ImageDescription`, and
`XMP-dc:Description` for photos missing those fields.

**Usage:**
```bash
./exif-photos.sh report <base_dir> [logfile]
./exif-photos.sh update <base_dir> [logfile]
```

**Modes:**

`report` — lists files missing fields; no changes made.
`update` — writes missing fields; uses `-overwrite_original` (no exiftool backup copy).

#### DateTimeOriginal / CreateDate

Derived from the following sources, in priority order:

1. **Filename** — patterns tried in order:
   - `YYYYMMDD_HHMMSS` anywhere in name (e.g. `20141008_135239`)
   - `MMDDYYHHMM` whole name, optional trailing letter (e.g. `0304011035a`) — phone format
   - `YYYYMMDD` anywhere in name, not inside a longer digit run (e.g. `IMG_20141008`)
2. **Directory path** — `YYYY/MM` extracted from path; date set to `YYYY:MM:01 00:00:00`

#### Description

`ImageDescription` and `XMP-dc:Description` are written together (Immich reads
`ImageDescription` preferentially). Derived from:

1. **Descriptive subdirectory** beneath `YYYY/MM` (first path component only)
2. **Descriptive filename** (base name, if not camera-generated per above rules)
3. **Both combined** as `SubDir - Filename` when both are present

A name is considered descriptive if it does not match any date, camera prefix,
or camera serial pattern. Files that already have a description are never
overwritten.

#### File modification time

After writing EXIF data, `touch -d` restores the original filesystem mtime.
This prevents the update pass from appearing to have "touched" the files in
directory listings and backup tools.

---

## Recommended Workflow

Run these steps in order. Do not skip the report steps — they are cheap and
catch problems before the update makes changes.

```bash
# 1. Verify classification logic against your filenames
./exif-classify.sh /path/to/pictures exif_classify.log

# 2. Review DESCRIPTIVE entries in the log for false positives
grep DESCRIPTIVE exif_classify.log | less

# 3. Audit what is actually missing before touching anything
./exif-photos.sh report /path/to/pictures exif_report.log

# 4. Review the report output
grep MISSING exif_report.log | less

# 5. Run the update (take a backup first)
./exif-photos.sh update /path/to/pictures exif_update.log

# 6. Verify the update summary
tail -20 exif_update.log
```

---

## Notes

- Extensions must be lowercase before running (`jpg` not `JPG`). A separate
  rename pass was done on this collection prior to using these tools.
- Files outside `YYYY/MM` directory structure (e.g. `Family/`, `USB/`,
  bare `YYYY/` directories) are skipped by both tools and counted in the
  `Skipped (outside YYYY/MM structure)` summary line.
- Videos (`mp4`, `mov`, etc.), GIFs, and other non-photo types are skipped
  and counted in `Skipped (unsupported file type)`.
- Both tools write output to both the terminal and a log file simultaneously
  via `tee`.
- The tools are idempotent: running `update` a second time will find nothing
  to do for files already updated.
