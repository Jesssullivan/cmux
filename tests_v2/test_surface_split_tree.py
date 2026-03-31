#!/usr/bin/env python3
"""Socket API: surface split, list, close, focus tracking in split tree."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        # Create fresh workspace (starts with 1 mock panel)
        ws_id = c.new_workspace()
        c.select_workspace(ws_id)
        time.sleep(0.1)

        surfaces_1 = c.list_surfaces()
        if len(surfaces_1) < 1:
            raise cmuxError(f"Expected >= 1 initial surface, got {len(surfaces_1)}")

        # Split right — should create a second surface
        s2 = c.new_split("right")
        time.sleep(0.1)
        if not s2:
            raise cmuxError("surface.split returned no surface_id")

        surfaces_2 = c.list_surfaces()
        if len(surfaces_2) < 2:
            raise cmuxError(f"Expected >= 2 surfaces after split, got {len(surfaces_2)}")

        # Split again — nested
        s3 = c.new_split("right")
        time.sleep(0.1)

        surfaces_3 = c.list_surfaces()
        if len(surfaces_3) < 3:
            raise cmuxError(f"Expected >= 3 surfaces after second split, got {len(surfaces_3)}")

        # Close the last created surface
        c.close_surface(s3)
        time.sleep(0.1)

        surfaces_4 = c.list_surfaces()
        if len(surfaces_4) != len(surfaces_3) - 1:
            raise cmuxError(f"Expected {len(surfaces_3) - 1} after close, got {len(surfaces_4)}")

        # Verify some surface is focused
        focused = [s for s in surfaces_4 if s[2]]  # s[2] is is_focused
        if not focused:
            raise cmuxError("No surface focused after close")

        # Verify surface IDs are stable UUIDs
        remaining_ids = {s[1] for s in surfaces_4}
        if s3 in remaining_ids:
            raise cmuxError(f"Closed surface {s3} still appears in list")

        # Cleanup
        c.close_workspace(ws_id)

    print("PASS: surface split tree (split, list, close, focus)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
