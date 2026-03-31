#!/usr/bin/env python3
"""Socket API: workspace create, rename, list, close lifecycle."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def main() -> int:
    created: list[str] = []
    with cmux(SOCKET_PATH) as c:
        # Count initial workspaces
        initial = c.list_workspaces()
        initial_count = len(initial)

        # Create 4 new workspaces
        for i in range(4):
            ws_id = c.new_workspace()
            if not ws_id:
                raise cmuxError(f"workspace.create #{i} returned no id")
            created.append(ws_id)
            time.sleep(0.05)

        # Verify count
        after_create = c.list_workspaces()
        expected = initial_count + 4
        if len(after_create) != expected:
            raise cmuxError(f"Expected {expected} workspaces, got {len(after_create)}")

        # Rename the second created workspace
        target_ws = created[1]
        c.rename_workspace(target_ws, "Renamed-WS")
        time.sleep(0.05)

        ws_list = c.list_workspaces()
        found_rename = False
        for _idx, wid, title, _sel in ws_list:
            if wid == target_ws and title == "Renamed-WS":
                found_rename = True
                break
        if not found_rename:
            titles = [(wid, t) for _, wid, t, _ in ws_list]
            raise cmuxError(f"Rename not reflected in list: {titles}")

        # Close workspaces in reverse order
        for ws_id in reversed(created):
            c.close_workspace(ws_id)
            time.sleep(0.05)

        # Verify we're back to initial count
        final = c.list_workspaces()
        if len(final) != initial_count:
            raise cmuxError(f"Expected {initial_count} after cleanup, got {len(final)}")

    print("PASS: workspace lifecycle (create, rename, list, close)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
