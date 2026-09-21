#!/usr/bin/env bash
#
# Computes the next version for the date based versioning scheme used by
# .github/workflows/release.yml and .github/workflows/snapshot.yml.
#
# A version is the day it is published on, written as YYYY-MM-DD. Several
# releases on the same day are numbered, and the counter resets the next day:
#
#   2026-09-19, 2026-09-19-2, 2026-09-19-3, then 2026-09-20, 2026-09-20-2, ...
#
# Usage:
#   scripts/next-version.sh              the next release version, numbered
#                                        against the git tags that already exist
#   scripts/next-version.sh --snapshot   the snapshot version of the day
#                                        (<YYYY-MM-DD>-SNAPSHOT)
#
# Options:
#   --date YYYY-MM-DD   use that day instead of the current UTC day
#   --taken FILE        read the versions already used that day from FILE, one
#                       per line, instead of looking at the git tags
#   -h, --help          print this help
#
# The version is printed on stdout, messages go to stderr.
#
# Snapshots are republished by every commit, like a regular Maven snapshot, so
# they need no counter: all the commits of a day update the same
# <YYYY-MM-DD>-SNAPSHOT version. Release versions are immutable and have to stay
# unique, hence the counter.

set -euo pipefail

day="$(date -u +%Y-%m-%d)"
snapshot="no"
taken_file=""
look_at_git_tags="yes"

die() {
    printf 'next-version: %s\n' "$1" >&2
    exit 2
}

usage() {
    cat <<'EOF'
Usage: scripts/next-version.sh [--snapshot] [--date YYYY-MM-DD] [--taken FILE]

Computes the next version for the date based versioning scheme: the day in
YYYY-MM-DD form, numbered with a counter when several releases happen on the same
day (2026-09-19, 2026-09-19-2, ...). The counter resets the next day.

Options:
  --snapshot        print the snapshot version of the day (<YYYY-MM-DD>-SNAPSHOT)
                    instead of a release version
  --date YYYY-MM-DD use that day instead of the current UTC day
  --taken FILE      read the versions already used that day from FILE, one per
                    line, instead of looking at the git tags
  -h, --help        print this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --snapshot)
            snapshot="yes"
            shift
            ;;
        --date)
            [ "$#" -ge 2 ] || die 'option --date needs a value'
            day="$2"
            shift 2
            ;;
        --taken)
            [ "$#" -ge 2 ] || die 'option --taken needs a file'
            taken_file="$2"
            look_at_git_tags="no"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1 (see --help)"
            ;;
    esac
done

case "${day}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "not a YYYY-MM-DD day: ${day}" ;;
esac

if [ "${snapshot}" = "yes" ]; then
    printf '%s\n' "${day}-SNAPSHOT"
    exit 0
fi

# Highest counter among the versions of that day, 0 when there is none yet.
highest=0

record() {
    local version="$1"
    local counter

    case "${version}" in
        "${day}")
            counter=1
            ;;
        "${day}"-[0-9]*)
            counter="${version#"${day}"-}"
            # Ignore anything that is not a plain number, for instance a
            # 2026-09-19-rc1 style tag.
            case "${counter}" in
                ''|*[!0-9]*) return 0 ;;
            esac
            ;;
        *)
            return 0
            ;;
    esac

    if [ "${counter}" -gt "${highest}" ]; then
        highest="${counter}"
    fi
}

if [ "${look_at_git_tags}" = "yes" ]; then
    if ! tags="$(git tag --list)"; then
        die 'cannot list the git tags, run this from a git checkout'
    fi
    while IFS= read -r tag; do
        [ -n "${tag}" ] || continue
        record "${tag}"
    done <<< "${tags}"
else
    [ -f "${taken_file}" ] || die "no such file: ${taken_file}"
    while IFS= read -r version; do
        [ -n "${version}" ] || continue
        record "${version}"
    done < "${taken_file}"
fi

if [ "${highest}" -eq 0 ]; then
    printf '%s\n' "${day}"
else
    printf '%s\n' "${day}-$((highest + 1))"
fi
