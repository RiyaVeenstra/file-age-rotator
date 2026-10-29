# file-age-rotator

A small Bash library that deletes files in a directory whose modification time (mtime) is older than a specified duration.

## Usage

```sh
source ./file_age_rotator.sh

# Delete files older than 7 days (third arg = reference epoch; defaults to now).
far_rotate "/var/log/app" "7d"

# See what would be deleted without touching anything.
far_rotate_dry_run "/var/log/app" "7d"

# Deterministic call with an explicit reference timestamp.
far_rotate "/var/log/app" "12h" 1700000000
```

## Exported functions

- `far_rotate DIR DURATION [NOW_EPOCH]` — deletes files under `DIR` whose mtime is older than `DURATION` seconds from `NOW_EPOCH`. If `NOW_EPOCH` is omitted, `date +%s` is used.
- `far_rotate_dry_run DIR DURATION [NOW_EPOCH]` — prints the path of each file that would be deleted; deletes nothing.
- `far_parse_duration STRING` — parses `30s`, `10m`, `2h`, `7d`, or a bare integer (seconds) into a number of seconds. Prints the number to stdout.
- `far_is_older_than FILE CUTOFF_EPOCH` — returns exit 0 if `FILE`'s mtime is strictly less than `CUTOFF_EPOCH`, exit 1 otherwise.

## Why

Log and cache directories fill up. The usual remedy is a cron job calling `find ... -mtime`, but that approach hides the logic in a long command line and is awkward to unit-test. This library exposes the rotation as plain functions that take the reference timestamp as an argument, so the behaviour can be verified deterministically.

The trade-off: there is no built-in archiving, no glob filter, and no recursive deletion of directories. It operates on files only, recursively beneath the given directory. If you need zip archiving or filename patterns, wrap `far_rotate_dry_run` and post-process its output.

## Edge cases

- **Boundary semantics.** A file whose mtime is *exactly* equal to the cutoff is **not** deleted — the comparison is strict (`mtime < cutoff`).
- **Duration units.** Only `s`, `m`, `h`, `d` (case-insensitive) and bare integers are accepted. Anything else exits non-zero.
- **Non-regular files.** Symlinks and directories are never deleted; only `-type f` matches from `find`.
- **stat portability.** The implementation supports both GNU `stat -c %Y` and BSD `stat -f %m` so it works under glibc, musl, and BusyBox `stat`.

## Testing

```sh
bash test_file_age_rotator.sh
```

All tests use a fixed reference epoch and set explicit mtimes with `touch -d @EPOCH` (or `touch -t` on platforms without `-d`), so they are deterministic and never depend on wall-clock time.
