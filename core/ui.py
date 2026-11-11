"""공용 UI 키트. 게임에서 써도 됨: `from core import ui`
폰트/텍스트/패널/이징/파티클/배경. 전부 코드로 그림 (에셋 파일 없음)."""
import math
import random

import pygame

from core import sfx

W, H = 800, 600
FONT_NAMES = "applesdgothicneo,malgungothic,notosanscjkkr,nanumgothic,applegothic"

# 팔레트
WHITE, INK, GRAY = (255, 255, 255), (16, 14, 30), (165, 170, 195)
GOLD, PINK, MINT, SKY, RED = (255, 205, 60), (255, 95, 140), (80, 225, 180), (90, 190, 255), (240, 80, 80)
PARTY = [GOLD, PINK, MINT, SKY, WHITE]

# 당첨 등급 (0 = 꽝). 등급 번호는 core.store.rank(경품이름) 으로 구함
TIERS = [
    {"name": "", "kor": "", "c": (120, 132, 180)},
    {"name": "RARE!", "kor": "레어", "c": (80, 180, 255)},
    {"name": "EPIC!!", "kor": "에픽", "c": (198, 112, 255)},
    {"name": "LEGENDARY!!!", "kor": "전설", "c": (255, 198, 50)},
    {"name": "CRITICAL!!!!", "kor": "크리티컬", "c": (255, 72, 96)},
]
TOP_TIER = len(TIERS) - 1

_fonts, _texts, _grads = {}, {}, {}


def font(size, bold=True):
    key = (size, bold)
    if key not in _fonts:
        _fonts[key] = pygame.font.SysFont(FONT_NAMES, size, bold=bold)
    return _fonts[key]


def render(msg, size, color=WHITE, bold=True, outline=0, shadow=True):
    """텍스트 Surface (캐시됨). outline>0 이면 검은 외곽선, 아니면 옅은 그림자."""
    key = (msg, size, color, bold, outline, shadow)
    if key in _texts:
        return _texts[key]
    if len(_texts) > 500:  # 타이머처럼 계속 바뀌는 문자열 대비
        _texts.clear()
    f = font(size, bold)
    base = f.render(msg, True, color)
    pad = outline or (2 if shadow else 0)
    out = pygame.Surface((base.get_width() + pad * 2, base.get_height() + pad * 2), pygame.SRCALPHA)
    if outline:
        black = f.render(msg, True, INK)
        for dx in (-outline, 0, outline):
            for dy in (-outline, 0, outline):
                out.blit(black, (pad + dx, pad + dy))
    elif shadow:
        dark = f.render(msg, True, (0, 0, 0))
        dark.set_alpha(110)
        out.blit(dark, (pad + 2, pad + 2))
    out.blit(base, (pad, pad))
    _texts[key] = out
    return out


def text(surf, msg, size, pos, color=WHITE, anchor="center", scale=1.0, alpha=255, **kw):
    img = render(msg, size, color, **kw)
    if scale != 1.0:
        img = pygame.transform.rotozoom(img, 0, scale)
    if alpha < 255:
        img = img.copy()
        img.set_alpha(alpha)
    r = img.get_rect(**{anchor: pos})
    surf.blit(img, r)
    return r


def panel(surf, rect, color=(12, 12, 32, 205), radius=16, border=None, width=2):
    rect = pygame.Rect(rect)
    s = pygame.Surface(rect.size, pygame.SRCALPHA)
    pygame.draw.rect(s, color, s.get_rect(), border_radius=radius)
    if border:
        pygame.draw.rect(s, border, s.get_rect(), width, border_radius=radius)
    surf.blit(s, rect)
    return rect


def pill(surf, msg, center, size=22, color=WHITE, bg=(0, 0, 0, 165)):
    img = render(msg, size, color, shadow=False)
    r = pygame.Rect(0, 0, img.get_width() + 44, img.get_height() + 18)
    r.center = center
    panel(surf, r, bg, radius=r.h // 2)
    surf.blit(img, img.get_rect(center=r.center))
    return r


def gradient(size, top, bottom):
    key = (size, top, bottom)
    if key not in _grads:
        s = pygame.Surface(size)
        h = size[1]
        for y in range(h):
            t = y / max(1, h - 1)
            s.fill([round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)], (0, y, size[0], 1))
        _grads[key] = s
    return _grads[key]


