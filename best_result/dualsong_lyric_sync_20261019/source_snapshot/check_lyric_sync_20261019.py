"""Compare the ModelSim timeline log with the generator schedule."""
from pathlib import Path
import sys
D = Path(__file__).resolve().parent.parent / "dual_board/image_link/sim/dualsong_20261005/lyricfix_20261019"
exp = [list(map(int, l.split())) for l in (D / "expected_events.txt").read_text().split("\n") if l]
got = [list(map(int, l.split())) for l in (D / "timeline_events.log").read_text().split("\n") if l]
assert len(exp) == len(got), (len(exp), len(got))
worst = 0
for e, g in zip(exp, got):
    assert e[0] == g[0] and e[2] == g[2] and e[3:] == g[3:], (e, g)
    worst = max(worst, abs(e[1] - g[1]))
assert worst <= 1, worst
print(f"timeline log matches schedule: {len(got)} events, max error {worst} sample(s)")
