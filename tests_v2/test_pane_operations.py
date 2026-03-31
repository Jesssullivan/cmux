#!/usr/bin/env python3
"""Socket API: pane.list, pane.focus, pane.surfaces, pane.last."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        # Create fresh workspace with splits
        ws_id = c.new_workspace()
        c.select_workspace(ws_id)
        time.sleep(0.1)

        s2 = c.new_split("right")
        time.sleep(0.1)
        s3 = c.new_split("right")
        time.sleep(0.1)

        # pane.list: should show 3 panes (1:1 panel mapping)
        panes = c.list_panes()
        if len(panes) < 3:
            raise cmuxError(f"Expected >= 3 panes after 2 splits, got {len(panes)}")

        # Verify pane structure: each has index, id, surface_count, focused
        for idx, pane_id, count, focused in panes:
            if not pane_id:
                raise cmuxError(f"Pane at index {idx} has no id")

        # pane.focus: focus the first pane
        first_pane_id = panes[0][1]
        c.focus_pane(first_pane_id)
        time.sleep(0.05)

        # Verify focus changed
        panes_after = c.list_panes()
        focused_panes = [(idx, pid) for idx, pid, _cnt, focused in panes_after if focused]
        if not focused_panes:
            raise cmuxError("No pane focused after focus_pane")
        if focused_panes[0][1] != first_pane_id:
            raise cmuxError(f"Expected pane {first_pane_id} focused, got {focused_panes[0][1]}")

        # pane.surfaces: check surfaces in the focused pane
        surfaces = c.list_pane_surfaces(first_pane_id)
        if len(surfaces) < 1:
            raise cmuxError(f"Expected >= 1 surface in pane, got {len(surfaces)}")

        # pane.last: should return a pane ID
        last = c._call("pane.last") or {}
        last_id = last.get("pane_id")
        if not last_id:
            raise cmuxError(f"pane.last returned no pane_id: {last}")

        # Cleanup
        c.close_workspace(ws_id)

    print("PASS: pane operations (list, focus, surfaces, last)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
