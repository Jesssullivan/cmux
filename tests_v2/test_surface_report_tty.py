#!/usr/bin/env python3
"""Socket API: surface.report_tty registers a TTY name on a panel.

Linux's report_tty is a metadata-only mutation: there is no PortScanner /
remote workspace plumbing on Linux yet, so the handler simply duplicates
the supplied tty_name onto Panel.tty_name and echoes it back.

This test verifies:
  1. report_tty without surface_id falls back to the focused surface
  2. report_tty with explicit surface_id targets that surface
  3. tty_name with surrounding whitespace is trimmed
  4. missing / empty / whitespace-only tty_name -> error
  5. invalid workspace_id / surface_id -> error
  6. response shape: {workspace_id, surface_id, tty_name}
"""

import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")

UUID_HEX_RE = re.compile(r"^[0-9a-f]{32}$")


def _assert_uuid(label: str, value: object) -> None:
    if not isinstance(value, str) or not UUID_HEX_RE.match(value):
        raise cmuxError(f"{label} not a 32-char hex UUID: {value!r}")


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
        _assert_uuid("focused surface_id", focused_id)

        # 1. No surface_id — defaults to focused surface
        res1 = c._call(
            "surface.report_tty",
            {"workspace_id": ws_id, "tty_name": "/dev/pts/42"},
        )
        if not isinstance(res1, dict):
            raise cmuxError(f"report_tty (default surface) returned {res1!r}")
        if res1.get("workspace_id") != ws_id:
            raise cmuxError(
                f"workspace_id echo mismatch: {res1.get('workspace_id')!r} vs {ws_id!r}"
            )
        if res1.get("surface_id") != focused_id:
            raise cmuxError(
                f"default surface_id should equal focused {focused_id!r}, got {res1.get('surface_id')!r}"
            )
        if res1.get("tty_name") != "/dev/pts/42":
            raise cmuxError(f"tty_name echo mismatch: {res1.get('tty_name')!r}")

        # 2. Explicit surface_id targets that surface (here it's the same one)
        res2 = c._call(
            "surface.report_tty",
            {
                "workspace_id": ws_id,
                "surface_id": focused_id,
                "tty_name": "/dev/pts/99",
            },
        )
        if res2.get("surface_id") != focused_id:
            raise cmuxError(f"explicit surface_id mismatch: {res2!r}")
        if res2.get("tty_name") != "/dev/pts/99":
            raise cmuxError(f"second tty_name not echoed: {res2!r}")

        # 3. Surrounding whitespace gets trimmed
        res3 = c._call(
            "surface.report_tty",
            {"workspace_id": ws_id, "tty_name": "  /dev/pts/7\n"},
        )
        if res3.get("tty_name") != "/dev/pts/7":
            raise cmuxError(f"tty_name not trimmed: {res3!r}")

        # 4. Empty / whitespace-only / missing tty_name -> error
        _expect_error(
            "missing tty_name",
            lambda: c._call("surface.report_tty", {"workspace_id": ws_id}),
        )
        _expect_error(
            "empty tty_name",
            lambda: c._call(
                "surface.report_tty",
                {"workspace_id": ws_id, "tty_name": ""},
            ),
        )
        _expect_error(
            "whitespace-only tty_name",
            lambda: c._call(
                "surface.report_tty",
                {"workspace_id": ws_id, "tty_name": "   \t\n"},
            ),
        )

        # 5. Invalid ids -> error
        _expect_error(
            "invalid workspace_id",
            lambda: c._call(
                "surface.report_tty",
                {"workspace_id": "0" * 32, "tty_name": "/dev/pts/0"},
            ),
        )
        _expect_error(
            "invalid surface_id",
            lambda: c._call(
                "surface.report_tty",
                {
                    "workspace_id": ws_id,
                    "surface_id": "0" * 32,
                    "tty_name": "/dev/pts/0",
                },
            ),
        )

        # Cleanup
        c.close_workspace(ws_id)

    print("PASS: surface.report_tty (default + explicit + trim + errors)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
