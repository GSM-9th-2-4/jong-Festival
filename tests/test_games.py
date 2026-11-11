"""PR 올리기 전에: python tests/test_games.py
1) 모든 게임이 규칙(NAME, play(screen, win))을 지키는지
2) 모든 게임을 당첨/꽝 두 번씩 '빨리 감기'로 끝까지 돌려서 안 터지고 True 로 끝나는지
3) 확률표 / 쿠폰 저장소가 맞게 동작하는지"""
import importlib
import inspect
import os
import pkgutil
import random
import sys
from collections import Counter
from pathlib import Path

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pygame  # noqa: E402

import games  # noqa: E402
from core import store  # noqa: E402

LIMIT_MS = 180_000  # 게임 한 판 최대 길이(가상 시간)


def all_games():
    return [importlib.import_module(f"games.{m.name}") for m in pkgutil.iter_modules(games.__path__)]


class FastForward:
    """시간을 가짜로 흘려서 게임을 순식간에 돌리고, 봇이 스페이스/엔터/클릭을 계속 넣어줌.
    on_frame(n, screen) 을 주면 프레임마다 호출 (스크린샷용)."""

    def __init__(self, on_frame=None, seed=1):
        self.on_frame, self.rng = on_frame, random.Random(seed)

    def __enter__(self):
        self.t = self.n = 0
        self.saved = (pygame.time.get_ticks, pygame.time.Clock, pygame.display.flip)
        ff = self

        class Clock:
            def tick(self, fps=60):
                return 16

            def get_fps(self):
                return 60.0

        def flip():
            ff.n += 1
            ff.t += 16
            if ff.on_frame:
                ff.on_frame(ff.n, pygame.display.get_surface())
            if ff.t > LIMIT_MS:
                raise TimeoutError("게임이 3분(가상 시간) 안에 안 끝남")
            if ff.n % 7 == 0:  # 봇 입력
                pos = (ff.rng.randrange(20, 780, 40), ff.rng.randrange(20, 580, 40))
                pygame.event.post(pygame.event.Event(pygame.MOUSEBUTTONDOWN, button=1, pos=pos))
                pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=ff.rng.choice((pygame.K_SPACE, pygame.K_RETURN))))

        pygame.time.get_ticks, pygame.time.Clock, pygame.display.flip = (lambda: ff.t), Clock, flip
        return self

    def __exit__(self, *exc):
        pygame.time.get_ticks, pygame.time.Clock, pygame.display.flip = self.saved
        pygame.event.clear()


def test_games_follow_contract():
    names = []
    for mod in all_games():
        short = mod.__name__
        assert isinstance(getattr(mod, "NAME", None), str), f"{short}: NAME 없음"
        assert callable(getattr(mod, "play", None)), f"{short}: play() 없음"
        assert len(inspect.signature(mod.play).parameters) == 2, f"{short}: play(screen, win) 형태여야 함"
        if not short.split(".")[-1].startswith("_"):
            names.append(mod.NAME)
    assert len(names) == len(set(names)), f"NAME 중복: {names}"


def test_games_run_to_the_end():
    pygame.init()
    screen = pygame.display.set_mode((800, 600))
    for mod in all_games():
        for win in (True, False):
            with FastForward():
                assert mod.play(screen, win) is True, f"{mod.__name__}: 끝까지 했는데 True 가 아님 (win={win})"
        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=pygame.K_ESCAPE))
        with FastForward():
            assert mod.play(screen, True) is False, f"{mod.__name__}: ESC 누르면 False 여야 함"


def test_prize_odds():
    s = store.Store(":memory:")
    n = 100_000
    got = Counter(s.draw() for _ in range(n))
    for p in store.PRIZES:
        assert abs(got[p.name] / n * 100 - p.pct) < 1, f"{p.name}: {got[p.name] / n * 100:.1f}% (기대 {p.pct}%)"


def test_coupon_lifecycle():
    s = store.Store(":memory:")
    assert s.record("g", store.LOSE) is None
    code = s.record("g", "500원 할인")
    assert len(code) == 6
    assert s.redeem(code.lower())[0] == "ok"       # 소문자로 쳐도 됨
    assert s.redeem(code)[0] == "used"             # 두 번은 안 됨
    assert s.redeem("ZZZZZZ")[0] == "none"
    st = s.stats()
    assert st["total"] == 2 and dict((p.name, (n, used)) for p, n, used in st["prizes"])["500원 할인"] == (1, 1)


def test_cap_falls_back_to_lose():
    s = store.Store(":memory:")
    old = store.PRIZES
    store.PRIZES = [store.Prize("한정", 100, cap=2)]
    try:
        for _ in range(2):
            s.record("g", s.draw())
        assert s.draw() == store.LOSE  # 수량 다 나가면 꽝
    finally:
        store.PRIZES = old


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
