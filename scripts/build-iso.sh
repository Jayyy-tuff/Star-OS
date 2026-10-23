#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the Star OS live ISO prototype (milestones M0.1 to M0.3).
#
# The archiso profile is assembled from the releng profile of the installed,
# pinned archiso version plus the Star OS overlay in distro/archiso/staros/
# (ADR-0001) and the Star OS shell files in shell/ (ADR-0008), with packages
# pinned to the baseline snapshot (ADR-0002). Must run as root on Arch Linux;
# see docs/development/building.md.
#
# The Star OS packages (Files, Sun Store; ADR-0009) come from the local
# repository that scripts/build-packages.sh writes: set STAROS_LOCAL_REPO to
# its directory. It is used at build time only; the image's /etc/pacman.conf
# is the pacman package's and does not list it.
#
# Writes to out/: the ISO, SHA256SUMS, packages.x86_64.txt, build-info.txt,
# boot-entries.txt, image-policy.txt and profile.tar.gz (the assembled
# profile, for review). Scratch space is build/.

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

build_dir="$staros_repo_root/build"
out_dir="$staros_repo_root/out"
overlay_dir="$staros_repo_root/distro/archiso/staros"
shell_src="$staros_repo_root/shell"
releng_dir=/usr/share/archiso/configs/releng
mirrorlist_include_re='^Include[[:space:]]*=[[:space:]]*/etc/pacman\.d/mirrorlist[[:space:]]*$'
boot_title_from='Arch Linux install medium'
boot_title_to='Star OS live (prototype)'
# Set by profiledef.append.sh (kernel_params_x86_64); checked on every built
# boot entry. The live medium's writable layer is a RAM disk of this size, so
# that per-user Flatpak apps fit (tmpfs only uses memory for written data).
kernel_params='cow_spacesize=50%'
# The systemd-boot entry of Star Storage (distro/archiso/staros/boot).
storage_entry=01-staros-storage-linux.conf

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
    local profile=$1 file count uefi=0 bios=0
    local -a files
    mapfile -t files < <(find "$profile/efiboot" "$profile/grub" "$profile/syslinux" \
        -type f \( -name '*.conf' -o -name '*.cfg' \) 2>/dev/null | sort)
    for file in "${files[@]}"; do
        count=$(grep -c -- "$boot_title_from" "$file" || true)
        ((count > 0)) || continue
        sed -i "s/$boot_title_from/$boot_title_to/g" "$file"
        case $file in
            "$profile"/syslinux/*) bios=$((bios + count)) ;;
            *) uefi=$((uefi + count)) ;;
        esac
    done
    ((uefi > 0 && bios > 0)) \
        || die "expected to rename UEFI and BIOS boot entries containing '$boot_title_from'," \
               "renamed $uefi UEFI and $bios BIOS entries; review the releng format before building"
    grep -rn -- "$boot_title_to" "${files[@]}" | sed "s|^$profile/||" >"$build_dir/boot-entries.txt"
    log "Boot menu entries renamed ($uefi UEFI, $bios BIOS)"
}

# Star Storage (M0.4, ADR-0011): a systemd-boot entry and a syslinux label
# that keep the live system's changes on the disk labelled STAROS_DATA. The
# releng entry stays the default.
add_storage_boot_entries() {
    local profile=$1
    local entries="$profile/efiboot/loader/entries" sys="$profile/syslinux/archiso_sys-linux.cfg"
    [[ -d $entries && -f $sys ]] \
        || die "expected releng's efiboot/loader/entries and syslinux/archiso_sys-linux.cfg;" \
               "review the releng format before building"
    grep -qx 'default 01-archiso-linux.conf' "$profile/efiboot/loader/loader.conf" \
        || die "expected releng's loader.conf to default to 01-archiso-linux.conf"
    install -m 0644 -- "$overlay_dir/boot/efiboot/loader/entries/$storage_entry" "$entries/"
    { printf '\n'; cat -- "$overlay_dir/boot/syslinux/staros-storage.cfg"; } >>"$sys"
    log "Added the Star Storage boot entries (UEFI $storage_entry, BIOS label starstorage)"
}

# Checks the built Star Storage entries: one UEFI and one BIOS entry with the
# label and a per-build folder, all placeholders replaced.
check_storage_entries() {
    local work=$1 lines line
    lines=$(grep -rhE --include='*.cfg' --include='*.conf' --exclude-dir=airootfs \
        'cow_label=STAROS_DATA' "$work" | sort -u)
    [[ $(grep -c . <<<"$lines") -eq 2 ]] \
        || die "expected 2 Star Storage boot entries (UEFI and BIOS), found:" "$lines"
    ! grep -qE '%[A-Z_]+%' <<<"$lines" \
        || die "unreplaced placeholders in the Star Storage boot entries:" "$lines"
    grep -qE 'cow_directory=persistent_[0-9-]+/x86_64( |$)' <<<"$lines" \
        || die "the Star Storage entries do not name a per-build folder:" "$lines"
    log "Star Storage boot entries:"
    while IFS= read -r line; do
        printf '    %s\n' "$line"
    done <<<"$lines"
}

# Arch's flatpak package ships Flathub as a static system-wide remote. Star OS
# adds Flathub per user, only after the person agrees in Sun Store (ADR-0010),
# so the image does not extract that file. The image policy check verifies
# that no system remote exists.
skip_static_flatpak_remote() {
    local pacman_conf=$1 path=usr/share/flatpak/remotes.d/flathub.flatpakrepo count
    count=$(grep -cx '\[options\]' "$pacman_conf" || true)
    ((count == 1)) || die "expected one [options] section in $pacman_conf, found $count"
    sed -i "/^\[options\]\$/a NoExtract = $path" "$pacman_conf"
    log "Not extracting /$path (Flathub is added per user after consent)"
}

# Adds [staros], the repository of Star OS packages from
# scripts/build-packages.sh, to the profile's pacman.conf. The package list
# may only ask for staros-* packages when STAROS_LOCAL_REPO is set.
add_local_repository() {
    local pacman_conf=$1 repo=${STAROS_LOCAL_REPO:-}
    if [[ -z $repo ]]; then
        if list_entries "$overlay_dir/packages.x86_64.append" | grep -q '^staros-'; then
            die "packages.x86_64.append lists Star OS packages; build them with" \
                "scripts/build-packages.sh and set STAROS_LOCAL_REPO to its output directory"
        fi
        return 0
    fi
    [[ -d $repo ]] || die "STAROS_LOCAL_REPO '$repo' is not a directory"
    repo=$(cd -- "$repo" && pwd)
    [[ -f $repo/staros.db ]] || die "$repo/staros.db not found; run scripts/build-packages.sh"
    ! grep -q '^\[staros\]' "$pacman_conf" || die "$pacman_conf already has a [staros] section"
    printf '\n[staros]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$repo" >>"$pacman_conf"
    log "Added the local repository [staros] at $repo (build time only)"
}

# Checks that every boot entry mkarchiso wrote (UEFI, BIOS, PXE, loopback)
# carries kernel_params.
check_boot_parameters() {
    local work=$1 file line lines=0 missing=0
    local -a files
    mapfile -t files < <(grep -rlE --include='*.cfg' --include='*.conf' --exclude-dir=airootfs \
        'archisobasedir=' "$work" | sort)
    for file in "${files[@]}"; do
        while IFS= read -r line; do
            lines=$((lines + 1))
            if [[ " $line " != *" $kernel_params "* ]]; then
                printf '    %s: %s\n' "${file#"$work"/}" "$line"
                missing=$((missing + 1))
            fi
        done < <(grep -E 'archisobasedir=' -- "$file")
    done
    ((lines > 0 && missing == 0)) \
        || die "expected '$kernel_params' on every boot entry, missing on $missing of $lines" \
               "(${#files[@]} files); review profiledef.append.sh and the releng format"
    log "Boot parameters: '$kernel_params' on all $lines boot entries in ${#files[@]} files"
}

# Prints the profile's boot modes as mkarchiso will read them.
profile_bootmodes() {
    # shellcheck disable=SC2016
    bash -c 'declare -A file_permissions; source "$1/profiledef.sh"; printf "%s\n" "${bootmodes[*]}"' \
        _ "$1" 2>/dev/null
}

# Lines of a list file without comments and blank lines.
list_entries() {
    grep -vE '^[[:space:]]*(#|$)' -- "$1" | sed -E 's/[[:space:]]+$//'
}

# Deletes the releng paths listed in releng-remove.txt. A missing path means
# releng changed, which needs a review, so the build stops.
remove_releng_paths() {
    local profile=$1 path
    while IFS= read -r path; do
        [[ $path != /* && $path != *..* ]] || die "releng-remove.txt: invalid path '$path'"
        [[ -e $profile/$path || -L $profile/$path ]] \
            || die "releng-remove.txt lists '$path', which releng no longer has; review releng"
        rm -f -- "$profile/$path"
        log "Removed releng path $path"
    done < <(list_entries "$overlay_dir/releng-remove.txt")
}

# Appends the Star OS packages that releng does not already list.
append_packages() {
    local list=$1 pkg added=0
    while IFS= read -r pkg; do
        if grep -qxF -- "$pkg" "$list"; then
            log "Package $pkg is already in releng's list"
        else
            printf '%s\n' "$pkg" >>"$list"
            added=$((added + 1))
        fi
    done < <(list_entries "$overlay_dir/packages.x86_64.append")
    log "Appended $added packages to the profile's package list"
}

# Copies the Star OS shell (QML module and Plasma packages) into the image.
# These are new paths that no package owns; licence sidecars stay in git.
install_shell_files() {
    local airootfs=$1
    mkdir -p -- "$airootfs/usr/lib/qt6/qml" "$airootfs/usr/share/plasma/shells" \
        "$airootfs/usr/share/plasma/plasmoids"
    cp -a -- "$shell_src/qml/StarOS" "$airootfs/usr/lib/qt6/qml/"
    cp -a -- "$shell_src/plasma/shells/." "$airootfs/usr/share/plasma/shells/"
    cp -a -- "$shell_src/plasma/plasmoids/." "$airootfs/usr/share/plasma/plasmoids/"
    find "$airootfs/usr/lib/qt6/qml/StarOS" "$airootfs/usr/share/plasma" \
        -name '*.license' -type f -delete
    log "Installed Star OS shell files ($(find "$airootfs/usr/lib/qt6/qml/StarOS/Shell" \
        "$airootfs/usr/share/plasma" -type f | wc -l) files)"
}

# A hash over the installed shell tree (paths and contents), for build records.
shell_tree_hash() {
    local airootfs=$1
    (cd -- "$airootfs" && find usr/lib/qt6/qml/StarOS/Shell usr/share/plasma/shells/org.staros.shell \
        usr/share/plasma/plasmoids/org.staros.taskbar usr/share/plasma/plasmoids/org.staros.desktop \
        -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1
}

assemble_profile() {
    local profile=$1
    rm -rf -- "$profile"
    mkdir -p -- "$(dirname -- "$profile")"
    cp -a -- "$releng_dir" "$profile"
    remove_releng_paths "$profile"
    cp -a -- "$overlay_dir/airootfs/." "$profile/airootfs/"
    append_packages "$profile/packages.x86_64"
    install_shell_files "$profile/airootfs"
    cat -- "$overlay_dir/profiledef.append.sh" >>"$profile/profiledef.sh"
    pin_repositories "$profile/pacman.conf"
    add_local_repository "$profile/pacman.conf"
    skip_static_flatpak_remote "$profile/pacman.conf"
    add_storage_boot_entries "$profile"
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
    cp -- "$build_dir/boot-entries.txt" "$out_dir/boot-entries.txt"
    {
        printf 'iso=%s\n' "$iso"
        printf 'iso_bytes=%s\n' "$(stat -c %s -- "${isos[0]}")"
        printf 'git_commit=%s\n' "$commit"
        printf 'arch_snapshot_date=%s\n' "$baseline"
        printf 'archiso=%s\n' "$(pacman -Q archiso)"
        printf 'bootmodes=%s\n' "$(profile_bootmodes "$build_dir/profile")"
        printf 'source_date_epoch=%s\n' "$SOURCE_DATE_EPOCH"
        printf 'built_at=%s\n' "$(date -u +%FT%TZ)"
        printf 'build_host_kernel=%s\n' "$(uname -r)"
        printf 'iso_package_count=%s\n' "$(wc -l <"$out_dir/packages.x86_64.txt")"
        printf 'staros_shell_sha256=%s\n' "$(shell_tree_hash "$work/x86_64/airootfs")"
        printf 'staros_packages=%s\n' "$(grep '^staros-' "$out_dir/packages.x86_64.txt" | tr ' \n' '= ' \
            | sed 's/ $//')"
        printf 'kernel_params=%s\n' "$kernel_params"
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

    check_boot_parameters "$work"
    check_storage_entries "$work"
    log "Disk space after mkarchiso:"
    df -h -- "$build_dir" "$out_dir" | sed 's/^/    /'
    log "Checking the image policy"
    "$staros_repo_root/scripts/ci/check-image-policy.sh" "$work/x86_64/airootfs" \
        "$build_dir/image-policy.txt"

    write_records "$work" "$baseline"
    cp -- "$build_dir/image-policy.txt" "$out_dir/image-policy.txt"
    log "Build records:"
    cat -- "$out_dir/build-info.txt"
    log "Boot menu entries:"
    sed 's/^/    /' -- "$out_dir/boot-entries.txt"
    cat -- "$out_dir/SHA256SUMS"
}

main "$@"
