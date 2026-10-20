#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Validates a Wayland session entry with desktop-file-validate. Session entries
# use 'DesktopNames', which display managers read (Plasma's own session files
# use it) but which the Desktop Entry specification does not define, so that
# one finding is allowed. Any other error or warning fails.
#
# Usage: scripts/ci/validate-session-entry.sh FILE

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

(($# == 1)) || die "usage: $0 FILE"
command -v desktop-file-validate >/dev/null || die "desktop-file-validate not found"
allowed='key "DesktopNames" in group "Desktop Entry", but keys extending the format should start with "X-"'

findings=$(desktop-file-validate "$1" 2>&1 || true)
remaining=$(grep -vF -- "$allowed" <<<"$findings" || true)
if [[ -n $remaining ]]; then
    printf '%s\n' "$remaining"
    die "$1 is not a valid session entry"
fi
grep -q '^DesktopNames=' "$1" || die "$1 has no DesktopNames key"
log "$1 is a valid session entry (DesktopNames allowed)"
