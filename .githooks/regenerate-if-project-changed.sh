#!/bin/sh
# Shared by post-merge and post-checkout: regenerates NostalgiaVision.xcodeproj whenever
# project.yml changed, or a file was added or removed under one of its source roots (Sources,
# Tests, UITemp), between $1 and $2. Xcode reads the checked-in-by-xcodegen .xcodeproj, not
# project.yml or the filesystem directly — xcodegen bakes an explicit file list into it, so a bare
# git pull/checkout/merge that adds or removes a source file (project.yml itself untouched)
# silently leaves Xcode unable to see the new file, exactly like a project.yml change leaving it on
# a stale package reference. A plain edit to an existing file's contents needs no regeneration —
# only the set of paths does — so this checks `git diff --name-status`, not `--name-only`.
before="$1"
after="$2"

needs_regen="$(git diff --name-status "$before" "$after" 2>/dev/null | awk '
    $NF == "project.yml" { found = 1 }
    $1 ~ /^[AD]/ && $2 ~ /^(Sources|Tests|UITemp)\// { found = 1 }
    END { print found + 0 }
')"

[ "$needs_regen" = "1" ] || exit 0

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "warning: project sources changed but xcodegen isn't on PATH (brew install xcodegen) — regenerate NostalgiaVision.xcodeproj manually before building." >&2
    exit 0
fi

echo "project sources changed — regenerating NostalgiaVision.xcodeproj"
(cd "$(git rev-parse --show-toplevel)" && xcodegen generate)