def glow(radius, color, alpha=90):
    """부드러운 빛 번짐 원 (캐시)."""
    key = ("glow", radius, color, alpha)
    if key not in _grads:
        s = pygame.Surface((radius * 2, radius * 2), pygame.SRCALPHA)
        for i in range(radius, 0, -2):
            a = int(alpha * (1 - i / radius) ** 2)
            pygame.draw.circle(s, (*color, a), (radius, radius), i)
        _grads[key] = s
    return _grads[key]


# ---------- 이징 ----------

def clamp(t, lo=0.0, hi=1.0):
    return max(lo, min(hi, t))


def lerp(a, b, t):
    return a + (b - a) * t


def ease_out(t):
    t = clamp(t)
    return 1 - (1 - t) ** 3


def ease_in_out(t):
    t = clamp(t)
    return t * t * (3 - 2 * t)


def out_back(t, s=1.7):
    """살짝 넘쳤다가 돌아오는 '뿅' 느낌."""
    t = clamp(t) - 1
    return 1 + t * t * ((s + 1) * t + s)


# ---------- 파티클 ----------

class Particles:
    """색종이/불꽃. 매 프레임 update_draw(surf) 한 번."""

    def __init__(self):
        self.items = []

    def burst(self, pos, n=40, colors=PARTY, speed=7.0, gravity=0.28, life=70, size=(4, 8), spread=(0, 360), shape="rect"):
        for _ in range(n):
            a = math.radians(random.uniform(*spread))
            v = random.uniform(speed * 0.3, speed)
            self.items.append([pos[0], pos[1], math.cos(a) * v, -math.sin(a) * v, random.choice(colors),
                               random.randint(life // 2, life), life, random.randint(*size), gravity, shape,
                               random.uniform(0, 6.28)])

    def rain(self, n=3, colors=PARTY):
        """화면 위에서 떨어지는 색종이 (매 프레임 호출)."""
        for _ in range(n):
            self.items.append([random.uniform(0, W), -10, random.uniform(-1, 1), random.uniform(1.5, 4),
                               random.choice(colors), 220, 220, random.randint(4, 8), 0.02, "rect", random.uniform(0, 6.28)])

    def update_draw(self, surf):
        alive = []
        for p in self.items:
            p[0] += p[2]
            p[1] += p[3]
            p[3] += p[8]
            p[5] -= 1
            p[10] += 0.25
            if p[5] <= 0 or p[1] > H + 20:
                continue
            alive.append(p)
            s = p[7] * min(1.0, p[5] / 15)
            if p[9] == "circle":
                pygame.draw.circle(surf, p[4], (p[0], p[1]), max(1, s / 2))
            elif p[9] == "star":
                star(surf, (p[0], p[1]), s, p[4], p[10])
            else:  # 팔랑거리는 색종이
                w = max(1, s * abs(math.cos(p[10])))
                pygame.draw.rect(surf, p[4], (p[0] - w / 2, p[1] - s / 2, w, s))
        self.items = alive


def star(surf, pos, r, color, rot=0.0, points=5):
    pts = []
    for i in range(points * 2):
        a = rot + i * math.pi / points
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((pos[0] + rr * math.cos(a), pos[1] + rr * math.sin(a)))
    pygame.draw.polygon(surf, color, pts)


def rays(surf, center, radius, color, t, n=12, alpha=70):
    """뒤에서 돌아가는 빛줄기."""
    s = pygame.Surface((radius * 2, radius * 2), pygame.SRCALPHA)
    for i in range(n):
        a = t + i * 2 * math.pi / n
        w = math.pi / n * 0.55
        pts = [(radius, radius)] + [(radius + radius * math.cos(a + d), radius + radius * math.sin(a + d)) for d in (-w, w)]
        pygame.draw.polygon(s, (*color, alpha), pts)
    surf.blit(s, s.get_rect(center=center))


# ---------- 축제 배경 (런처 화면용) ----------

class Backdrop:
    def __init__(self, seed=5):
        rng = random.Random(seed)
        self.bokeh = [(rng.uniform(0, W), rng.uniform(0, H), rng.randint(20, 70), rng.choice(PARTY), rng.uniform(0.2, 1.0))
                      for _ in range(26)]
        self.flags = [rng.choice([GOLD, PINK, MINT, SKY]) for _ in range(40)]

    def draw(self, surf, now):
        surf.blit(gradient((W, H), (20, 14, 56), (78, 30, 96)), (0, 0))
        for x, y, r, c, sp in self.bokeh:
            yy = (y - now * 0.012 * sp) % (H + 140) - 70
            xx = x + 14 * math.sin(now / 1700 * sp + y)
            surf.blit(glow(r, c, 70), (xx - r, yy - r))
        for row, (y0, sag, n) in enumerate(((0, 46, 17), (-14, 30, 13))):  # 만국기 줄
            pts = [(i * W / (n - 1), y0 + sag * math.sin(math.pi * i / (n - 1)) + 18) for i in range(n)]
            pygame.draw.lines(surf, (230, 230, 240), False, pts, 2)
            for i in range(n - 1):
                (x1, y1), (x2, y2) = pts[i], pts[i + 1]
                sway = 3 * math.sin(now / 400 + i + row)
                tip = ((x1 + x2) / 2 + sway, (y1 + y2) / 2 + 30)
                pygame.draw.polygon(surf, self.flags[i + row * 20], [(x1 + 3, y1), (x2 - 3, y2), tip])


def fade(screen, clock, out=True, ms=220):
    """화면 전환용 짧은 페이드."""
    snap = screen.copy()
    veil = pygame.Surface(screen.get_size())
    t0 = pygame.time.get_ticks()
    while (el := pygame.time.get_ticks() - t0) < ms:
        pygame.event.pump()
        k = el / ms
        veil.set_alpha(int(255 * (k if out else 1 - k)))
        screen.blit(snap, (0, 0))
        screen.blit(veil, (0, 0))
        pygame.display.flip()
        clock.tick(60)


# ---------- 등급 축하 연출 (세 게임 공용) ----------

def tier_banner(surf, rank, prize, el, center=(400, 270), hold=1300):
    """'EPIC!!' 이 쾅 찍히는 배너. el = 터진 뒤 지난 ms."""
    if not rank or not 0 <= el < hold:
        return
    t = TIERS[min(rank, TOP_TIER)]
    slam = 1 + 2.4 * (1 - ease_out(el / 190))
    fade_a = int(255 * clamp((hold - el) / 250))
    size = 96 if len(t["name"]) < 10 else 78
    img = pygame.transform.rotozoom(render(t["name"], size, t["c"] if rank < TOP_TIER else WHITE, outline=7), 5, slam)
    img.set_alpha(fade_a)
    surf.blit(img, img.get_rect(center=center))
    text(surf, f"{t['kor']} 등급!   {prize}", 32, (center[0], center[1] + 86), WHITE, outline=4, alpha=fade_a,
         scale=max(0.01, out_back((el - 120) / 250)))


class Fireworks:
    """폭죽. launch() 로 쏘고 매 프레임 update_draw(surf) — 이번 프레임에 터진 개수를 돌려줌."""

    def __init__(self):
        self.rockets, self.sparks, self.blasts = [], [], []

    def launch(self, n=1, colors=PARTY, area=(70, W - 70, 50, 250)):
        for _ in range(n):
            x, y = random.uniform(area[0], area[1]), random.uniform(area[2], area[3])
            self.rockets.append([x + random.uniform(-60, 60), H + 10, x, y, 0, random.randint(22, 34), random.choice(colors)])

    def update_draw(self, surf):
        popped = 0
        for r in self.rockets:
            r[4] += 1
            k = ease_out(r[4] / r[5])
            x, y = lerp(r[0], r[2], k), lerp(r[1], r[3], k)
            k0 = ease_out(max(0, r[4] - 3) / r[5])
            pygame.draw.line(surf, (255, 236, 190), (lerp(r[0], r[2], k0), lerp(r[1], r[3], k0)), (x, y), 3)
            if r[4] >= r[5]:
                popped += 1
                self.blasts.append([x, y, 0, r[6]])
                n = random.randint(38, 56)
                speed = random.uniform(4.5, 7.5)
                for i in range(n):
                    a = 2 * math.pi * i / n + random.uniform(-0.05, 0.05)
                    v = speed * random.uniform(0.82, 1.0) * (0.55 if i % 3 == 0 else 1)
                    life = random.randint(38, 60)
                    self.sparks.append([x, y, math.cos(a) * v, math.sin(a) * v, r[6] if i % 4 else WHITE, life, life])
        self.rockets = [r for r in self.rockets if r[4] < r[5]]
        for b in self.blasts:  # 터지는 순간 번쩍
            b[2] += 1
            g = glow(70, b[3], int(230 * (1 - b[2] / 8)))
            surf.blit(g, g.get_rect(center=(b[0], b[1])))
        self.blasts = [b for b in self.blasts if b[2] < 8]
        for p in self.sparks:
            ox, oy = p[0], p[1]
            p[0] += p[2]
            p[1] += p[3]
            p[2] *= 0.955
            p[3] = p[3] * 0.955 + 0.07
            p[5] -= 1
            f = p[5] / p[6]
            if f > 0.25 or p[5] % 2:  # 꺼지기 직전 반짝반짝
                pygame.draw.line(surf, [int(v * min(1.0, f * 1.6)) for v in p[4]], (ox, oy), (p[0], p[1]), 3 if f > 0.5 else 2)
        self.sparks = [p for p in self.sparks if p[5] > 0]
        return popped


class TierShow:
    """당첨 순간 축하 연출: 번쩍 + 등급 배너 + 폭죽. 등급이 높을수록 폭죽이 많고 오래 터짐.
    결과가 나오는 순간 start(now), 매 프레임 맨 위에 draw(surf, now). 꽝(rank 0)이면 아무것도 안 함."""
    RATE = (0, 0.035, 0.08, 0.16, 0.34)  # 프레임당 폭죽 발사 확률

    def __init__(self, rank, prize, banner=True, center=(400, 270)):
        self.rank = max(0, min(TOP_TIER, rank))
        self.prize, self.banner, self.center = prize, banner, center
        self.duration = 0 if not self.rank else 2400 + 800 * self.rank  # 게임이 이만큼 더 기다려주면 됨
        self.t0 = None
        self.fw = Fireworks()
        self.last_pop = 0
        c = TIERS[self.rank]["c"]
        self.colors = PARTY + [(255, 120, 60), (170, 255, 120)] if self.rank == TOP_TIER else \
            [c, tuple(min(255, v + 70) for v in c), WHITE, GOLD]

    @property
    def started(self):
        return self.t0 is not None

    def start(self, now):
        if not self.rank or self.started:
            return
        self.t0 = now
        sfx.play("boom")
        sfx.play(f"tier{self.rank}")
        if self.rank >= 3:
            sfx.play("cheer", 0.8)
        self.fw.launch(1 + 2 * self.rank, self.colors)

    def draw(self, surf, now):
        if not self.started:
            return
        el = now - self.t0
        veil = pygame.Surface(surf.get_size())  # 폭죽이 잘 보이게 살짝 어둡게
        veil.set_alpha(int((30 + 22 * self.rank) * clamp(el / 300) * clamp((self.duration - el) / 500)))
        surf.blit(veil, (0, 0))
        if el < self.duration - 900 and random.random() < self.RATE[self.rank]:
            self.fw.launch(1 if self.rank < TOP_TIER else random.randint(1, 3), self.colors)
        if self.fw.update_draw(surf) and now - self.last_pop > 110:
            self.last_pop = now
            sfx.play("firework", 0.55)
        if self.banner:
            tier_banner(surf, self.rank, self.prize, el, self.center)
        if el < 300:
            white = pygame.Surface(surf.get_size())
            white.fill(WHITE)
            white.set_alpha(int(210 * (1 - el / 300) ** 2))
            surf.blit(white, (0, 0))
