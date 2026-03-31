#!/usr/bin/env python3
"""Socket API: workspace.next, workspace.previous, workspace.last navigation."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _selected_index(c: cmux) -> int:
    for idx, _wid, _title, selected in c.list_workspaces():
        if selected:
            return idx
    raise cmuxError("No workspace selected")


def main() -> int:
    created: list[str] = []
    with cmux(SOCKET_PATH) as c:
        # Create 4 more workspaces (total 5 with initial)
        for _ in range(4):
            created.append(c.new_workspace())
            time.sleep(0.05)

        ws_list = c.list_workspaces()
        total = len(ws_list)
        if total < 5:
            raise cmuxError(f"Expected >= 5 workspaces, got {total}")

        # Select workspace 0
        c.select_workspace(ws_list[0][1])
        time.sleep(0.05)
        if _selected_index(c) != 0:
            raise cmuxError("Failed to select workspace 0")

        # next should go to 1
        c.next_workspace()
        time.sleep(0.05)
        idx = _selected_index(c)
        if idx != 1:
            raise cmuxError(f"next from 0: expected index 1, got {idx}")

        # next again should go to 2
        c.next_workspace()
        time.sleep(0.05)
        idx = _selected_index(c)
        if idx != 2:
            raise cmuxError(f"next from 1: expected index 2, got {idx}")

        # previous should go back to 1
        c.previous_workspace()
        time.sleep(0.05)
        idx = _selected_index(c)
        if idx != 1:
            raise cmuxError(f"previous from 2: expected index 1, got {idx}")

        # Select first, previous should wrap to last
        c.select_workspace(ws_list[0][1])
        time.sleep(0.05)
        c.previous_workspace()
        time.sleep(0.05)
        idx = _selected_index(c)
        if idx != total - 1:
            raise cmuxError(f"previous from 0: expected wrap to {total - 1}, got {idx}")

        # next from last should wrap to 0
        c.next_workspace()
        time.sleep(0.05)
        idx = _selected_index(c)
        if idx != 0:
            raise cmuxError(f"next from last: expected wrap to 0, got {idx}")

        # Cleanup
        for ws_id in reversed(created):
            c.close_workspace(ws_id)

    print("PASS: workspace navigation (next, previous, wrap)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
