#!/bin/sh
# Shared by post-merge and post-checkout: regenerates NostalgiaVision.xcodeproj whenever
# project.yml differs between $1 and $2. Xcode reads the checked-in-by-xcodegen .xcodeproj, not
# project.yml directly, so a bare git pull/checkout that changes project.yml silently leaves Xcode
# building against a stale package reference or target until someone remembers to regenerate.
before="$1"
after="$2"

if ! git diff --name-only "$before" "$after" 2>/dev/null | grep -q '^project\.yml$'; then
    exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "warning: project.yml changed but xcodegen isn't on PATH (brew install xcodegen) — regenerate NostalgiaVision.xcodeproj manually before building." >&2
    exit 0
fi

echo "project.yml changed — regenerating NostalgiaVision.xcodeproj"
(cd "$(git rev-parse --show-toplevel)" && xcodegen generate)
