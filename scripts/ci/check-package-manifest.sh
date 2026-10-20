#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compares the package list of a built ISO with the recorded baseline manifest
# (test T0-05). Usage: check-package-manifest.sh <packages.x86_64.txt>
#
# When the baseline date changes, regenerate the recorded manifest from a CI
# build and commit it in the same change, so the package difference is reviewed.

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

(($# == 1)) || die "usage: $0 <packages.x86_64.txt>"
actual=$1
expected="$staros_repo_root/distro/baseline/packages.x86_64.txt"
[[ -s $actual ]] || die "$actual is missing or empty"

if [[ ! -f $expected ]]; then
    log "Package list of this build:"
    cat -- "$actual"
    die "no recorded manifest at distro/baseline/packages.x86_64.txt;" \
        "review the list above and commit it to record the baseline"
fi

if ! diff -u -- "$expected" "$actual"; then
    log "Full package list of this build (between the markers):"
    echo "----- BEGIN packages.x86_64.txt -----"
    cat -- "$actual"
    echo "----- END packages.x86_64.txt -----"
    die "the ISO's packages differ from the recorded baseline (distro/baseline/packages.x86_64.txt)" \
        "at baseline date $(staros_baseline_date). If the change is intended (for example a" \
        "reviewed change to packages.x86_64.append), commit the list above in the same change."
fi
log "Package list matches the recorded baseline ($(wc -l <"$actual") packages)"
