"""공용 UI 키트. 게임에서 써도 됨: `from core import ui`
폰트/텍스트/패널/이징/파티클/배경. 전부 코드로 그림 (에셋 파일 없음)."""
import math
import random

import pygame

W, H = 800, 600
FONT_NAMES = "applesdgothicneo,malgungothic,notosanscjkkr,nanumgothic,applegothic"

# 팔레트
WHITE, INK, GRAY = (255, 255, 255), (16, 14, 30), (165, 170, 195)
GOLD, PINK, MINT, SKY, RED = (255, 205, 60), (255, 95, 140), (80, 225, 180), (90, 190, 255), (240, 80, 80)
PARTY = [GOLD, PINK, MINT, SKY, WHITE]

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
