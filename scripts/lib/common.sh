# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=bash
#
# Shared helpers for Star OS build scripts. Source this file; do not run it.

staros_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '==> %s\n' "$*"
}

# Runs pacman, trying again when it fails: the Arch Linux Archive sometimes
# stalls a download ("Operation too slow"). Packages already downloaded stay
# in pacman's cache, so a new attempt fetches only the missing ones.
staros_pacman() {
    local attempt
    for attempt in 1 2 3; do
        pacman "$@" && return 0
        ((attempt < 3)) || return 1
        log "pacman failed (attempt $attempt of 3); trying again in $((attempt * 30)) s"
        sleep $((attempt * 30))
    done
}

# Prints the package baseline date (YYYY-MM-DD), see ADR-0002.
staros_baseline_date() {
    local file="$staros_repo_root/distro/baseline/ARCH_SNAPSHOT_DATE" date
    [[ -r $file ]] || die "missing $file"
    date=$(<"$file")
    [[ $date =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
        || die "$file must contain a single YYYY-MM-DD date, found '$date'"
    [[ $(date --date="$date" +%F 2>/dev/null) == "$date" ]] \
        || die "$file contains an invalid date '$date'"
    printf '%s\n' "$date"
}

# Prints the pacman Server URL of the Arch Linux Archive snapshot for a date.
staros_archive_server() {
    # $repo and $arch are pacman variables and must stay literal.
    # shellcheck disable=SC2016
    printf 'https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "${1//-//}"
}

# Prints the archiso version the Star OS profile overlay is validated against.
staros_archiso_version() {
    local file="$staros_repo_root/distro/archiso/ARCHISO_VERSION" version
    [[ -r $file ]] || die "missing $file"
    version=$(<"$file")
    [[ $version =~ ^[0-9]+-[0-9]+$ ]] \
        || die "$file must contain a pacman version such as 91-1, found '$version'"
    printf '%s\n' "$version"
}
