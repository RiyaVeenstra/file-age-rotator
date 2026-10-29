#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/file_age_rotator.sh"

# Minimal TAP-like assert.
assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "ok - $label"
    else
        echo "not ok - $label"
        echo "  expected: '$expected'"
        echo "  actual:   '$actual'"
        return 1
    fi
}

# Assert that far_rotate_dry_run deletes only the right files.
# Using a fixed reference epoch (1000000000 = 2001-09-09T01:46:40Z) so the test is
# deterministic regardless of when it runs.
NOW=1000000000

# --- far_parse_duration ---
assert_eq "3600" "$(far_parse_duration '1h')" 'parse 1h'
assert_eq "86400" "$(far_parse_duration '1d')" 'parse 1d'
assert_eq "600" "$(far_parse_duration '10m')" 'parse 10m'
assert_eq "45" "$(far_parse_duration '45s')" 'parse 45s'
assert_eq "3600" "$(far_parse_duration '1H')" 'parse 1H uppercase'
assert_eq "90" "$(far_parse_duration '90')" 'parse bare integer as seconds'

# --- far_is_older_than ---
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Create a file with an mtime of NOW-100 (clearly older than NOW-50).
OLD_FILE="$TMPDIR/old.log"
: > "$OLD_FILE"
touch -d "@$(( NOW - 100 ))" "$OLD_FILE" 2>/dev/null || touch -t "$(date -r "$(( NOW - 100 ))" +%Y%m%d%H%M.%S)" "$OLD_FILE"
assert_eq 0 "$(far_is_older_than "$OLD_FILE" "$(( NOW - 50 ))"; echo $?)" 'old file is older than cutoff'

NEW_FILE="$TMPDIR/new.log"
: > "$NEW_FILE"
touch -d "@$(( NOW - 10 ))" "$NEW_FILE" 2>/dev/null || touch -t "$(date -r "$(( NOW - 10 ))" +%Y%m%d%H%M.%S)" "$NEW_FILE"
assert_eq 1 "$(far_is_older_than "$NEW_FILE" "$(( NOW - 50 ))"; echo $?)" 'new file is NOT older than cutoff'

# --- far_rotate_dry_run ---
# Make two more files: one old, one new.
OLD2="$TMPDIR/old2.log"
NEW2="$TMPDIR/new2.log"
: > "$OLD2"; touch -d "@$(( NOW - 200 ))" "$OLD2" 2>/dev/null || touch -t "$(date -r "$(( NOW - 200 ))" +%Y%m%d%H%M.%S)" "$OLD2"
: > "$NEW2"; touch -d "@$(( NOW - 5 ))"   "$NEW2" 2>/dev/null || touch -t "$(date -r "$(( NOW - 5 ))" +%Y%m%d%H%M.%S)" "$NEW2"

DRY="$(far_rotate_dry_run "$TMPDIR" '60' "$NOW" | sort)"
EXPECTED="$(printf '%s\n%s\n' "$OLD2" "$OLD_FILE" | sort)"
assert_eq "$EXPECTED" "$DRY" 'dry-run lists only old files'

# --- far_rotate deletes ---
far_rotate "$TMPDIR" '60' "$NOW"
assert_eq 1 "$( [[ -f "$NEW_FILE" ]] && echo 1 || echo 0 )" 'new file still present after rotate'
assert_eq 0 "$( [[ -f "$OLD_FILE" ]] && echo 1 || echo 0 )" 'old file removed after rotate'
assert_eq 1 "$( [[ -f "$NEW2" ]] && echo 1 || echo 0 )" 'new2 still present after rotate'
assert_eq 0 "$( [[ -f "$OLD2" ]] && echo 1 || echo 0 )" 'old2 removed after rotate'

# --- edge: empty directory ---
EMPTY="$TMPDIR/empty"
mkdir -p "$EMPTY"
far_rotate "$EMPTY" '60' "$NOW"  # should not error
assert_eq '' "$(far_rotate_dry_run "$EMPTY" '60' "$NOW")" 'empty dir yields no output'

# --- edge: nonexistent directory ---
assert_eq 1 "$(far_rotate "/nonexistent_dir_12345" '60' "$NOW" >/dev/null 2>&1; echo $?)" 'nonexistent dir returns error'

# --- edge: invalid duration ---
assert_eq 1 "$(far_parse_duration 'abc' >/dev/null 2>&1; echo $?)" 'invalid duration returns error'

# --- edge: exactly at boundary (mtime == cutoff) ---
BOUNDARY="$TMPDIR/boundary.log"
: > "$BOUNDARY"
CUTOFF=$(( NOW - 30 ))
touch -d "@$CUTOFF" "$BOUNDARY" 2>/dev/null || touch -t "$(date -r "$CUTOFF" +%Y%m%d%H%M.%S)" "$BOUNDARY"
# far_is_older_than uses strict -lt, so a file AT the cutoff is NOT considered older.
assert_eq 1 "$(far_is_older_than "$BOUNDARY" "$CUTOFF"; echo $?)" 'file at boundary is not older (strict lt)'

# --- edge: subdirectories are not deleted, only files within ---
SUBDIR="$TMPDIR/sub"
mkdir -p "$SUBDIR"
SUB_OLD="$SUBDIR/sub_old.log"
: > "$SUB_OLD"
touch -d "@$(( NOW - 1000 ))" "$SUB_OLD" 2>/dev/null || touch -t "$(date -r "$(( NOW - 1000 ))" +%Y%m%d%H%M.%S)" "$SUB_OLD"
far_rotate "$SUBDIR" '60' "$NOW"
assert_eq 0 "$( [[ -f "$SUB_OLD" ]] && echo 1 || echo 0 )" 'file in subdir deleted'
assert_eq 1 "$( [[ -d "$SUBDIR" ]] && echo 1 || echo 0 )" 'subdir itself still exists'

echo 'All tests passed.'
