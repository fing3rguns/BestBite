#!/usr/bin/env python3
"""Runs the BestBite harness against a fake Forever client.

    python Tests/run.py

Needs lupa:  pip install lupa

The harness is plain Lua that stubs just enough of the client to load the addon,
stock its buttons and drive its commands. It is deliberately not in the .toc, so
the game never loads it.
"""

import os
import sys


def main():
    try:
        from lupa import LuaRuntime
    except ImportError:
        print("lupa is not installed. Try:  pip install lupa", file=sys.stderr)
        return 2

    here = os.path.dirname(os.path.abspath(__file__))
    addon = os.path.dirname(here)
    harness = os.path.join(here, "harness.lua")

    if not os.path.exists(harness):
        print("harness.lua is missing beside this script", file=sys.stderr)
        return 2

    lua = LuaRuntime(unpack_returned_tuples=True)
    # The harness loads the addon's files relative to this folder.
    lua.execute("BESTBITE_DIR = [[" + addon.replace("\\", "/") + "]]")

    with open(harness, encoding="utf-8") as handle:
        source = handle.read()

    try:
        lua.execute(source)
    except Exception as exc:  # a failed check ends in a raised error
        message = str(exc)
        if "checks failed" not in message:
            print("Lua error:", message, file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
