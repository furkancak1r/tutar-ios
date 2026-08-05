#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_root="$repo_root/app/Tutar"
failed=0

report() {
    title=$1
    matches=$2
    if [ -n "$matches" ]; then
        printf 'error: %s\n%s\n' "$title" "$matches"
        failed=1
    fi
}

direct_swipes=$(grep -R -n --include='*.swift' '\.swipeActions' "$app_root" | grep -v '/AppConstants.swift:' || true)
unsafe_accent_fills=$(grep -R -n -E --include='*.swift' '\.(tint|background|fill)\((\.accentColor|Color\.accentColor)\)' "$app_root" | grep -v '/TutarApp.swift:' || true)
fixed_control_fills=$(grep -R -n -E --include='*.swift' '\.(tint|background|fill)\((\.white|\.black|Color\.white|Color\.black)\)' "$app_root" || true)
prominent_buttons=$(grep -R -n --include='*.swift' '\.buttonStyle(\.borderedProminent)' "$app_root" || true)

report 'Use tutarDeleteSwipeAction so destructive colour and contrast stay centralized.' "$direct_swipes"
report 'AccentColor is foreground-only; do not use it as an interactive fill.' "$unsafe_accent_fills"
report 'Fixed black/white interactive fills are forbidden; use semantic colours.' "$fixed_control_fills"
report 'borderedProminent inherits unsafe accent fills; use bordered or an audited custom style.' "$prominent_buttons"

exit "$failed"
