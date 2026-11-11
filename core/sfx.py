"""효과음. 전부 코드로 합성 (파일 없음). 게임에서: `from core import sfx; sfx.play("hit")`
오디오 장치가 없으면 조용히 아무것도 안 함."""
import math
import random
from array import array

import pygame

_cache = {}
_state = {"ok": None, "rate": 22050, "ch": 1}


def _ready():
    if _state["ok"] is None:
        try:
            if not pygame.mixer.get_init():
                pygame.mixer.init(22050, -16, 1, 512)
            rate, fmt, ch = pygame.mixer.get_init()
            _state.update(ok=(fmt == -16), rate=rate, ch=ch)
        except pygame.error:
            _state["ok"] = False
    return _state["ok"]


def _tone(freq, ms, vol=0.4, wave="sine", to=None, decay=4.0, vib=0.0):
    """freq→to 로 미끄러지는 음. decay 클수록 빨리 사라짐."""
    rate = _state["rate"]
    n = int(rate * ms / 1000)
    out, phase = array("h"), 0.0
    for i in range(n):
        t = i / n
        f = freq + ((to or freq) - freq) * t
        if vib:
            f *= 1 + 0.03 * math.sin(2 * math.pi * vib * i / rate)
        phase += f / rate
        x = phase % 1.0
        s = math.sin(2 * math.pi * x) if wave == "sine" else (1.0 if x < 0.5 else -1.0) if wave == "square" else 2 * x - 1
        env = min(1.0, i / (rate * 0.004)) * math.exp(-decay * t)
        out.append(int(32000 * vol * s * env))
    return out


def _noise(ms, vol=0.4, decay=4.0, smooth=0.0, swell=False):
    """smooth 0~1: 클수록 먹먹한(저음) 소리. swell: 커졌다 작아짐."""
    n = int(_state["rate"] * ms / 1000)
    out, prev = array("h"), 0.0
    for i in range(n):
        t = i / n
        prev = prev * smooth + random.uniform(-1, 1) * (1 - smooth)
        env = math.sin(math.pi * t) ** 0.6 if swell else math.exp(-decay * t)
        out.append(int(32000 * vol * prev * env))
    return out


def _mix(*parts):
    out = array("h", [0]) * max(len(p) for p in parts)
    for p in parts:
        for i, v in enumerate(p):
            out[i] = max(-32767, min(32767, out[i] + v))
    return out


def _seq(*parts):
    out = array("h")
    for p in parts:
        out.extend(p)
    return out


def _gap(ms):
    return array("h", [0]) * int(_state["rate"] * ms / 1000)


def _notes(freqs, ms, wave="square", vol=0.22, decay=3.0):
    return _seq(*[_tone(f, ms, vol, wave, decay=decay) if f else _gap(ms) for f in freqs])


C5, D5, E5, G5, A5, C6, E6, G6 = 523, 587, 659, 784, 880, 1047, 1319, 1568

RECIPES = {
    "move": lambda: _tone(660, 35, 0.2, "square"),
    "click": lambda: _seq(_tone(880, 40, 0.25, "square"), _tone(1320, 60, 0.25, "square")),
    "tick": lambda: _tone(1000, 30, 0.25, "sine", decay=6),
    "go": lambda: _tone(520, 260, 0.3, "square", to=1040, decay=2),
    "pop": lambda: _tone(280, 110, 0.35, "sine", to=760, decay=3),
    "swing": lambda: _noise(110, 0.22, decay=3, smooth=0.6),
    "hit": lambda: _mix(_noise(70, 0.5, decay=6), _tone(240, 160, 0.5, "square", to=70, decay=5)),
    "kick": lambda: _mix(_noise(50, 0.6, decay=7, smooth=0.3), _tone(140, 140, 0.6, "sine", to=50, decay=5)),
    "whistle": lambda: _mix(_tone(2150, 520, 0.22, "sine", decay=0.6, vib=28), _tone(2300, 520, 0.16, "sine", decay=0.6, vib=28)),
    "net": lambda: _noise(280, 0.3, decay=3, smooth=0.8),
    "cheer": lambda: _mix(_noise(2000, 0.5, smooth=0.92, swell=True), _noise(2000, 0.12, smooth=0.5, swell=True)),
    "groan": lambda: _mix(_tone(230, 800, 0.16, "saw", to=150, decay=1.5), _tone(180, 800, 0.16, "saw", to=120, decay=1.5),
                          _noise(800, 0.2, smooth=0.95, swell=True)),
    "coin": lambda: _seq(_tone(988, 70, 0.25, "square"), _tone(1319, 260, 0.25, "square", decay=5)),
    "drum": lambda: _seq(*[_noise(45, 0.12 + 0.3 * i / 32, decay=5, smooth=0.4) for i in range(32)]),
    "win": lambda: _seq(_notes([C5, E5, G5, C6], 100), _mix(_tone(C6, 500, 0.2, "square", decay=3), _tone(E6, 500, 0.15, "square", decay=3))),
    "jackpot": lambda: _seq(_notes([C5, C5, C5, E5, G5, E5, G5], 95), _notes([C6, 0, C6, E6, G6], 110),
                            _mix(_tone(C6, 900, 0.2, "square", decay=2), _tone(E6, 900, 0.15, "square", decay=2),
                                 _tone(G6, 900, 0.12, "square", decay=2))),
    "lose": lambda: _seq(_tone(392, 260, 0.25, "saw", to=370, decay=1.5), _tone(330, 260, 0.25, "saw", to=311, decay=1.5),
                         _tone(262, 620, 0.25, "saw", to=196, decay=2, vib=6)),
    "error": lambda: _tone(160, 220, 0.3, "square", decay=2),
    "boom": lambda: _mix(_noise(500, 0.7, decay=5, smooth=0.85), _tone(110, 600, 0.7, "sine", to=36, decay=4),
                         _noise(90, 0.5, decay=8)),
    "riser": lambda: _mix(_tone(180, 1100, 0.14, "saw", to=1500, decay=-1.2), _noise(1100, 0.1, decay=-1.5, smooth=0.5)),
    "heart": lambda: _seq(_tone(70, 110, 0.7, "sine", to=45, decay=3), _gap(60), _tone(60, 140, 0.55, "sine", to=40, decay=3)),
    "zap": lambda: _mix(_noise(260, 0.45, decay=6, smooth=0.1), _tone(1900, 260, 0.25, "square", to=160, decay=4)),
}
for _lv, _root in enumerate((C5, E5, G5, C6), 1):  # 등급 상승 징글: 등급이 높을수록 높은 음
    RECIPES[f"tier{_lv}"] = (lambda r=_root, n=_lv: _seq(
        _notes([r * 2 ** (k * 4 / 12) for k in range(n + 2)], 70, vol=0.24),
        _mix(_tone(r * 2, 520, 0.22, "square", decay=3), _tone(r * 3, 520, 0.14, "square", decay=3))))


def play(name, volume=1.0):
    """등록된 효과음 재생. 이름: move click tick go pop swing hit kick whistle net cheer groan coin drum win jackpot lose error
    boom riser heart zap tier1~tier4"""
    if not _ready():
        return None
    if name not in _cache:
        data = RECIPES[name]()
        if _state["ch"] == 2:  # 스테레오 믹서면 좌우 복제
            st = array("h")
            for v in data:
                st.append(v)
                st.append(v)
            data = st
        _cache[name] = pygame.mixer.Sound(buffer=data.tobytes())
    s = _cache[name]
    s.set_volume(volume)
    return s.play()


def stop(name):
    if name in _cache:
        _cache[name].stop()
