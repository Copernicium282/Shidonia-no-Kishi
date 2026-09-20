#!/usr/bin/env bash
# Weekly upstream sync for Shidonia-no-Kishi.
#
# Merges the latest commits from ilyamiro/serpantinum into master while
# preserving this fork's stable overrides:
#   - any path matching KEEP_OURS_PATTERNS that conflicts is resolved
#     to "ours" (the fork's version wins),
#   - any other conflicting path is ALSO resolved to "ours" so the fork
#     never breaks on a pull; upstream's non-conflicting changes still
#     land via the regular three-way merge.
#
# Push is skipped when DRY_RUN is set (for local testing).

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/ilyamiro/serpantinum.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
DRY_RUN="${DRY_RUN:-}"

# Paths this fork intentionally overrides. Informational: every conflict is
# resolved to ours regardless; this list documents what to re-review after a sync.
KEEP_OURS_PATTERNS=(
  'README.md'
  'config/serpantinum/settings.json'
  'config/sddm/themes/material-you*'
  'docs/assets*'
  'install/install.sh'
  'install/modules/*'
  'src/assets/languages/*'
  'src/assets/themes/Tsugumori.json'
  'src/quickshell/bar/*'
  'src/quickshell/guide/AboutTab.qml'
  'src/scripts/updater.py'
)

matches() {
    local path="$1" pattern
    for pattern in "$@"; do
        case "$path" in
            $pattern) return 0 ;;
        esac
    done
    return 1
}

has_upstream_changes() {
    local ancestor
    ancestor=$(git merge-base HEAD "upstream/$UPSTREAM_BRANCH" 2>/dev/null || true)
    [ -n "$ancestor" ] && [ "$ancestor" != "$(git rev-parse "upstream/$UPSTREAM_BRANCH")" ]
}

resolve_conflicts() {
    local conflicted
    conflicted=$(git diff --name-only --diff-filter=U)
    if [ -z "$conflicted" ]; then
        echo "merge failed but no conflicting paths are left to resolve"
        exit 1
    fi

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if git checkout --ours -- "$f" 2>/dev/null; then
            :
        else
            git rm -f -- "$f" 2>/dev/null || true
        fi
        git add -- "$f" 2>/dev/null || git add -A -- "$f" 2>/dev/null || true
        if matches "$f" "${KEEP_OURS_PATTERNS[@]}"; then
            echo "resolved keep-ours: $f"
        else
            echo "resolved keep-ours (unexpected conflict): $f"
        fi
    done <<< "$conflicted"

    git commit --no-edit --no-verify
}

ensure_identity() {
    git config user.name >/dev/null 2>&1 || git config user.name "github-actions[bot]"
    git config user.email >/dev/null 2>&1 || git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
}

main() {
    ensure_identity
    git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
    git fetch upstream "$UPSTREAM_BRANCH"

    if ! has_upstream_changes; then
        echo "no new upstream commits for $UPSTREAM_BRANCH, nothing to do"
        exit 0
    fi

    local merge_base
    merge_base=$(git merge-base HEAD "upstream/$UPSTREAM_BRANCH")

    if git merge --no-edit --no-ff "upstream/$UPSTREAM_BRANCH"; then
        echo "clean three-way merge from $merge_base"
    else
        echo "conflicts detected, applying fork keep-ours policy..."
        resolve_conflicts
    fi

    if [ -n "$DRY_RUN" ]; then
        echo "DRY_RUN set, not pushing"
        exit 0
    fi

    git push origin HEAD:"$UPSTREAM_BRANCH"
    echo "pushed merged upstream changes to origin/$UPSTREAM_BRANCH"
}

main "$@"