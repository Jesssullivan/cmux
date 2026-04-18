#!/usr/bin/env python3
"""Socket API: pane.resize adjusts split divider ratios.

Verifies:
  1. Resize right grows the first child's share (ratio increases)
  2. Resize left grows the second child's share (ratio decreases)
  3. Ratio is clamped to [0.1, 0.9]
  4. Resize with custom amount steps the ratio proportionally
  5. Error on no split (single-pane workspace)
  6. Error on bad direction
  7. Error on no matching split ancestor for the given direction
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
    raise cmuxError(f"{label}: expected error, got success")


def main() -> int:
    ws = None
    with cmux(SOCKET_PATH) as c:
        try:
            ws = c.new_workspace()
            c.select_workspace(ws)
            time.sleep(0.1)

            # Single pane → resize should error (no split tree or trivial root)
            surfaces_1 = c.list_surfaces()
            if not surfaces_1:
                raise cmuxError("no surfaces in fresh workspace")
            solo_id = surfaces_1[0][1]

            _expect_error(
                "resize single pane",
                lambda: c._call(
                    "pane.resize",
                    {"workspace_id": ws, "pane_id": solo_id, "direction": "right"},
                ),
            )

            # Split right → creates [s0 | s1] horizontal split
            s1 = c.new_split("right")
            time.sleep(0.1)
            if not s1:
                raise cmuxError("surface.split returned no id")

            surfaces_2 = c.list_surfaces()
            if len(surfaces_2) < 2:
                raise cmuxError(f"expected >= 2 surfaces after split, got {len(surfaces_2)}")
            s0_id = surfaces_2[0][1]
            s1_id = surfaces_2[1][1]

            # Resize right from s0 (first child) → ratio increases from 0.5
            res1 = c._call(
                "pane.resize",
                {"workspace_id": ws, "pane_id": s0_id, "direction": "right"},
            )
            if not isinstance(res1, dict):
                raise cmuxError(f"resize right returned {res1!r}")
            r1 = res1.get("ratio")
            if r1 is None or r1 <= 0.5:
                raise cmuxError(f"resize right should increase ratio above 0.5, got {r1}")

            # Resize left from s1 (second child) → ratio decreases
            res2 = c._call(
                "pane.resize",
                {"workspace_id": ws, "pane_id": s1_id, "direction": "left"},
            )
            r2 = res2.get("ratio")
            if r2 is None or r2 >= r1:
                raise cmuxError(f"resize left should decrease ratio below {r1}, got {r2}")

            # Multiple amount: resize right by 5 from s0 → big jump
            res3 = c._call(
                "pane.resize",
                {
                    "workspace_id": ws,
                    "pane_id": s0_id,
                    "direction": "right",
                    "amount": 5,
                },
            )
            r3 = res3.get("ratio")
            if r3 is None or r3 <= r2:
                raise cmuxError(f"resize right amount=5 should increase, got {r3}")

            # Clamp at 0.9: keep pushing right
            for _ in range(20):
                c._call(
                    "pane.resize",
                    {"workspace_id": ws, "pane_id": s0_id, "direction": "right", "amount": 5},
                )
            res_max = c._call(
                "pane.resize",
                {"workspace_id": ws, "pane_id": s0_id, "direction": "right"},
            )
            r_max = res_max.get("ratio", 0)
            if r_max > 0.9 + 0.001:
                raise cmuxError(f"ratio should clamp at 0.9, got {r_max}")

            # Clamp at 0.1: push left from s1 many times
            for _ in range(20):
                c._call(
                    "pane.resize",
                    {"workspace_id": ws, "pane_id": s1_id, "direction": "left", "amount": 5},
                )
            res_min = c._call(
                "pane.resize",
                {"workspace_id": ws, "pane_id": s1_id, "direction": "left"},
            )
            r_min = res_min.get("ratio", 1)
            if r_min < 0.1 - 0.001:
                raise cmuxError(f"ratio should clamp at 0.1, got {r_min}")

            # Bad direction → error
            _expect_error(
                "bad direction",
                lambda: c._call(
                    "pane.resize",
                    {"workspace_id": ws, "pane_id": s0_id, "direction": "diagonal"},
                ),
            )

            # Resize up/down on a horizontal-only split → no matching ancestor
            _expect_error(
                "no vertical split",
                lambda: c._call(
                    "pane.resize",
                    {"workspace_id": ws, "pane_id": s0_id, "direction": "up"},
                ),
            )

        finally:
            if ws is not None:
                try:
                    c.close_workspace(ws)
                except Exception:
                    pass

    print("PASS: pane.resize (ratio adjust, clamp, errors)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except cmuxError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
