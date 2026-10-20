#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fails if a name from scripts/ci/forbidden-env.txt appears anywhere in the
# repository outside docs/ and the list itself. Documentation may name the
# variables in order to explain why they are banned.
#
# Usage: scripts/ci/check-forbidden-env.sh

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

list=scripts/ci/forbidden-env.txt
cd -- "$staros_repo_root"

mapfile -t names < <(grep -vE '^[[:space:]]*(#|$)' "$list")
((${#names[@]} > 0)) || die "$list lists no names"

args=()
for name in "${names[@]}"; do
    args+=(-e "$name")
done

if git grep --untracked -n -w -F "${args[@]}" -- . ':!docs/' ":!$list"; then
    die "forbidden environment variable names found (see $list)"
fi
log "No forbidden environment variable names outside docs/ (${#names[@]} names checked)"
