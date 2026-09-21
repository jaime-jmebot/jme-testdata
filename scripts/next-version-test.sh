#!/usr/bin/env bash
#
# Checks the versions computed by scripts/next-version.sh: the day in YYYY-MM-DD
# form, the daily counter of the releases and the snapshot naming.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
next_version="${script_dir}/next-version.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

today="2026-09-19"
taken_file="${tmp_dir}/taken.txt"
failures=0

# writes the given versions, one per line, to the file used with --taken
set_taken() {
    : > "${taken_file}"
    local version
    for version in "$@"; do
        printf '%s\n' "${version}" >> "${taken_file}"
    done
}

check() { # expected version, then the arguments of the script
    local expected="$1"
    shift
    local actual
    if ! actual="$(bash "${next_version}" "$@")"; then
        printf 'FAIL: the script failed for: %s\n' "$*" >&2
        failures=$((failures + 1))
        return 0
    fi
    if [ "${actual}" != "${expected}" ]; then
        printf 'FAIL: expected %s but got %s from: %s\n' "${expected}" "${actual}" "$*" >&2
        failures=$((failures + 1))
    else
        printf 'ok: %s <- %s\n' "${actual}" "$*"
    fi
}

check_fails() { # arguments of the script, expected to be rejected
    if bash "${next_version}" "$@" > /dev/null 2>&1; then
        printf 'FAIL: the script should have failed for: %s\n' "$*" >&2
        failures=$((failures + 1))
    else
        printf 'ok: rejected <- %s\n' "$*"
    fi
}

# first release of the day
set_taken
check "${today}" --date "${today}" --taken "${taken_file}"

# second and third release of the same day
set_taken "${today}"
check "${today}-2" --date "${today}" --taken "${taken_file}"

set_taken "${today}" "${today}-2"
check "${today}-3" --date "${today}" --taken "${taken_file}"

# the counter is not the number of versions, it is the highest one plus one
set_taken "${today}-2" "${today}-7"
check "${today}-8" --date "${today}" --taken "${taken_file}"

# other days, legacy v* tags and unrelated tags don't shift the counter
set_taken "2026-09-18" "2026-09-18-4" "2026-09-20" "v3.10.0" "${today}-rc1"
check "${today}" --date "${today}" --taken "${taken_file}"

# the counter resets on the next day
set_taken "2026-09-19" "2026-09-19-5"
check "2026-09-20" --date "2026-09-20" --taken "${taken_file}"

# snapshots use the day as version too
check "${today}-SNAPSHOT" --date "${today}" --snapshot

# invalid input is rejected
check_fails --date "2026-9-19"
check_fails --date "today"
check_fails --taken
check_fails --taken "${tmp_dir}/does-not-exist"
check_fails --unknown-option

# the tags of the checkout are used when no file is given
repo="${tmp_dir}/repo"
git -c init.defaultBranch=master init -q "${repo}"
git -C "${repo}" -c user.email=test@example.com -c user.name=Test \
    commit -q --allow-empty -m 'initial commit'
git -C "${repo}" tag 'v3.10.0'

check_repo() { # expected version, repository
    local expected="$1"
    local directory="$2"
    local actual
    actual="$(cd "${directory}" && bash "${next_version}" --date "${today}")"
    if [ "${actual}" != "${expected}" ]; then
        printf 'FAIL: expected %s but got %s from the tags of %s\n' \
            "${expected}" "${actual}" "${directory}" >&2
        failures=$((failures + 1))
    else
        printf 'ok: %s <- git tags\n' "${actual}"
    fi
}

check_repo "${today}" "${repo}"
git -C "${repo}" tag "${today}"
check_repo "${today}-2" "${repo}"
git -C "${repo}" tag "${today}-2"
check_repo "${today}-3" "${repo}"

if [ "${failures}" -ne 0 ]; then
    printf '%s check(s) failed\n' "${failures}" >&2
    exit 1
fi

printf 'all checks passed\n'
