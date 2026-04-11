#!/bin/bash
# exif_photos.sh
#
# Audits or updates EXIF DateTimeOriginal for photos in a YYYY/MM directory structure.
#
# Usage:
#   exif_photos.sh report <base_dir> [logfile]
#   exif_photos.sh update <base_dir> [logfile]
#
# Modes:
#   report  -- List files missing DateTimeOriginal; no changes made
#   update  -- Set DateTimeOriginal on files missing it, using:
#              1. Timestamp parsed from filename (YYYYMMDD_HHMMSS or YYYYMMDD)
#              2. YYYY/MM from directory path, defaulting to 01 00:00:00
#
# Supported file types: jpg, jpeg, png, tif
# Skipped: videos, gif, non-media files, directories outside YYYY/MM pattern

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 report|update <base_dir> [logfile]"
    exit 1
fi

MODE="$1"
BASE_DIR="$2"
LOGFILE="${3:-exif_photos_$(date +%Y%m%d_%H%M%S).log}"

if [[ "$MODE" != "report" && "$MODE" != "update" ]]; then
    echo "Error: mode must be 'report' or 'update'"
    exit 1
fi

if [[ ! -d "$BASE_DIR" ]]; then
    echo "Error: base directory '$BASE_DIR' does not exist"
    exit 1
fi

# ---------------------------------------------------------------------------
# Supported photo extensions (all lowercase — run extension lowercaser first)
# ---------------------------------------------------------------------------
PHOTO_EXTS="jpg jpeg png tif"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    echo "$1" | tee -a "$LOGFILE"
}

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
count_processed=0
count_has_date=0
count_missing=0
count_updated_filename=0
count_updated_dir=0
count_skipped_structure=0
count_skipped_type=0
count_errors=0

# ---------------------------------------------------------------------------
# Check exiftool is available
# ---------------------------------------------------------------------------
if ! command -v exiftool &>/dev/null; then
    echo "Error: exiftool is not installed. Install with: sudo apt install libimage-exiftool-perl"
    exit 1
fi

log "========================================"
log "exif_photos.sh"
log "Mode     : $MODE"
log "Base dir : $BASE_DIR"
log "Log file : $LOGFILE"
log "Started  : $(date)"
log "========================================"
log ""

