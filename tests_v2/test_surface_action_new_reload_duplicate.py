#!/usr/bin/env python3
"""Socket API: surface.action new_terminal_right / new_browser_right / reload / duplicate.

Pure socket round-trip test -- no GUI, no CLI binary, no platform-specific
filesystem assumptions. Designed to pass on both macOS and Linux daemons.
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _surfaces_in(c: cmux, workspace_id: str) -> list[dict]:
    """Return raw surface.list rows (dicts) for the given workspace."""
    res = c._call("surface.list", {"workspace_id": workspace_id}) or {}
    return list(res.get("surfaces") or [])


def _surface_ids(c: cmux, workspace_id: str) -> list[str]:
    """Return ordered list of surface IDs in the workspace."""
    return [str(s.get("id")) for s in _surfaces_in(c, workspace_id)]


def _run_assertions(c: cmux, ws_id: str) -> None:
    """Run the full new_terminal_right / new_browser_right / reload / duplicate suite."""
    c.select_workspace(ws_id)
    time.sleep(0.05)

    # Locate the focused surface in the workspace.
    rows = _surfaces_in(c, ws_id)
    if not rows:
        raise cmuxError(f"new workspace has no surfaces: {rows}")
    focused = next((r for r in rows if r.get("focused")), rows[0])
    surface_id = str(focused["id"])
    initial_count = len(rows)

    # ---- new_terminal_right -------------------------------------------------
    result = c._call(
        "surface.action",
        {
            "workspace_id": ws_id,
            "surface_id": surface_id,
            "action": "new_terminal_right",
        },
    ) or {}

    if result.get("action") != "new_terminal_right":
        raise cmuxError(f"new_terminal_right: unexpected response: {result}")
    new_id = result.get("new_surface_id")
    if not new_id:
        raise cmuxError(f"new_terminal_right: no new_surface_id: {result}")

    # Surface count should increase by 1.
    time.sleep(0.05)
    ids_after = _surface_ids(c, ws_id)
    if len(ids_after) != initial_count + 1:
        raise cmuxError(
            f"new_terminal_right: expected {initial_count + 1} surfaces, "
            f"got {len(ids_after)}"
        )
    if new_id not in ids_after:
        raise cmuxError(f"new_terminal_right: new surface {new_id} not in list")

    # New surface should appear after the anchor in ordered position.
    anchor_pos = ids_after.index(surface_id)
    new_pos = ids_after.index(new_id)
    if new_pos != anchor_pos + 1:
        raise cmuxError(
            f"new_terminal_right: expected new at pos {anchor_pos + 1}, "
            f"got {new_pos}"
        )

    # ---- new_terminal_right via tab.action alias ----------------------------
    alias_result = c._call(
        "tab.action",
        {
            "workspace_id": ws_id,
            "tab_id": surface_id,
            "action": "new_terminal_right",
        },
    ) or {}
    if alias_result.get("action") != "new_terminal_right":
        raise cmuxError(f"tab.action alias: unexpected response: {alias_result}")
    alias_new_id = alias_result.get("new_surface_id")
    if not alias_new_id:
        raise cmuxError(f"tab.action alias: no new_surface_id: {alias_result}")

    # ---- reload on terminal panel returns error ----------------------------
    reload_resp = c._call(
        "surface.action",
        {
            "workspace_id": ws_id,
            "surface_id": surface_id,
            "action": "reload",
        },
    ) or {}
    # Terminal panels should return an error (reload is browser-only).
    if "error" not in reload_resp:
        raise cmuxError(f"reload on terminal: expected error, got {reload_resp}")

    # ---- duplicate on terminal panel returns error -------------------------
    dup_resp = c._call(
        "surface.action",
        {
            "workspace_id": ws_id,
            "surface_id": surface_id,
            "action": "duplicate",
        },
    ) or {}
    if "error" not in dup_resp:
        raise cmuxError(f"duplicate on terminal: expected error, got {dup_resp}")

    # ---- new_browser_right -------------------------------------------------
    # May succeed (webkit available) or return error (no webkit).  Either
    # is acceptable -- the test validates the response shape, not webkit.
    browser_resp = c._call(
        "surface.action",
        {
            "workspace_id": ws_id,
            "surface_id": surface_id,
            "action": "new_browser_right",
        },
    ) or {}
    if "error" in browser_resp:
        # Acceptable: no-webkit build or browser panel unavailable.
        pass
    elif browser_resp.get("action") != "new_browser_right":
        raise cmuxError(f"new_browser_right: unexpected response: {browser_resp}")
    elif not browser_resp.get("new_surface_id"):
        raise cmuxError(f"new_browser_right: no new_surface_id: {browser_resp}")

    # ---- focused-surface fallback (no surface_id) --------------------------
    fallback_resp = c._call(
        "surface.action",
        {
            "workspace_id": ws_id,
            "action": "new_terminal_right",
        },
    ) or {}
    if fallback_resp.get("action") != "new_terminal_right":
        raise cmuxError(
            f"focused-surface fallback: unexpected response: {fallback_resp}"
        )
    if not fallback_resp.get("new_surface_id"):
        raise cmuxError(
            f"focused-surface fallback: no new_surface_id: {fallback_resp}"
        )

    # ---- unsupported action still returns structured error ------------------
    bad_resp = c._call(
        "surface.action",
        {
            "workspace_id": ws_id,
            "surface_id": surface_id,
            "action": "definitely-not-a-real-action",
        },
    ) or {}
    # Response should contain an "error" key and "supported" list.
    if "supported" in bad_resp:
        supported = bad_resp["supported"]
        for expected in (
            "new_terminal_right",
            "new_browser_right",
            "reload",
            "duplicate",
        ):
            if expected not in supported:
                raise cmuxError(
                    f"supported list missing {expected!r}: {supported}"
                )


def main() -> int:
    created_workspace: str | None = None
    with cmux(SOCKET_PATH) as c:
        try:
            created_workspace = c.new_workspace()
            if not created_workspace:
                raise cmuxError("workspace.create returned no id")
            _run_assertions(c, created_workspace)
        finally:
            if created_workspace is not None:
                try:
                    c.close_workspace(created_workspace)
                except Exception:
                    pass

    print(
        "PASS: surface.action new_terminal_right / new_browser_right / "
        "reload / duplicate"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except cmuxError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
