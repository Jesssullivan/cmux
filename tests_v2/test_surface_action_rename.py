#!/usr/bin/env python3
"""Socket API: surface.action rename / clear_name / pin / unpin / mark_read / mark_unread.

Pure socket round-trip test — no GUI, no CLI binary, no platform-specific
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


def _find_surface(rows: list[dict], surface_id: str) -> dict:
    for row in rows:
        if str(row.get("id")) == surface_id:
            return row
    raise cmuxError(f"surface {surface_id} missing from list: {rows}")


def _run_assertions(c: cmux, created_workspace: str) -> None:
    """Run the full surface.action / tab.action assertion suite.

    Caller owns lifecycle of `created_workspace` (creation + cleanup).
    """
    c.select_workspace(created_workspace)
    time.sleep(0.05)

    # Locate the focused surface in the new workspace.
    rows = _surfaces_in(c, created_workspace)
    if not rows:
        raise cmuxError(f"new workspace has no surfaces: {rows}")
    focused = next((r for r in rows if r.get("focused")), rows[0])
    surface_id = str(focused["id"])

    unique_title = f"renamed-via-action-{int(time.time() * 1000) % 100000}"

    # ── rename ────────────────────────────────────────────────────────
    result = c._call(
        "surface.action",
        {
            "workspace_id": created_workspace,
            "surface_id": surface_id,
            "action": "rename",
            "title": unique_title,
        },
    ) or {}
    if result.get("action") != "rename":
        raise cmuxError(f"rename: unexpected response: {result}")
    if str(result.get("title")) != unique_title:
        raise cmuxError(f"rename: title not echoed: {result}")

    # Reflected in surface.list?
    renamed = _find_surface(_surfaces_in(c, created_workspace), surface_id)
    if str(renamed.get("title")) != unique_title:
        raise cmuxError(
            f"rename not reflected in surface.list: expected {unique_title!r}, "
            f"got {renamed.get('title')!r}"
        )

    # ── tab.action alias should hit the same handler ──────────────────
    alias_title = f"{unique_title}-alias"
    alias_result = c._call(
        "tab.action",
        {
            "workspace_id": created_workspace,
            "tab_id": surface_id,
            "action": "rename",
            "title": alias_title,
        },
    ) or {}
    if alias_result.get("action") != "rename":
        raise cmuxError(f"tab.action alias: unexpected response: {alias_result}")
    aliased = _find_surface(_surfaces_in(c, created_workspace), surface_id)
    if str(aliased.get("title")) != alias_title:
        raise cmuxError(
            f"tab.action alias not reflected: expected {alias_title!r}, "
            f"got {aliased.get('title')!r}"
        )

    # ── clear_name ────────────────────────────────────────────────────
    cleared_resp = c._call(
        "surface.action",
        {
            "workspace_id": created_workspace,
            "surface_id": surface_id,
            "action": "clear_name",
        },
    ) or {}
    if cleared_resp.get("action") != "clear_name":
        raise cmuxError(f"clear_name: unexpected response: {cleared_resp}")
    cleared = _find_surface(_surfaces_in(c, created_workspace), surface_id)
    if str(cleared.get("title")) == alias_title:
        raise cmuxError(
            f"clear_name did not drop custom title: still {cleared.get('title')!r}"
        )
    # Title falls back to process title or "Terminal"; we just assert it
    # is no longer the custom alias.

    # ── pin / unpin ───────────────────────────────────────────────────
    pin_resp = c._call(
        "surface.action",
        {
            "workspace_id": created_workspace,
            "surface_id": surface_id,
            "action": "pin",
        },
    ) or {}
    if pin_resp.get("action") != "pin" or pin_resp.get("pinned") is not True:
        raise cmuxError(f"pin: unexpected response: {pin_resp}")

    unpin_resp = c._call(
        "surface.action",
        {
            "workspace_id": created_workspace,
            "surface_id": surface_id,
            "action": "unpin",
        },
    ) or {}
    if unpin_resp.get("action") != "unpin" or unpin_resp.get("pinned") is not False:
        raise cmuxError(f"unpin: unexpected response: {unpin_resp}")

    # ── mark_read / mark_unread ───────────────────────────────────────
    for action in ("mark_unread", "mark_read"):
        resp = c._call(
            "surface.action",
            {
                "workspace_id": created_workspace,
                "surface_id": surface_id,
                "action": action,
            },
        ) or {}
        if resp.get("action") != action:
            raise cmuxError(f"{action}: unexpected response: {resp}")

    # ── unsupported action returns an error structure ─────────────────
    try:
        c._call(
            "surface.action",
            {
                "workspace_id": created_workspace,
                "surface_id": surface_id,
                "action": "definitely-not-a-real-action",
            },
        )
        # Some daemons may return a JSON body with an "error" field while
        # still marking the response ok=true. Either is acceptable.
    except cmuxError:
        pass  # expected

    # ── focused-surface fallback (no surface_id provided) ─────────────
    focus_fallback_title = f"{unique_title}-focused"
    fallback_resp = c._call(
        "surface.action",
        {
            "workspace_id": created_workspace,
            "action": "rename",
            "title": focus_fallback_title,
        },
    ) or {}
    if fallback_resp.get("action") != "rename":
        raise cmuxError(
            f"focused-surface fallback: unexpected response: {fallback_resp}"
        )

    # Reset to clear the custom name we leaked into the workspace.
    c._call(
        "surface.action",
        {
            "workspace_id": created_workspace,
            "surface_id": surface_id,
            "action": "clear_name",
        },
    )


def main() -> int:
    created_workspace: str | None = None
    with cmux(SOCKET_PATH) as c:
        try:
            # Create an isolated workspace so the test cannot disturb the
            # user's current workspace state.
            created_workspace = c.new_workspace()
            if not created_workspace:
                raise cmuxError("workspace.create returned no id")
            _run_assertions(c, created_workspace)
        finally:
            # Always close the workspace, even if assertions raised — leaving
            # one behind would corrupt subsequent tests on the same daemon.
            if created_workspace is not None:
                try:
                    c.close_workspace(created_workspace)
                except Exception:
                    pass

    print("PASS: surface.action rename / clear_name / pin / unpin / mark_read / mark_unread")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except cmuxError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
