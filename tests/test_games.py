"""모든 게임이 규칙(NAME, play)을 지키는지 확인. PR 올리기 전에: python -m pytest  또는  python tests/test_games.py"""
import importlib
import os
import pkgutil
import sys
from pathlib import Path

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import games  # noqa: E402


def test_games_follow_contract():
    names = []
    for m in pkgutil.iter_modules(games.__path__):
        mod = importlib.import_module(f"games.{m.name}")
        assert isinstance(getattr(mod, "NAME", None), str), f"{m.name}: NAME 없음"
        assert callable(getattr(mod, "play", None)), f"{m.name}: play() 없음"
        if not m.name.startswith("_"):
            names.append(mod.NAME)
    assert len(names) == len(set(names)), f"NAME 중복: {names}"


if __name__ == "__main__":
    test_games_follow_contract()
    print("ok")
