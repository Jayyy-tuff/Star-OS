#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Turns a throwaway Arch Linux container into a Star OS build host: points
# pacman at the baseline snapshot (ADR-0002), syncs every installed package to
# it (including downgrades), and installs the pinned archiso plus any packages
# given as arguments.
#
# This rewrites the host's mirrorlist and pacman.conf, so it refuses to run
# unless STAROS_DISPOSABLE_HOST=1 confirms the host is disposable.

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

[[ -f /etc/arch-release ]] || die "must run in an Arch Linux container"
((EUID == 0)) || die "must run as root"
[[ ${STAROS_DISPOSABLE_HOST:-} == 1 ]] \
    || die "refusing to modify this host; set STAROS_DISPOSABLE_HOST=1 only in a throwaway container"

server=$(staros_archive_server "$(staros_baseline_date)")
log "Pinning pacman to $server"
printf 'Server = %s\n' "$server" >/etc/pacman.d/mirrorlist

# The archlinux container image skips some files (for example locales) via
# NoExtract. Build tools such as grub-mkstandalone need them.
sed -i -E '/^[[:space:]]*NoExtract[[:space:]]*=/d' /etc/pacman.conf

pacman-key --init
pacman-key --populate archlinux
staros_pacman -Syyuu --noconfirm --needed archiso grub "$@"
pacman -Q archiso grub "$@"