# ---------------------------------------------------------------------------
# Helper: check if extension is a supported photo type
# ---------------------------------------------------------------------------
is_photo() {
    local ext="${1,,}"  # lowercase
    for e in $PHOTO_EXTS; do
        [[ "$ext" == "$e" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Helper: extract DateTimeOriginal via exiftool
# Returns empty string if not present or not a valid date
# ---------------------------------------------------------------------------
get_exif_date() {
    local file="$1"
    exiftool -s3 -DateTimeOriginal "$file" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Helper: attempt to parse date from filename
# Matches: YYYYMMDD_HHMMSS  or  YYYYMMDD
# Returns exiftool-format date string: YYYY:MM:DD HH:MM:SS  or empty
# ---------------------------------------------------------------------------
parse_date_from_filename() {
    local filename="$1"
    local base
    base=$(basename "$filename")
    base="${base%.*}"  # strip extension

    # Pattern 1: YYYYMMDD_HHMMSS (e.g. 20141008_135239)
    if [[ "$base" =~ ([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
        local y="${BASH_REMATCH[1]}"
        local mo="${BASH_REMATCH[2]}"
        local d="${BASH_REMATCH[3]}"
        local h="${BASH_REMATCH[4]}"
        local mi="${BASH_REMATCH[5]}"
        local s="${BASH_REMATCH[6]}"
        echo "${y}:${mo}:${d} ${h}:${mi}:${s}"
        return
    fi

    # Pattern 2: YYYYMMDD anywhere in filename (e.g. IMG_20141008.jpg)
    if [[ "$base" =~ ([0-9]{4})([0-9]{2})([0-9]{2}) ]]; then
        local y="${BASH_REMATCH[1]}"
        local mo="${BASH_REMATCH[2]}"
        local d="${BASH_REMATCH[3]}"
        echo "${y}:${mo}:${d} 00:00:00"
        return
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Helper: parse date from directory path
# Expects path to contain /YYYY/MM/ somewhere
# Returns exiftool-format date string or empty
# ---------------------------------------------------------------------------
parse_date_from_dir() {
    local filepath="$1"
    local dir
    dir=$(dirname "$filepath")

    # Match /YYYY/MM at end of path or anywhere
    if [[ "$dir" =~ /([0-9]{4})/([0-9]{2})(/|$) ]]; then
        local y="${BASH_REMATCH[1]}"
        local mo="${BASH_REMATCH[2]}"
        echo "${y}:${mo}:01 00:00:00"
        return
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Helper: check that YYYY/MM components are plausible
# ---------------------------------------------------------------------------
is_valid_year_month() {
    local y="$1"
    local mo="$2"
    [[ "$y" -ge 1800 && "$y" -le 2100 && "$mo" -ge 1 && "$mo" -le 12 ]]
}

# ---------------------------------------------------------------------------
# Main loop: walk only YYYY/MM subdirectories of BASE_DIR
# ---------------------------------------------------------------------------
while IFS= read -r -d '' file; do

    ext="${file##*.}"
    rel_path="${file#$BASE_DIR/}"

    # Check directory structure matches YYYY/MM
    if ! [[ "$rel_path" =~ ^([0-9]{4})/([0-9]{2})/ ]]; then
        log "SKIP [structure] $file"
        (( count_skipped_structure++ )) || true
        continue
    fi

    # Check file type
    if ! is_photo "$ext"; then
        log "SKIP [type:$ext] $file"
        (( count_skipped_type++ )) || true
        continue
    fi

    (( count_processed++ )) || true

    # Check for existing DateTimeOriginal
    existing_date=$(get_exif_date "$file")

    if [[ -n "$existing_date" ]]; then
        (( count_has_date++ )) || true
        continue
    fi

    # --- File is missing DateTimeOriginal ---
    (( count_missing++ )) || true

    if [[ "$MODE" == "report" ]]; then
        log "MISSING $file"
        continue
    fi

    # --- Update mode: determine best date source ---
    new_date=""
    date_source=""

    # Try filename first
    new_date=$(parse_date_from_filename "$file")
    if [[ -n "$new_date" ]]; then
        date_source="filename"
    else
        # Fall back to directory
        new_date=$(parse_date_from_dir "$file")
        if [[ -n "$new_date" ]]; then
            date_source="directory"
        fi
    fi

    if [[ -z "$new_date" ]]; then
        log "ERROR [no date source] $file"
        (( count_errors++ )) || true
        continue
    fi

    # Preserve mtime before exiftool modifies the file
    mtime=$(stat -c '%y' "$file")

    # Write DateTimeOriginal (and CreateDate for broader compatibility)
    if exiftool -overwrite_original \
        -DateTimeOriginal="$new_date" \
        -CreateDate="$new_date" \
        "$file" &>/dev/null; then

        # Restore mtime
        touch -d "$mtime" "$file"

        log "UPDATED [$date_source] $new_date  $file"
        if [[ "$date_source" == "filename" ]]; then
            (( count_updated_filename++ )) || true
        else
            (( count_updated_dir++ )) || true
        fi
    else
        log "ERROR [exiftool write failed] $file"
        (( count_errors++ )) || true
    fi

done < <(find "$BASE_DIR" -type f -print0 | sort -z)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "========================================"
log "Summary"
log "========================================"
log "Files processed (photo types in YYYY/MM) : $count_processed"
log "Already had DateTimeOriginal             : $count_has_date"
log "Missing DateTimeOriginal                 : $count_missing"
if [[ "$MODE" == "update" ]]; then
log "  Updated from filename                  : $count_updated_filename"
log "  Updated from directory                 : $count_updated_dir"
log "  Errors (could not determine date)      : $count_errors"
fi
log "Skipped (outside YYYY/MM structure)      : $count_skipped_structure"
log "Skipped (unsupported file type)          : $count_skipped_type"
log "Completed : $(date)"
log "========================================"
