#!/usr/bin/env bash
# file-age-rotator: delete files older than a specified duration based on mtime.
# Public functions: far_rotate, far_rotate_dry_run
set -euo pipefail

# Parse a duration string like "7d", "12h", "30m", "600s", or "86400" into seconds.
# A bare integer is treated as seconds. This keeps the interface simple while still
# allowing the common "days/hours/minutes" shorthand used in log-rotation scripts.
# Returns the number of seconds on stdout. Exits non-zero on malformed input.
far_parse_duration() {
    local input="$1"
    local value unit seconds
    # Strip trailing whitespace so a stray space after the unit is not fatal.
    input="${input%%[[:space:]]}"
    if [[ ! "$input" =~ ^[0-9]+[smhdSMHD]?$ ]]; then
        echo "far_parse_duration: invalid duration '$input'" >&2
        return 1
    fi
    if [[ "$input" =~ ^([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    value="${input%[smhdSMHD]}"
    unit="${input: -1}"
    case "$unit" in
        s|S) seconds=$(( value )) ;;
        m|M) seconds=$(( value * 60 )) ;;
        h|H) seconds=$(( value * 3600 )) ;;
        d|D) seconds=$(( value * 86400 )) ;;
        *)   echo "far_parse_duration: unknown unit '$unit'" >&2; return 1 ;;
    esac
    echo "$seconds"
}

# Determine whether a file is older than a cutoff timestamp.
# Uses stat(1) to read mtime. We support both GNU stat (-c %Y) and BSD stat (-f %m)
# because the tests may run in either a glibc or musl/BusyBox container.
# Args: filepath  cutoff_epoch_seconds
# Returns 0 (true, file is older) or 1 (false, file is not older).
far_is_older_than() {
    local file="$1"
    local cutoff="$2"
    local mtime
    if [[ ! -f "$file" ]]; then
        echo "far_is_older_than: not a regular file: '$file'" >&2
        return 1
    fi
    if stat -c '%Y' "$file" >/dev/null 2>&1; then
        mtime="$(stat -c '%Y' "$file")"
    else
        mtime="$(stat -f '%m' "$file")"
    fi
    [[ "$mtime" -lt "$cutoff" ]]
}

# Core driver. Walks a directory and applies an action to files older than cutoff.
# Actions: "delete" (rm -f) or "dry-run" (print only, no deletion).
# The cutoff is passed in explicitly to make this function trivially testable
# without touching wall-clock time.
far_apply() {
    local dir="$1"
    local cutoff="$2"
    local action="$3"
    local f
    if [[ ! -d "$dir" ]]; then
        echo "far_apply: not a directory: '$dir'" >&2
        return 1
    fi
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        if far_is_older_than "$f" "$cutoff"; then
            if [[ "$action" == "delete" ]]; then
                rm -f "$f"
            else
                echo "$f"
            fi
        fi
    done < <(find "$dir" -type f -print)
}

# Delete files older than a given duration from a directory.
# Args: dir  duration_string  reference_epoch_seconds
# The reference epoch is taken as a parameter so that tests are deterministic.
far_rotate() {
    local dir="$1"
    local duration="$2"
    local now="${3:-$(date +%s)}"
    local seconds cutoff
    seconds="$(far_parse_duration "$duration")"
    cutoff=$(( now - seconds ))
    far_apply "$dir" "$cutoff" "delete"
}

# Print names of files that WOULD be deleted, without deleting them.
# Args: dir  duration_string  reference_epoch_seconds
far_rotate_dry_run() {
    local dir="$1"
    local duration="$2"
    local now="${3:-$(date +%s)}"
    local seconds cutoff
    seconds="$(far_parse_duration "$duration")"
    cutoff=$(( now - seconds ))
    far_apply "$dir" "$cutoff" "dry-run"
}
