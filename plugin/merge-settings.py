#!/usr/bin/env python3
"""Merge Shidonia plugin managed settings into the user's settings.json.

Snapshot semantics ("stays intact"):
  - First install (no snapshot yet): every managed key is set to the overlay
    default, whatever the user currently has.
  - Later runs (e.g. after an upstream update wiped nothing, since the user
    config survives updates, or after the user edited values): a managed key
    is only (re-)set when it is missing or still equals the value this plugin
    set last time. If the user changed it since, the user's value wins.

Usage:
    merge-settings.py <user_settings.json> <overlay.json> <state.json>
"""

import json
import sys


def flatten(obj, prefix=""):
    leaves = {}
    for key, val in obj.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(val, dict):
            leaves.update(flatten(val, path))
        else:
            leaves[path] = val
    return leaves


def get_path(obj, path):
    cur = obj
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None, False
        cur = cur[part]
    return cur, True


def set_path(obj, path, value):
    cur = obj
    parts = path.split(".")
    for part in parts[:-1]:
        if not isinstance(cur.get(part), dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = value


def main():
    user_path, overlay_path, state_path = sys.argv[1:4]

    try:
        with open(user_path) as f:
            user = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        user = {}
    if not isinstance(user, dict):
        user = {}

    # Upstream 2.3.0 renamed bar.thickness to bar.height. Carry an existing
    # user value across before overlay defaults are considered, so a
    # customized thickness is not replaced by the plugin default.
    bar = user.get("bar")
    if isinstance(bar, dict) and "height" not in bar:
        legacy = bar.get("thickness")
        if isinstance(legacy, (int, float)) and not isinstance(legacy, bool):
            bar["height"] = legacy

    with open(overlay_path) as f:
        overlay = json.load(f)
    leaves = flatten(overlay)

    try:
        with open(state_path) as f:
            state = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    snapshot = state.get("settings_snapshot", {})
    first_install = not snapshot

    changed = []
    new_snapshot = dict(snapshot)
    for path, default in leaves.items():
        current, found = get_path(user, path)
        snap_val, snap_found = get_path(snapshot, path)
        if not found or first_install or (snap_found and current == snap_val):
            if not found or current != default:
                set_path(user, path, default)
                changed.append(path)
            # record what the PLUGIN set, not what the user may hold now
            set_path(new_snapshot, path, default)
        # else: user customized this key since we last touched it - keep
        # theirs, and keep our old snapshot so we keep recognizing it as theirs
    state["settings_snapshot"] = new_snapshot

    with open(user_path, "w") as f:
        json.dump(user, f, indent=2, ensure_ascii=False)
        f.write("\n")

    with open(state_path, "w") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"settings: {len(changed)} key(s) set ({', '.join(changed) if changed else 'all already intact'})")


if __name__ == "__main__":
    main()
