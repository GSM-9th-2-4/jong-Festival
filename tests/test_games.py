"""모든 게임이 규칙(NAME, play(screen, win))을 지키는지 + 확률표 확인.
PR 올리기 전에: python tests/test_games.py"""
import importlib
import inspect
import os
import pkgutil
import sys
from collections import Counter
from pathlib import Path

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import coupon  # noqa: E402
import games  # noqa: E402


def test_games_follow_contract():
    names = []
    for m in pkgutil.iter_modules(games.__path__):
        mod = importlib.import_module(f"games.{m.name}")
        assert isinstance(getattr(mod, "NAME", None), str), f"{m.name}: NAME 없음"
        assert callable(getattr(mod, "play", None)), f"{m.name}: play() 없음"
        assert len(inspect.signature(mod.play).parameters) == 2, f"{m.name}: play(screen, win) 형태여야 함"
        if not m.name.startswith("_"):
            names.append(mod.NAME)
    assert len(names) == len(set(names)), f"NAME 중복: {names}"


def test_prize_odds():
    n = 100_000
    got = Counter(coupon.draw() for _ in range(n))
    for prize, pct in coupon.PRIZES.items():
        assert abs(got[prize] / n * 100 - pct) < 1, f"{prize}: {got[prize] / n * 100:.1f}% (기대 {pct}%)"


if __name__ == "__main__":
    test_games_follow_contract()
    test_prize_odds()
    print("ok")
