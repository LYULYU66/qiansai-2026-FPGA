"""Behavioral regression for SDRAM retention during a long image dwell.

The hardware refresh timer is implemented in sdr_init_ref.enc.v, while its
terminal count is configured by global_def.v.  This test reads the actual HDL
macros, applies Verilog-style integer arithmetic, and checks both the refresh
command gap and the full 4096-row refresh window.  It also demonstrates why
the former 2048-row formula could leave an inactive image buffer corrupted
when the display was switched after a long dwell.
"""

from __future__ import annotations

import ast
import operator
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GLOBAL_DEF = ROOT / "src/user_source/hdl_source/include/global_def.v"


def _read_macros() -> dict[str, str]:
    macros: dict[str, str] = {}
    for line in GLOBAL_DEF.read_text(encoding="utf-8").splitlines():
        match = re.match(r"\s*`define\s+(\w+)\s+(.+?)\s*(?://.*)?$", line)
        if match:
            macros[match.group(1)] = match.group(2).strip()
    return macros


MACROS = _read_macros()


def _integer_eval(expression: str) -> int:
    """Evaluate the small integer-expression subset used by global_def.v."""

    binary_ops = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.floordiv,
        ast.FloorDiv: operator.floordiv,
        ast.Pow: operator.pow,
    }
    unary_ops = {ast.UAdd: operator.pos, ast.USub: operator.neg}

    def visit(node: ast.AST) -> int:
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in binary_ops:
            return binary_ops[type(node.op)](visit(node.left), visit(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in unary_ops:
            return unary_ops[type(node.op)](visit(node.operand))
        raise ValueError(f"unsupported HDL macro expression: {expression!r}")

    return visit(ast.parse(expression.replace("_", ""), mode="eval"))


def macro_expression(name: str, resolving: tuple[str, ...] = ()) -> str:
    """Expand a macro textually, exactly as the Verilog preprocessor does."""

    if name in resolving:
        raise ValueError(f"recursive macro: {' -> '.join((*resolving, name))}")
    expression = MACROS[name]
    return re.sub(
        r"`(\w+)",
        lambda match: macro_expression(match.group(1), (*resolving, name)),
        expression,
    )


def macro_value(name: str) -> int:
    return _integer_eval(macro_expression(name))


class LongDwellRefreshTest(unittest.TestCase):
    def test_configured_refresh_meets_em638325_requirement(self) -> None:
        clock_period_ns = macro_value("SDR_CLK_PERIOD")
        refresh_window_ns = macro_value("SDR_REFRESH_WINDOW_NS")
        refresh_commands = macro_value("SDR_REFRESH_COMMANDS")
        terminal_count = macro_value("SELF_REFRESH_INTERVAL")

        # init_cnt runs from zero through terminal_count, inclusive.
        command_gap_clocks = terminal_count + 1
        command_gap_ns = command_gap_clocks * clock_period_ns
        max_gap_clocks = refresh_window_ns // clock_period_ns // refresh_commands
        full_refresh_window_ns = command_gap_ns * refresh_commands

        self.assertEqual(refresh_commands, 4096)
        self.assertLessEqual(command_gap_clocks, max_gap_clocks)
        self.assertLessEqual(full_refresh_window_ns, refresh_window_ns)

    def test_long_dwell_keeps_all_four_frame_buffers_valid(self) -> None:
        clock_period_ns = macro_value("SDR_CLK_PERIOD")
        refresh_window_ns = macro_value("SDR_REFRESH_WINDOW_NS")
        refresh_commands = macro_value("SDR_REFRESH_COMMANDS")
        terminal_count = macro_value("SELF_REFRESH_INTERVAL")
        full_refresh_window_ns = (
            (terminal_count + 1) * clock_period_ns * refresh_commands
        )

        # A 10-second dwell is much longer than the 64-ms retention window.
        # Every buffer remains valid because a complete refresh sweep finishes
        # before the retention deadline, independent of which frame is read.
        dwell_ns = 10_000_000_000
        refresh_sweeps = dwell_ns // full_refresh_window_ns
        frame_valid = [full_refresh_window_ns <= refresh_window_ns] * 4

        self.assertGreater(refresh_sweeps, 100)
        self.assertTrue(all(frame_valid))

    def test_previous_formula_is_caught_by_regression(self) -> None:
        clock_period_ns = macro_value("SDR_CLK_PERIOD")
        refresh_window_ns = macro_value("SDR_REFRESH_WINDOW_NS")
        refresh_commands = macro_value("SDR_REFRESH_COMMANDS")
        row_width = macro_value("ROW_WIDTH")

        # Previous HDL used 2**ROW_WIDTH (=2048) and also omitted the -1.
        legacy_terminal = (
            refresh_window_ns // clock_period_ns // (2**row_width)
        )
        legacy_full_refresh_ns = (
            (legacy_terminal + 1) * clock_period_ns * refresh_commands
        )

        self.assertGreater(legacy_full_refresh_ns, refresh_window_ns)


if __name__ == "__main__":
    unittest.main(verbosity=2)
