#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the Star OS live ISO prototype (milestone M0.1).
#
# The archiso profile is assembled from the releng profile of the installed,
# pinned archiso version plus the Star OS overlay in distro/archiso/staros/
# (ADR-0001), with packages pinned to the baseline snapshot (ADR-0002). Must run
# as root on Arch Linux; see docs/development/building.md.
#
# Writes to out/: the ISO, SHA256SUMS, packages.x86_64.txt, build-info.txt and
# profile.tar.gz (the assembled profile, for review). Scratch space is build/.

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

build_dir="$staros_repo_root/build"
out_dir="$staros_repo_root/out"
overlay_dir="$staros_repo_root/distro/archiso/staros"
releng_dir=/usr/share/archiso/configs/releng
mirrorlist_include_re='^Include[[:space:]]*=[[:space:]]*/etc/pacman\.d/mirrorlist[[:space:]]*$'
boot_title_from='Arch Linux install medium'
boot_title_to='Star OS live (prototype)'

check_host() {
    local want have
    [[ -f /etc/arch-release ]] || die "must run on Arch Linux (see docs/development/building.md)"
    ((EUID == 0)) || die "must run as root (mkarchiso requirement)"
    command -v mkarchiso >/dev/null || die "mkarchiso not found; install archiso"
    want=$(staros_archiso_version)
    read -r _ have < <(pacman -Q archiso)
    [[ $have == "$want" ]] \
        || die "archiso $have is installed, but the overlay is validated against $want" \
               "(distro/archiso/ARCHISO_VERSION). Use scripts/ci/prepare-arch-build-host.sh," \
               "or update ARCHISO_VERSION in a reviewed change."
    [[ -d $releng_dir ]] || die "$releng_dir not found"
}

# Pins the profile's repositories to the baseline snapshot (ADR-0002).
pin_repositories() {
    local pacman_conf=$1 server count
    server=$(staros_archive_server "$(staros_baseline_date)")
    count=$(grep -cE "$mirrorlist_include_re" "$pacman_conf" || true)
    ((count >= 2)) \
        || die "expected releng's pacman.conf to include the mirrorlist for [core] and [extra]," \
               "found $count include lines; review the releng format before building"
    sed -i -E "s|$mirrorlist_include_re|Server = $server|" "$pacman_conf"
    log "Repositories pinned to $server ($count sections)"
}

retitle_boot_entries() {
    local profile=$1 file count total=0
    local -a files
    mapfile -t files < <(find "$profile/efiboot" "$profile/syslinux" "$profile/grub" \
        -type f \( -name '*.conf' -o -name '*.cfg' \) 2>/dev/null | sort)
    for file in "${files[@]}"; do
        count=$(grep -c -- "$boot_title_from" "$file" || true)
        ((count > 0)) || continue
        sed -i "s/$boot_title_from/$boot_title_to/g" "$file"
        total=$((total + count))
    done
    ((total > 0)) \
        || die "no boot menu entries contain '$boot_title_from'; review the releng format before building"
    log "Boot menu entries renamed ($total):"
    grep -rn -- "$boot_title_to" "${files[@]}" | sed "s|^$profile/|    |"
}

assemble_profile() {
    local profile=$1
    rm -rf -- "$profile"
    mkdir -p -- "$(dirname -- "$profile")"
    cp -a -- "$releng_dir" "$profile"
    cp -a -- "$overlay_dir/airootfs/." "$profile/airootfs/"
    cat -- "$overlay_dir/profiledef.append.sh" >>"$profile/profiledef.sh"
    pin_repositories "$profile/pacman.conf"
    retitle_boot_entries "$profile"
}

write_records() {
    local work=$1 baseline=$2 iso commit
    local -a isos=("$out_dir"/*.iso)
    [[ ${#isos[@]} -eq 1 && -f ${isos[0]} ]] || die "expected exactly one ISO in $out_dir"
    iso=$(basename -- "${isos[0]}")
    commit=${GITHUB_SHA:-$(git -C "$staros_repo_root" rev-parse HEAD 2>/dev/null || echo unknown)}

    pacman -Q --dbpath "$work/x86_64/airootfs/var/lib/pacman" >"$out_dir/packages.x86_64.txt"
    (cd -- "$out_dir" && sha256sum -- "$iso" >SHA256SUMS)
    tar -C "$build_dir" -czf "$out_dir/profile.tar.gz" profile
    {
        printf 'iso=%s\n' "$iso"
        printf 'git_commit=%s\n' "$commit"
        printf 'arch_snapshot_date=%s\n' "$baseline"
        printf 'archiso=%s\n' "$(pacman -Q archiso)"
        printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
        printf 'built_at=%s\n' "$(date -u +%FT%TZ)"
        printf 'build_host_kernel=%s\n' "$(uname -r)"
        printf 'iso_package_count=%s\n' "$(wc -l <"$out_dir/packages.x86_64.txt")"
    } >"$out_dir/build-info.txt"
}

main() {
    local baseline profile="$build_dir/profile" work="$build_dir/work"
    check_host
    baseline=$(staros_baseline_date)
    export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$staros_repo_root" log -1 --format=%ct)}
    [[ $SOURCE_DATE_EPOCH =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH must be a Unix timestamp"

    log "Assembling profile: $releng_dir (archiso $(staros_archiso_version)) + $overlay_dir"
    assemble_profile "$profile"

    rm -rf -- "$work" "$out_dir"
    mkdir -p -- "$out_dir"
    log "Running mkarchiso"
    mkarchiso -v -w "$work" -o "$out_dir" "$profile"

    write_records "$work" "$baseline"
    log "Build records:"
    cat -- "$out_dir/build-info.txt"
    cat -- "$out_dir/SHA256SUMS"
}

main "$@"
