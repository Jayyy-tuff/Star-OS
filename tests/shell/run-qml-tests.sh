#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the Star OS shell checks that need Qt but no session (M0.2, T0-20):
#   1. qmllint on the StarOS.Shell module (warnings are fatal);
#   2. kpackagetool6 installs the three Plasma packages into a scratch HOME;
#   3. qmltestrunner on tests/shell at scale factors 1, 1.5 and 2 on an
#      offscreen 1920x1080 screen with the software scene graph, writing JUnit
#      XML per scale and checking that each run saw the scale it asked for.
#
# Usage: tests/shell/run-qml-tests.sh [OUTDIR]   (default: build/qml-tests)
# Needs qt6-declarative (qmllint, qmltestrunner), kpackage and a font.

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/lib/common.sh"

repo=$staros_repo_root
out=$(realpath -m -- "${1:-$repo/build/qml-tests}")
scales=(1 1.5 2)
qml_dir="$repo/shell/qml"
module_dir="$qml_dir/StarOS/Shell"

find_tool() {
    local name
    for name in "$@"; do
        if command -v "$name" >/dev/null; then
            command -v "$name"
            return
        fi
        if [[ -x /usr/lib/qt6/bin/$name ]]; then
            printf '%s\n' "/usr/lib/qt6/bin/$name"
            return
        fi
    done
    die "none of $* found; install qt6-declarative"
}

rm -rf -- "$out"
mkdir -p -- "$out"
qmllint=$(find_tool qmllint6 qmllint)
qmltestrunner=$(find_tool qmltestrunner6 qmltestrunner)
command -v kpackagetool6 >/dev/null || die "kpackagetool6 not found; install kpackage"

log "qmllint $(basename -- "$qmllint") on StarOS.Shell"
mapfile -t module_files < <(find "$module_dir" -name '*.qml' | sort)
"$qmllint" -I "$qml_dir" "${module_files[@]}"
log "qmllint: ${#module_files[@]} files clean"

log "kpackagetool6: installing the Plasma packages into a scratch HOME"
scratch_home=$(mktemp -d)
trap 'rm -rf -- "$scratch_home"' EXIT
HOME=$scratch_home kpackagetool6 --type Plasma/Shell \
    --install "$repo/shell/plasma/shells/org.staros.shell"
for applet in org.staros.taskbar org.staros.desktop; do
    HOME=$scratch_home kpackagetool6 --type Plasma/Applet \
        --install "$repo/shell/plasma/plasmoids/$applet"
done
HOME=$scratch_home kpackagetool6 --type Plasma/Applet --list | grep -E 'org\.staros\.' || true

export QT_QPA_PLATFORM="offscreen:configfile=$repo/tests/shell/screen-1920x1080.json"
export QT_QUICK_BACKEND=software
unset QT_SCREEN_SCALE_FACTORS QT_ENABLE_HIGHDPI_SCALING QT_SCALE_FACTOR_ROUNDING_POLICY

failed=0
for scale in "${scales[@]}"; do
    log "qmltestrunner at QT_SCALE_FACTOR=$scale"
    status=0
    QT_SCALE_FACTOR=$scale "$qmltestrunner" -input "$repo/tests/shell" -import "$qml_dir" \
        -o "$out/junit-scale-$scale.xml,junitxml" -o "-,txt" 2>&1 \
        | tee "$out/qmltest-scale-$scale.log" || status=$?
    if ((status != 0)); then
        echo "qmltestrunner failed at scale $scale (status $status)"
        failed=1
    fi
    if ! grep -q "STAROS-TEST scaling screen=.* dpr=$scale " "$out/qmltest-scale-$scale.log"; then
        echo "the scaling test did not report dpr=$scale; the scale factor was not applied"
        failed=1
    fi
    grep -E '^Totals:' "$out/qmltest-scale-$scale.log" | sed "s/^/scale $scale: /" || true
done
((failed == 0)) || die "QML tests failed"
log "QML tests passed at scale factors ${scales[*]}"
