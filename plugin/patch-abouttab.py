#!/usr/bin/env python3
"""Chain the Shidonia plugin re-apply onto the stock Settings Update command.

The stock AboutTab.qml Update button runs the upstream installer, which
wipes plugin-overlaid shell files. This patch appends
`bash <apply.sh> --post-update` INSIDE the held terminal command (so sudo
can still prompt), making every Settings-driven update self-healing:
installer runs first, plugin re-applies right after.

Idempotent: a marker comment guards against double-patching. After an
upstream update overwrites AboutTab.qml the marker is gone, so apply.sh
simply patches it again.

Usage:
    patch-abouttab.py <AboutTab.qml> <apply.sh path>
"""

import os
import sys

MARKER = "shidonia-plugin-post-update"


def main():
    qml_path, apply_path = sys.argv[1:3]
    with open(qml_path) as f:
        text = f.read()

    if MARKER in text:
        print("abouttab: update chain already present, skipping")
        return 0

    home = os.path.expanduser("~")
    if apply_path == os.path.join(home, ".local/share/shidonia-plugin/plugin/apply.sh"):
        chain_target = "$HOME/.local/share/shidonia-plugin/plugin/apply.sh"
    else:
        chain_target = apply_path
    # NOTE: chain_target must stay unquoted here. This replacement lands
    # inside the single-quoted `bash -c '...'` body of the Update command,
    # so any double quote we emit is literal to the outer shell and would
    # unbalance it (that broke the Update button once already).
    old = 'install.sh)\\"\''
    new = 'install.sh)\\"; bash ' + chain_target + ' --post-update\''
    count = text.count(old)
    if count != 2:
        print(
            f"abouttab: ERROR: expected 2 update-command spots, found {count}. "
            "Upstream changed AboutTab.qml beyond recognition; refusing to patch.",
            file=sys.stderr,
        )
        return 1

    text = text.replace(old, new)

    # tag the `let cmd` line so future runs (and users) can see the hook
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if "let cmd = " in line and "kitty" in line:
            lines[i] = line.rstrip() + f" // {MARKER}"
    text = "\n".join(lines)

    with open(qml_path, "w") as f:
        f.write(text)
    print("abouttab: update command now re-applies Shidonia customizations post-update")


if __name__ == "__main__":
    sys.exit(main())
