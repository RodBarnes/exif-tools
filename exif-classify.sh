#!/bin/bash
# exif-classify.sh
#
# Tests filename classification logic for use in exif-photos.sh.
# Walks a directory structure and classifies each photo filename as:
#   DATE-LIKE     -- contains a recognizable date/timestamp pattern
#   CAMERA-PREFIX -- starts with a known camera-generated prefix (IMG_, DSC, etc.)
#   CAMERA-SERIAL -- matches a camera/scanner sequential numbering pattern
#   DESCRIPTIVE   -- appears to be a human-given name
#
# No files are modified. Output goes to terminal and log file.
#
# Usage:
#   exif-classify.sh <base_dir> [logfile]

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <base_dir> [logfile]"
    exit 1
fi

BASE_DIR="$1"
LOGFILE="${2:-exif_classify_$(date +%Y%m%d_%H%M%S).log}"

if [[ ! -d "$BASE_DIR" ]]; then
    echo "Error: base directory '$BASE_DIR' does not exist"
    exit 1
fi

# ---------------------------------------------------------------------------
# Supported photo extensions (all lowercase)
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
count_date_like=0
count_camera_prefix=0
count_camera_serial=0
count_descriptive=0
count_skipped_structure=0
count_skipped_type=0

# ---------------------------------------------------------------------------
# Helper: check if extension is a supported photo type
# ---------------------------------------------------------------------------
is_photo() {
    local ext="${1,,}"
    for e in $PHOTO_EXTS; do
        [[ "$ext" == "$e" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Helper: classify a filename (without extension)
# Prints one of:
#   DATE-LIKE [pattern:YYYY-MM-DD HH.MM.SS]
#   DATE-LIKE [pattern:YYYYMMDD_HHMMSS]
#   DATE-LIKE [pattern:YYYYMMDD]
#   DATE-LIKE [pattern:MMDDYY]
#   CAMERA-PREFIX [prefix:DSC|SAM_|downsized|Attach|IMG_|IMAG|DSCN|MVI_|VID_|MOV_|P[0-9]]
#   CAMERA-SERIAL [pattern:NNN_NNNN|NNN_NNA|imgNN|NNNNAsuffix|NNNN]
#   DESCRIPTIVE
# ---------------------------------------------------------------------------
classify_filename() {
    local base="$1"
    local base_lower="${base,,}"
    local base_upper="${base^^}"

    # --- Date patterns (checked first, highest confidence) ---
    # NOTE: Complex patterns must be stored in variables for bash [[ =~ ]] to handle them correctly

    # YYYY-MM-DD HH.MM.SS or YYYY-MM-DD_HH.MM.SS with optional sequence suffix
    # e.g. 2013-09-04 12.09.33, 2013-09-13_12.46.04, 2016-02-27 20.26.15-1
    local pat_datetime='^[0-9]{4}-[0-9]{2}-[0-9]{2}[_ ][0-9]{2}\.[0-9]{2}\.[0-9]{2}'
    if [[ "$base" =~ $pat_datetime ]]; then
        echo "DATE-LIKE [pattern:YYYY-MM-DD HH.MM.SS]"
        return
    fi

    # YYYYMMDD_HHMMSS
    local pat_yyyymmdd_hhmmss='[0-9]{4}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])_([01][0-9]|2[0-3])[0-5][0-9][0-5][0-9]'
    if [[ "$base" =~ $pat_yyyymmdd_hhmmss ]]; then
        echo "DATE-LIKE [pattern:YYYYMMDD_HHMMSS]"
        return
    fi

    # YYYYMMDD (year 1800-2100, valid month, valid day)
    local pat_yyyymmdd='(1[89][0-9]{2}|20[0-9]{2}|21[0]{2})(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])'
    if [[ "$base" =~ $pat_yyyymmdd ]]; then
        echo "DATE-LIKE [pattern:YYYYMMDD]"
        return
    fi

    # MMDDYY — valid month (01-12), valid day (01-31), any two-digit year
    # Must be exactly six contiguous digits surrounded by non-digits or string boundary
    local pat_mmddyy='(^|[^0-9])(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[0-9]{2}([^0-9]|$)'
    if [[ "$base" =~ $pat_mmddyy ]]; then
        echo "DATE-LIKE [pattern:MMDDYY]"
        return
    fi

    # --- Camera prefix patterns ---
    # DSC: DSC followed by optional letter (e.g. DSCF for Fujifilm), then digits, optional trailing letter
    # Covers: DSC00273, DSC00273a, DSCF0001, DSCF0001a
    if [[ "$base_upper" =~ ^DSC[A-Z]?[0-9]+[A-Z]?$ ]]; then
        echo "CAMERA-PREFIX [prefix:DSC]"
        return
    fi
    # SAM_NNNN — Samsung camera (e.g. SAM_1433)
    if [[ "$base_upper" =~ ^SAM_[0-9]+ ]]; then
        echo "CAMERA-PREFIX [prefix:SAM_]"
        return
    fi
    # downsized — resized camera images (e.g. downsized950913031552, downsized_1026031935)
    if [[ "$base_lower" =~ ^downsized ]]; then
        echo "CAMERA-PREFIX [prefix:downsized]"
        return
    fi
    # Attach — email attachment naming (e.g. Attach7290)
    if [[ "$base_lower" =~ ^attach[0-9]+ ]]; then
        echo "CAMERA-PREFIX [prefix:Attach]"
        return
    fi
    for prefix in "IMG_" "IMAG" "DSCN" "MVI_" "VID_" "MOV_" "P[0-9]"; do
        if [[ "$base_upper" =~ ^$prefix ]]; then
            echo "CAMERA-PREFIX [prefix:${prefix}]"
            return
        fi
    done

    # --- Camera serial patterns ---
    # NOTE: More specific patterns must come before broader ones

    # NNN_NNNN — Olympus/Fuji style (e.g. 100_0626, 106_0665, 100_0714_a)
    # Three digits, underscore, four digits, optional underscore+letter suffix
    if [[ "$base" =~ ^[0-9]{3}_[0-9]{4}(_[A-Za-z])?$ ]]; then
        echo "CAMERA-SERIAL [pattern:NNN_NNNN]"
        return
    fi

    # NNN_NNA — film scanner frame numbers (e.g. 009_6A, 022_19A, 002_00A, 003_0A)
    # digits, underscore, digits, optional letter — must come AFTER NNN_NNNN
    if [[ "$base" =~ ^[0-9]+_[0-9]+[A-Za-z]?$ ]]; then
        echo "CAMERA-SERIAL [pattern:NNN_NNA]"
        return
    fi

    # imgNN — scanner sequential (e.g. 2img08, img02, img26)
    # optional leading digit, 'img', digits
    if [[ "$base_lower" =~ ^[0-9]?img[0-9]+$ ]]; then
        echo "CAMERA-SERIAL [pattern:imgNN]"
        return
    fi

    # NNNNAsuffix — film roll/frame (e.g. 0310A, 0311B, 0312Alow, 0312Blow2)
    # Four digits, one letter, optional alphanumeric suffix
    if [[ "$base" =~ ^[0-9]{4}[A-Za-z][A-Za-z0-9]*$ ]]; then
        echo "CAMERA-SERIAL [pattern:NNNNAsuffix]"
        return
    fi

    # NNN+ — plain sequential numbers, 3 or more digits, no letters (e.g. 013, 047, 7780, 7799)
    if [[ "$base" =~ ^[0-9]{3,}$ ]]; then
        echo "CAMERA-SERIAL [pattern:NNN]"
        return
    fi

    # --- Default: descriptive ---
    echo "DESCRIPTIVE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "========================================"
log "exif-classify.sh"
log "Base dir : $BASE_DIR"
log "Log file : $LOGFILE"
log "Started  : $(date)"
log "========================================"
log ""

while IFS= read -r -d '' file; do

    ext="${file##*.}"
    rel_path="${file#$BASE_DIR/}"

    # Must be in YYYY/MM structure
    if ! [[ "$rel_path" =~ ^([0-9]{4})/([0-9]{2})/ ]]; then
        (( count_skipped_structure++ )) || true
        continue
    fi

    # Must be a supported photo type
    if ! is_photo "$ext"; then
        (( count_skipped_type++ )) || true
        continue
    fi

    base=$(basename "$file")
    base_noext="${base%.*}"

    classification=$(classify_filename "$base_noext")

    log "$classification  $file"

    case "$classification" in
        DATE-LIKE*)       (( count_date_like++ ))      || true ;;
        CAMERA-PREFIX*)   (( count_camera_prefix++ ))  || true ;;
        CAMERA-SERIAL*)   (( count_camera_serial++ ))  || true ;;
        DESCRIPTIVE*)     (( count_descriptive++ ))    || true ;;
    esac

done < <(find "$BASE_DIR" -type f -print0 | sort -z)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "========================================"
log "Summary"
log "========================================"
log "Date-like filenames    : $count_date_like"
log "Camera-prefix filenames: $count_camera_prefix"
log "Camera-serial filenames: $count_camera_serial"
log "Descriptive filenames  : $count_descriptive"
log "Skipped (structure)    : $count_skipped_structure"
log "Skipped (type)         : $count_skipped_type"
log "Completed : $(date)"
log "========================================"
