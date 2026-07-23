#!/bin/bash
# find-duplicates.sh
#
# For each file in <target_dir>, searches <search_root> for other files with
# the same filename (mirroring `find <search_root> -name <filename>`), then
# confirms whether they are true duplicates by comparing sha256 checksums.
#
# Usage:
#   find-duplicates.sh report <target_dir> [search_root] [logfile]
#   find-duplicates.sh dedup  <target_dir> [search_root] [logfile]
#
# Modes:
#   report -- List classifications; no changes made
#   dedup  -- Same as report, but also DELETES each confirmed duplicate found
#             in target_dir (the file in target_dir is removed; the matching
#             file elsewhere — inside or outside target_dir — is kept).
#             Name collisions and unique files are never deleted.
#
# search_root defaults to "staging/bard" if not given.
#
# Classifies each file in target_dir as one of:
#   UNIQUE          -- no other file with the same name found anywhere in search_root
#   DUPLICATE       -- same-named file(s) found and at least one is byte-identical (sha256)
#   NAME COLLISION  -- same-named file(s) found elsewhere, but none match by content
#                      (needs manual review — never deleted)

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 report|dedup <target_dir> [search_root] [logfile]"
    exit 1
fi

MODE="$1"
TARGET_DIR="$2"
SEARCH_ROOT="${3:-staging/bard}"
LOGFILE="${4:-find_duplicates_$(date +%Y%m%d_%H%M%S).log}"

if [[ "$MODE" != "report" && "$MODE" != "dedup" ]]; then
    echo "Error: mode must be 'report' or 'dedup'"
    exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: target directory '$TARGET_DIR' does not exist"
    exit 1
fi

if [[ ! -d "$SEARCH_ROOT" ]]; then
    echo "Error: search root '$SEARCH_ROOT' does not exist"
    exit 1
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    echo "$1" | tee -a "$LOGFILE"
}

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
count_unique=0
count_duplicate=0
count_collision=0
count_deleted=0
count_errors=0

log "========================================"
log "find-duplicates.sh"
log "Mode        : $MODE"
log "Target dir  : $TARGET_DIR"
log "Search root : $SEARCH_ROOT"
log "Log file    : $LOGFILE"
log "Started     : $(date)"
log "========================================"
log ""

# ---------------------------------------------------------------------------
# Main: for each file in target_dir, find same-named files in search_root
# and verify by sha256 whether they're real duplicates
# ---------------------------------------------------------------------------
while IFS= read -r -d '' file; do
    base=$(basename "$file")
    file_sum=""
    match_found=false
    dup_found=false
    last_match=""

    while IFS= read -r -d '' match; do
        # Skip comparing the file to itself (inode comparison, robust
        # regardless of relative/absolute path differences)
        [[ "$match" -ef "$file" ]] && continue

        match_found=true
        last_match="$match"
        if [[ -z "$file_sum" ]]; then
            file_sum=$(sha256sum "$file" | cut -d' ' -f1)
        fi
        match_sum=$(sha256sum "$match" | cut -d' ' -f1)

        if [[ "$file_sum" == "$match_sum" ]]; then
            dup_found=true
            (( count_duplicate++ )) || true

            if [[ "$MODE" == "dedup" ]]; then
                if rm -- "$file"; then
                    log "DELETED  $file  ==  $match"
                    (( count_deleted++ )) || true
                else
                    log "ERROR [delete failed]  $file"
                    (( count_errors++ )) || true
                fi
            else
                log "DUPLICATE  $file  ==  $match"
            fi
            break
        fi
    done < <(find "$SEARCH_ROOT" -name "$base" -print0)

    if ! $dup_found; then
        if $match_found; then
            log "NAME COLLISION  $file  (Conflict: $last_match)"
            (( count_collision++ )) || true
        else
            log "UNIQUE  $file"
            (( count_unique++ )) || true
        fi
    fi

done < <(find "$TARGET_DIR" -type f -print0 | sort -z)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "========================================"
log "Summary"
log "========================================"
log "Unique (no name match anywhere)      : $count_unique"
log "Duplicate (confirmed by sha256)      : $count_duplicate"
log "Name collision (needs manual review) : $count_collision"
if [[ "$MODE" == "dedup" ]]; then
log "Deleted                               : $count_deleted"
log "Errors                                : $count_errors"
fi
log "Completed : $(date)"
log "========================================"
