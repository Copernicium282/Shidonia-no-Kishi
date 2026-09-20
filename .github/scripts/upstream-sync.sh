#!/usr/bin/env bash
# Upstream sync for Shidonia-no-Kishi, gated on version bumps.
#
# Runs on a schedule (matching the shell updater's hourly check cadence) and
# merges new commits from ilyamiro/serpantinum into master whenever the fork's
# version.txt is behind upstream's — i.e. on every upstream version change.
#
# The fork's stable overrides are preserved:
#   - any path that conflicts is resolved to "ours" (the fork's version wins),
#     so the clean, upstream-facing files still receive upstream updates while
#     the customized ones stay intact,
#   - version.txt itself follows upstream (it's the "new release" signal that
#     the installed shell uses to notify about an update).
#
# No merge happens without a version bump unless FORCE is set, or when
# upstream has no new commits at all. Push is skipped when DRY_RUN is set.

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/ilyamiro/serpantinum.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
FORCE="${FORCE:-}"
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

# 0 if v1 < v2, 1 otherwise (dot-separated numeric parts).
version_gt() {
    local v1="$1" v2="$2"
    local -a a b
    IFS=. read -ra a <<< "$v1"
    IFS=. read -ra b <<< "$v2"
    local i x y
    for i in "${!a[@]}"; do
        x="${a[$i]:-0}"
        y="${b[$i]:-0}"
        if [ "$y" -gt "$x" ]; then return 0; fi
        if [ "$x" -gt "$y" ]; then return 1; fi
    done
    return 1
}

version_gate_allows_merge() {
    local head_ver up_ver
    head_ver=$(git show "HEAD:version.txt" 2>/dev/null | tr -d '[:space:]')
    up_ver=$(git show "upstream/$UPSTREAM_BRANCH:version.txt" 2>/dev/null | tr -d '[:space:]')
    head_ver="${head_ver:-0.0.0}"
    up_ver="${up_ver:-0.0.0}"
    if version_gt "$head_ver" "$up_ver"; then
        echo "upstream version $up_ver > fork version $head_ver, merging"
        return 0
    fi
    echo "fork version $head_ver is not behind upstream $up_ver, skipping (use FORCE to override)"
    return 1
}

ensure_identity() {
    git config user.name >/dev/null 2>&1 || git config user.name "github-actions[bot]"
    git config user.email >/dev/null 2>&1 || git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
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

main() {
    ensure_identity
    git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
    git fetch upstream "$UPSTREAM_BRANCH"

    if ! has_upstream_changes; then
        echo "no new upstream commits for $UPSTREAM_BRANCH, nothing to do"
        exit 0
    fi

    if [ -z "$FORCE" ] && ! version_gate_allows_merge; then
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