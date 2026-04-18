#!/usr/bin/env python3
"""Socket API: system.tree on Linux.

Asserts that the tree composes existing window/workspace/surface state into
the macOS-shaped { active, windows[].workspaces[].panes[].surfaces[] }
envelope. Linux currently uses 1:1 panel:pane mapping, so every pane carries
exactly one surface and the pane_id/surface_id of that pair are identical.

This test creates an extra workspace so the tree contains more than the
default workspace, and (best-effort) re-selects the original to leave the
session unchanged on exit.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _is_uuid_hex(s: object) -> bool:
    return isinstance(s, str) and len(s) == 32 and all(ch in "0123456789abcdef" for ch in s)


def _assert_window_node(node: dict) -> None:
    if not _is_uuid_hex(node.get("id")):
        raise cmuxError(f"window.id not a 32-char hex: {node!r}")
    if not isinstance(node.get("ref"), str) or not node["ref"].startswith("window:"):
        raise cmuxError(f"window.ref not 'window:N': {node!r}")
    if not isinstance(node.get("index"), int):
        raise cmuxError(f"window.index missing/not int: {node!r}")
    if not isinstance(node.get("workspace_count"), int):
        raise cmuxError(f"window.workspace_count missing/not int: {node!r}")
    workspaces = node.get("workspaces")
    if not isinstance(workspaces, list):
        raise cmuxError(f"window.workspaces not a list: {node!r}")
    if len(workspaces) != node["workspace_count"]:
        raise cmuxError(
            f"window.workspace_count={node['workspace_count']} but len(workspaces)={len(workspaces)}"
        )


def _assert_workspace_node(node: dict, expected_index: int) -> None:
    if not _is_uuid_hex(node.get("id")):
        raise cmuxError(f"workspace.id not hex: {node!r}")
    if node.get("ref") != f"workspace:{expected_index}":
        raise cmuxError(f"workspace.ref expected 'workspace:{expected_index}', got {node!r}")
    if node.get("index") != expected_index:
        raise cmuxError(f"workspace.index expected {expected_index}, got {node!r}")
    if not isinstance(node.get("title"), str):
        raise cmuxError(f"workspace.title not string: {node!r}")
    if not isinstance(node.get("selected"), bool):
        raise cmuxError(f"workspace.selected not bool: {node!r}")
    if not isinstance(node.get("pinned"), bool):
        raise cmuxError(f"workspace.pinned not bool: {node!r}")
    panes = node.get("panes")
    if not isinstance(panes, list):
        raise cmuxError(f"workspace.panes not list: {node!r}")


def _assert_pane_node(node: dict, expected_index: int) -> None:
    if not _is_uuid_hex(node.get("id")):
        raise cmuxError(f"pane.id not hex: {node!r}")
    if node.get("ref") != f"pane:{expected_index}":
        raise cmuxError(f"pane.ref expected 'pane:{expected_index}', got {node!r}")
    if node.get("index") != expected_index:
        raise cmuxError(f"pane.index expected {expected_index}, got {node!r}")
    if node.get("surface_count") != 1:
        raise cmuxError(f"pane.surface_count expected 1 on Linux 1:1 mapping, got {node!r}")
    if node.get("selected_surface_id") != node.get("id"):
        raise cmuxError(f"pane.selected_surface_id should equal pane.id on Linux: {node!r}")
    surfaces = node.get("surfaces")
    if not isinstance(surfaces, list) or len(surfaces) != 1:
        raise cmuxError(f"pane.surfaces should have exactly one entry on Linux: {node!r}")


def _assert_surface_node(node: dict, expected_pane_id: str, expected_pane_index: int) -> None:
    if node.get("id") != expected_pane_id:
        raise cmuxError(f"surface.id should equal pane.id on Linux 1:1: {node!r}")
    if node.get("pane_id") != expected_pane_id:
        raise cmuxError(f"surface.pane_id should equal owning pane.id: {node!r}")
    if node.get("ref") != f"surface:{expected_pane_index}":
        raise cmuxError(f"surface.ref expected 'surface:{expected_pane_index}', got {node!r}")
    if node.get("pane_ref") != f"pane:{expected_pane_index}":
        raise cmuxError(f"surface.pane_ref expected 'pane:{expected_pane_index}', got {node!r}")
    if node.get("index_in_pane") != 0:
        raise cmuxError(f"surface.index_in_pane should be 0 on Linux 1:1: {node!r}")
    if node.get("type") not in {"terminal", "browser", "markdown"}:
        raise cmuxError(f"surface.type unexpected: {node!r}")
    for key in ("focused", "selected", "selected_in_pane"):
        if not isinstance(node.get(key), bool):
            raise cmuxError(f"surface.{key} should be bool: {node!r}")
    if not isinstance(node.get("title"), str):
        raise cmuxError(f"surface.title should be string: {node!r}")


def _run(c: cmux) -> None:
    initial_workspace = c.current_workspace()
    if not _is_uuid_hex(initial_workspace):
        raise cmuxError(f"current_workspace returned non-hex id: {initial_workspace!r}")

    res = c._call("system.tree")
    if not isinstance(res, dict):
        raise cmuxError(f"system.tree expected dict, got {type(res).__name__}: {res!r}")

    active = res.get("active")
    if not isinstance(active, dict):
        raise cmuxError(f"system.tree.active not a dict: {active!r}")
    if active.get("workspace_id") != initial_workspace:
        raise cmuxError(
            f"active.workspace_id={active.get('workspace_id')!r} mismatched current={initial_workspace!r}"
        )

    windows = res.get("windows")
    if not isinstance(windows, list) or not windows:
        raise cmuxError(f"system.tree.windows must be non-empty list: {windows!r}")

    found_initial_in_tree = False
    for window in windows:
        _assert_window_node(window)
        for ws_idx, ws in enumerate(window["workspaces"]):
            _assert_workspace_node(ws, ws_idx)
            if ws["id"] == initial_workspace:
                found_initial_in_tree = True
            for pane_idx, pane in enumerate(ws["panes"]):
                _assert_pane_node(pane, pane_idx)
                for surface in pane["surfaces"]:
                    _assert_surface_node(surface, pane["id"], pane_idx)

    if not found_initial_in_tree:
        raise cmuxError(
            f"current workspace {initial_workspace!r} not present in any window in the tree"
        )


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        # Snapshot the original selected workspace so we can restore it.
        try:
            baseline = c.current_workspace()
        except cmuxError:
            baseline = None

        # Add a second workspace so the tree exercises a multi-workspace shape.
        created = c.new_workspace()

        try:
            _run(c)
        finally:
            if baseline:
                try:
                    c.select_workspace(baseline)
                except Exception:
                    pass
            if created:
                try:
                    c.close_workspace(created)
                except Exception:
                    pass

    print("PASS: system.tree (active pointer, window/workspace/pane/surface composition)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
