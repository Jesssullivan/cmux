#!/usr/bin/env python3
"""Socket API: workspace.reorder by index, before_workspace, after_workspace."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _ws_ids(c: cmux) -> list[str]:
    return [wid for _idx, wid, _title, _sel in c.list_workspaces()]


def main() -> int:
    created: list[str] = []
    with cmux(SOCKET_PATH) as c:
        # Create 3 workspaces (total 4 with initial)
        for _ in range(3):
            created.append(c.new_workspace())
            time.sleep(0.05)

        ids_before = _ws_ids(c)
        if len(ids_before) < 4:
            raise cmuxError(f"Expected >= 4 workspaces, got {len(ids_before)}")

        ws0, ws1, ws2, ws3 = ids_before[0], ids_before[1], ids_before[2], ids_before[3]

        # Reorder by index: move ws3 to index 0
        c.reorder_workspace(ws3, index=0)
        time.sleep(0.05)
        ids_after_idx = _ws_ids(c)
        if ids_after_idx[0] != ws3:
            raise cmuxError(f"reorder by index: expected ws3 first, got {ids_after_idx}")

        # Reorder by before_workspace: move ws1 before ws3 (which is now at index 0)
        c.reorder_workspace(ws1, before_workspace=ws3)
        time.sleep(0.05)
        ids_after_before = _ws_ids(c)
        idx_ws1 = ids_after_before.index(ws1)
        idx_ws3 = ids_after_before.index(ws3)
        if idx_ws1 >= idx_ws3:
            raise cmuxError(f"reorder before: ws1 should be before ws3, got {ids_after_before}")

        # Reorder by after_workspace: move ws0 after ws2
        c.reorder_workspace(ws0, after_workspace=ws2)
        time.sleep(0.05)
        ids_after_after = _ws_ids(c)
        idx_ws0 = ids_after_after.index(ws0)
        idx_ws2 = ids_after_after.index(ws2)
        if idx_ws0 != idx_ws2 + 1:
            raise cmuxError(f"reorder after: ws0 should be right after ws2, got {ids_after_after}")

        # Verify all IDs still present (no loss)
        if set(ids_after_after) != set(ids_before):
            raise cmuxError(f"Workspace IDs changed after reorder: {ids_before} -> {ids_after_after}")

        # Cleanup
        for ws_id in reversed(created):
            c.close_workspace(ws_id)

    print("PASS: workspace reorder (by index, before, after)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
