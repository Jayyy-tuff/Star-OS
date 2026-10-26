#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds and tests the Star OS packages (distro/packages/*/PKGBUILD, ADR-0009)
# and makes a pacman repository of them for scripts/build-iso.sh
# (STAROS_LOCAL_REPO).
#
# Usage: scripts/build-packages.sh OUTDIR
#
# Runs in a disposable Arch container that scripts/ci/prepare-arch-build-host.sh
# has pinned to the baseline snapshot, with base-devel installed. As root it
# installs each PKGBUILD's dependencies with pacman; the build and the tests
# (makepkg runs check()) run as the unprivileged user 'builder'. Every package
# is built from a tarball of this checkout (star-os-src.tar.gz).
#
# Writes OUTDIR/*.pkg.tar.zst, the repository OUTDIR/staros.db.tar.gz (with
# the staros.db link pacman reads) and OUTDIR/packages.txt (one line per
# package: file name and sha256). Scratch space is build/packages/.

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

packages_dir="$staros_repo_root/distro/packages"
work_dir="$staros_repo_root/build/packages"
builder=builder

check_host() {
    [[ -f /etc/arch-release ]] || die "must run in an Arch Linux container"
    ((EUID == 0)) || die "must run as root (it installs build dependencies)"
    [[ ${STAROS_DISPOSABLE_HOST:-} == 1 ]] \
        || die "refusing to add a user and packages to this host;" \
               "set STAROS_DISPOSABLE_HOST=1 only in a throwaway container"
    local tool
    for tool in makepkg repo-add runuser tar sha256sum; do
        command -v "$tool" >/dev/null || die "$tool not found; install base-devel"
    done
}

ensure_builder() {
    if ! id -u "$builder" >/dev/null 2>&1; then
        useradd --system --create-home --shell /usr/bin/nologin "$builder"
        log "Created the build user $builder"
    fi
}

as_builder() {
    runuser -u "$builder" -- "$@"
}

# The checked-out tree without version control and build output, as
# star-os-src/ (the CI container's checkout may have no .git directory).
make_source_tarball() {
    local tarball=$1
    tar --create --gzip --file "$tarball" --sort=name --owner=0 --group=0 --numeric-owner \
        --exclude=./.git --exclude=./build --exclude=./out \
        --transform 's,^\.,star-os-src,' -C "$staros_repo_root" .
    log "Source tarball: $(du -h -- "$tarball" | cut -f1)"
}

# Installs the depends, makedepends and checkdepends of the PKGBUILD in DIR:
# Star OS packages (staros-*) from OUT, built earlier in this run, and the
# others from the pinned Arch repositories.
install_dependencies() {
    local dir=$1 out=$2 dep
    local -a deps repo_deps=() local_files=() found
    mapfile -t deps < <(as_builder env -C "$dir" makepkg --printsrcinfo \
        | awk -F ' = ' '$1 ~ /^\t(depends|makedepends|checkdepends)$/ { print $2 }' | sort -u)
    ((${#deps[@]} > 0)) || die "no dependencies found in $dir/PKGBUILD"
    for dep in "${deps[@]}"; do
        if [[ $dep == staros-* ]]; then
            found=("$out/$dep"-[0-9]*.pkg.tar.zst)
            [[ -f ${found[0]} ]] || die "$dep is needed but was not built before; check the build order"
            local_files+=("${found[0]}")
        else
            repo_deps+=("$dep")
        fi
    done
    if ((${#repo_deps[@]} > 0)); then
        log "Installing ${#repo_deps[@]} dependencies: ${repo_deps[*]}"
        staros_pacman -S --noconfirm --needed --asdeps -- "${repo_deps[@]}"
    fi
    if ((${#local_files[@]} > 0)); then
        log "Installing Star OS packages built earlier: ${local_files[*]##*/}"
        pacman -U --noconfirm --asdeps -- "${local_files[@]}"
    fi
}

# After a failed makepkg: the checksums of the downloaded sources, so that a
# reviewed change can pin them, and the content of Flatpak remote files.
show_sources() {
    local dir=$1 file
    log "Downloaded sources in $(basename -- "$dir"):"
    for file in "$dir"/*; do
        [[ -f $file && ! -L $file && $file != */PKGBUILD && $file != *.pkg.tar.* \
            && $file != */star-os-src.tar.gz ]] || continue
        printf '    sha256 %s  %s\n' "$(sha256sum -- "$file" | cut -d' ' -f1)" "$(basename -- "$file")"
        if [[ $file == *.flatpakrepo ]]; then
            sed 's/^/        /' -- "$file"
        fi
    done
}

build_package() {
    local name=$1 tarball=$2 out=$3 dir="$work_dir/$1"
    rm -rf -- "$dir"
    install -d -o "$builder" -- "$dir"
    install -m 644 -o "$builder" -- "$packages_dir/$name/PKGBUILD" "$dir/PKGBUILD"
    install -m 644 -o "$builder" -- "$tarball" "$dir/star-os-src.tar.gz"
    install_dependencies "$dir" "$out"
    log "Building and testing $name"
    if ! as_builder env -C "$dir" makepkg --nodeps --cleanbuild --check --noconfirm; then
        show_sources "$dir"
        die "makepkg failed for $name"
    fi
    local -a built=("$dir"/*.pkg.tar.zst)
    [[ ${#built[@]} -ge 1 && -f ${built[0]} ]] || die "makepkg wrote no package for $name"
    cp -- "${built[@]}" "$out/"
}

main() {
    [[ $# -eq 1 ]] || die "usage: $0 OUTDIR"
    check_host
    local out=$1 tarball pkgbuild file
    local -a names=()
    # staros-system first: the other packages use its QML module.
    [[ -f $packages_dir/staros-system/PKGBUILD ]] && names+=(staros-system)
    for pkgbuild in "$packages_dir"/*/PKGBUILD; do
        file=$(basename -- "$(dirname -- "$pkgbuild")")
        [[ -f $pkgbuild && $file != staros-system ]] && names+=("$file")
    done
    ((${#names[@]} > 0)) || die "no PKGBUILD found under $packages_dir"

    ensure_builder
    rm -rf -- "$work_dir"
    mkdir -p -- "$work_dir" "$out"
    out=$(cd -- "$out" && pwd)
    rm -f -- "$out"/*.pkg.tar.zst "$out"/staros.*
    tarball="$work_dir/star-os-src.tar.gz"
    make_source_tarball "$tarball"

    for file in "${names[@]}"; do
        build_package "$file" "$tarball" "$out"
    done

    repo-add "$out/staros.db.tar.gz" "$out"/*.pkg.tar.zst
    # pacman reads staros.db; plain copies survive artifact upload and download.
    for file in "$out/staros.db" "$out/staros.files"; do
        if [[ -L $file ]]; then
            cp --remove-destination -- "$(readlink -f -- "$file")" "$file"
        fi
    done
    (cd -- "$out" && sha256sum -- *.pkg.tar.zst) >"$out/packages.txt"
    log "Packages:"
    sed 's/^/    /' -- "$out/packages.txt"
    for file in "$out"/*.pkg.tar.zst; do
        log "Contents of $(basename -- "$file"):"
        pacman -Qlp -- "$file" | sed 's/^/    /'
    done
}

main "$@"
