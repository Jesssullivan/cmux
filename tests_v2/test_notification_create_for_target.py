#!/usr/bin/env python3
"""Socket API: notification.create_for_target requires both ids and routes correctly.

Linux's create_for_target is the strict variant of create_for_surface:
both workspace_id and surface_id are required, and the surface must
belong to the workspace. Successful calls add a flash to the surface
and append to the in-memory notification store.

This test verifies:
  1. Successful call with valid ids returns {workspace_id, surface_id}
  2. Notification appears in notification.list with the right surface_id
  3. Repeated calls increment notification.list count
  4. Missing workspace_id / surface_id -> error
  5. Invalid workspace_id / surface_id -> error
  6. Spurious title/subtitle/body params accepted
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _expect_error(label: str, fn) -> None:
    try:
        fn()
    except cmuxError:
        return
    raise cmuxError(f"{label}: expected error, call returned successfully")


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        ws_id = c.new_workspace()
        c.select_workspace(ws_id)
        time.sleep(0.1)

        surfaces = c.list_surfaces()
        if not surfaces:
            raise cmuxError("Expected at least one surface in fresh workspace")
        focused = next((s for s in surfaces if s[2]), None)
        if focused is None:
            raise cmuxError("No focused surface in fresh workspace")
        focused_id = focused[1]

        # Baseline notification count
        before = c._call("notification.list") or {}
        before_n = len(before.get("notifications", []))

        # 1. Successful call
        res = c._call(
            "notification.create_for_target",
            {
                "workspace_id": ws_id,
                "surface_id": focused_id,
                "title": "Build done",
                "subtitle": "macOS-shape param accepted",
                "body": "All green",
            },
        )
        if not isinstance(res, dict):
            raise cmuxError(f"create_for_target returned {res!r}")
        if res.get("workspace_id") != ws_id:
            raise cmuxError(f"workspace_id echo mismatch: {res!r}")
        if res.get("surface_id") != focused_id:
            raise cmuxError(f"surface_id echo mismatch: {res!r}")

        # 2. Notification recorded with correct surface_id
        after = c._call("notification.list") or {}
        after_list = after.get("notifications", [])
        if len(after_list) != before_n + 1:
            raise cmuxError(
                f"expected notification count {before_n + 1}, got {len(after_list)}"
            )
        last = after_list[-1]
        if last.get("surface_id") != focused_id:
            raise cmuxError(f"notification surface_id mismatch: {last!r}")

        # 3. Repeated calls accumulate
        c._call(
            "notification.create_for_target",
            {"workspace_id": ws_id, "surface_id": focused_id, "title": "Second"},
        )
        again = c._call("notification.list") or {}
        if len(again.get("notifications", [])) != before_n + 2:
            raise cmuxError(
                f"expected notification count {before_n + 2} after second, got {len(again['notifications'])}"
            )

        # 4. Missing ids -> error
        _expect_error(
            "missing workspace_id",
            lambda: c._call(
                "notification.create_for_target",
                {"surface_id": focused_id, "title": "No ws"},
            ),
        )
        _expect_error(
            "missing surface_id",
            lambda: c._call(
                "notification.create_for_target",
                {"workspace_id": ws_id, "title": "No surface"},
            ),
        )

        # 5. Invalid ids -> error
        _expect_error(
            "invalid workspace_id",
            lambda: c._call(
                "notification.create_for_target",
                {
                    "workspace_id": "0" * 32,
                    "surface_id": focused_id,
                    "title": "Bad ws",
                },
            ),
        )
        _expect_error(
            "invalid surface_id",
            lambda: c._call(
                "notification.create_for_target",
                {
                    "workspace_id": ws_id,
                    "surface_id": "0" * 32,
                    "title": "Bad surface",
                },
            ),
        )

        # Cleanup
        c._call("notification.clear")
        c.close_workspace(ws_id)

    print("PASS: notification.create_for_target (success, errors, accumulation)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
