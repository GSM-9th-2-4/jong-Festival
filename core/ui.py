"""공용 UI 키트. 게임에서 써도 됨: `from core import ui`
폰트/텍스트/패널/이징/파티클/배경/등급 연출. 전부 코드로 그림 (에셋 파일 없음).
스타일: 어두운 유리 패널 + 금속 그라데이션 글자 + 빛 번짐."""
import math
import random

import pygame

from core import sfx

W, H = 800, 600
FONT_NAMES = "applesdgothicneo,malgungothic,notosanscjkkr,nanumgothic,applegothic"
FONT_EN = "dincondensed,bahnschrift,avenirnextcondensed,impact,arial"  # 영문/숫자 전용 (좁고 각진 글꼴)

# 팔레트
WHITE, INK, GRAY = (240, 244, 255), (10, 12, 22), (132, 142, 170)
GOLD, PINK, MINT, SKY, RED = (240, 200, 110), (255, 95, 140), (80, 225, 180), (90, 200, 255), (240, 80, 90)
PARTY = [(255, 205, 60), PINK, MINT, SKY, (255, 255, 255)]
GOLD_TOP, GOLD_BOT = (255, 244, 200), (214, 150, 50)  # 금속 글자 그라데이션

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


def font(size, bold=True, en=False):
    key = (size, bold, en)
    if key not in _fonts:
        _fonts[key] = pygame.font.SysFont(FONT_EN if en else FONT_NAMES, size, bold=bold and not en)
    return _fonts[key]


def blur(surf, k=6):
    """싸고 빠른 흐림: 줄였다가 다시 늘림."""
    w, h = surf.get_size()
    small = pygame.transform.smoothscale(surf, (max(1, w // k), max(1, h // k)))
    return pygame.transform.smoothscale(small, (w, h))


def _plain(msg, size, color, bold, en, spacing):
    f = font(size, bold, en)
    if not spacing:
        return f.render(msg, True, color)
    glyphs = [f.render(ch, True, color) for ch in msg]  # 자간
    w = sum(g.get_width() for g in glyphs) + spacing * (len(glyphs) - 1)
    out = pygame.Surface((max(1, w), f.get_height()), pygame.SRCALPHA)
    x = 0
    for g in glyphs:
        out.blit(g, (x, 0))
        x += g.get_width() + spacing
    return out


def render(msg, size, color=WHITE, bold=True, outline=0, shadow=True, en=False, spacing=0, metal=None, glow=None):
    """텍스트 Surface (캐시됨).
    outline>0: 글자 뒤에 부드러운 어두운 후광(배경 위에서 잘 읽히게). shadow: 옅은 그림자.
    en: 영문 전용 글꼴. spacing: 자간(px). metal=(위색, 아래색): 금속 그라데이션. glow=색: 빛 번짐."""
    key = (msg, size, color, bold, outline, shadow, en, spacing, metal, glow)
    if key in _texts:
        return _texts[key]
    if len(_texts) > 600:  # 타이머처럼 계속 바뀌는 문자열 대비
        _texts.clear()
    base = _plain(msg, size, WHITE if metal else color, bold, en, spacing).convert_alpha()
    if metal:
        base.blit(gradient(base.get_size(), *metal), (0, 0), special_flags=pygame.BLEND_RGB_MULT)
    pad = max(outline * 3, 22 if glow else 0, 3 if shadow else 0)
    out = pygame.Surface((base.get_width() + pad * 2, base.get_height() + pad * 2), pygame.SRCALPHA)
    if glow:
        halo = pygame.Surface(out.get_size(), pygame.SRCALPHA)
        sil = base.copy()
        sil.fill((*glow, 255), special_flags=pygame.BLEND_RGBA_MULT)
        halo.blit(sil, (pad, pad))
        halo = blur(halo, 7)
        out.blit(halo, (0, 0))
        out.blit(halo, (0, 0))
    if outline:
        dark = pygame.Surface(out.get_size(), pygame.SRCALPHA)
        sil = base.copy()
        sil.fill((0, 0, 8, 255), special_flags=pygame.BLEND_RGBA_MULT)
        for dx in (-outline, 0, outline):
            for dy in (-outline, 0, outline):
                dark.blit(sil, (pad + dx, pad + dy + 1))
        dark = blur(dark, 3)
        out.blit(dark, (0, 0))
        out.blit(dark, (0, 0))
    elif shadow:
        sil = base.copy()
        sil.fill((0, 0, 0, 255), special_flags=pygame.BLEND_RGBA_MULT)
        sil.set_alpha(120)
        out.blit(sil, (pad + 1, pad + 2))
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


def panel(surf, rect, color=(10, 13, 26, 205), radius=14, border=(255, 255, 255, 38), width=1):
    """유리 패널: 반투명 어두운 바탕 + 얇은 밝은 테두리 + 위쪽 하이라이트."""
    rect = pygame.Rect(rect)
    s = pygame.Surface(rect.size, pygame.SRCALPHA)
    pygame.draw.rect(s, color, s.get_rect(), border_radius=radius)
    if border:
        pygame.draw.rect(s, border, s.get_rect(), width, border_radius=radius)
        if width == 1 and rect.w > radius * 2 + 8:
            pygame.draw.line(s, (255, 255, 255, 70), (radius, 0), (rect.w - radius, 0))
    surf.blit(s, rect)
    return rect


def cut_panel(surf, rect, cut=14, color=(10, 13, 26, 215), border=(255, 255, 255, 46), accent=None):
    """모서리를 깎은 패널 (왼쪽 위 / 오른쪽 아래). accent 색을 주면 위쪽에 색 띠."""
    rect = pygame.Rect(rect)
    w, h = rect.size
    pts = [(cut, 0), (w - 1, 0), (w - 1, h - 1 - cut), (w - 1 - cut, h - 1), (0, h - 1), (0, cut)]
    s = pygame.Surface(rect.size, pygame.SRCALPHA)
    pygame.draw.polygon(s, color, pts)
    pygame.draw.polygon(s, border, pts, 1)
    if accent:
        pygame.draw.line(s, (*accent[:3], 255), (cut, 0), (w - 1, 0), 2)
        pygame.draw.line(s, (*accent[:3], 255), (0, cut), (cut, 0), 2)
    surf.blit(s, rect)
    return rect


def pill(surf, msg, center, size=22, color=WHITE, bg=(8, 10, 22, 190)):
    img = render(msg, size, color, shadow=False)
    r = pygame.Rect(0, 0, img.get_width() + 48, img.get_height() + 16)
    r.center = center
    panel(surf, r, bg, radius=r.h // 2, border=(255, 255, 255, 60))
    surf.blit(img, img.get_rect(center=r.center))
    return r


def keycap(surf, label, pos, anchor="midleft"):
    """키 모양 아이콘. 그린 Rect 반환."""
    img = render(label, 15, WHITE, en=True, shadow=False, spacing=1)
    r = pygame.Rect(0, 0, max(26, img.get_width() + 14), 24)
    setattr(r, anchor, pos)
    pygame.draw.rect(surf, (36, 42, 64), r, border_radius=5)
    pygame.draw.rect(surf, (120, 130, 160), r, 1, border_radius=5)
    pygame.draw.line(surf, (70, 78, 104), (r.x + 3, r.bottom - 1), (r.right - 3, r.bottom - 1))
    surf.blit(img, img.get_rect(center=(r.centerx, r.centery + 1)))
    return r


def hints(surf, items, y=574):
    """아래쪽 조작 안내: [("ENTER", "시작"), ...] 를 가운데 정렬로."""
    parts = [(k, render(v, 15, GRAY, bold=False, shadow=False)) for k, v in items]
    widths = [max(26, render(k, 15, WHITE, en=True, shadow=False, spacing=1).get_width() + 14) + 8 + img.get_width() for k, img in parts]
    x = W / 2 - (sum(widths) + 28 * (len(parts) - 1)) / 2
    for (k, img), w in zip(parts, widths):
        r = keycap(surf, k, (x, y))
        surf.blit(img, img.get_rect(midleft=(r.right + 8, y)))
        x += w + 28


def gradient(size, top, bottom):
    key = (size, top, bottom)
    if key not in _grads:
        if len(_grads) > 200:
            _grads.clear()
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
        if len(_grads) > 200:
            _grads.clear()
        s = pygame.Surface((radius * 2, radius * 2), pygame.SRCALPHA)
        for i in range(radius, 0, -2):
            a = int(alpha * (1 - i / radius) ** 2)
            pygame.draw.circle(s, (*color, a), (radius, radius), i)
        _grads[key] = s
    return _grads[key]


def flare(surf, center, width, color=WHITE, alpha=200, thick=2):
    """가로로 길게 뻗는 렌즈 빛줄기."""
    key = ("flare", width, color, thick)
    if key not in _grads:
        s = pygame.Surface((width, thick * 9), pygame.SRCALPHA)
        for x in range(width):
            k = 1 - abs(x / (width - 1) * 2 - 1)
            a = int(255 * k ** 2.2)
            s.fill((*color, a // 5), (x, 0, 1, thick * 9))
            s.fill((*color, a // 2), (x, thick * 3, 1, thick * 3))
            s.fill((255, 255, 255, a), (x, thick * 4, 1, thick))
        _grads[key] = blur(s, 2)
    img = _grads[key]
    if alpha < 255:
        img = img.copy()
        img.set_alpha(alpha)
    surf.blit(img, img.get_rect(center=center))


def sheen(surf, rect, phase, alpha=46, mask=None):
    """rect 위를 비스듬히 지나가는 광택. phase 0~1 (범위 밖이면 안 그림).
    mask(rect 와 같은 크기의 Surface)를 주면 그 모양 안에서만 빛남 (글자 위 광택용)."""
    if not 0 <= phase <= 1:
        return
    rect = pygame.Rect(rect)
    s = pygame.Surface(rect.size, pygame.SRCALPHA)
    x = -rect.h + (rect.w + rect.h * 2) * phase
    for off, a in ((0, alpha), (46, alpha // 2)):
        pygame.draw.polygon(s, (255, 255, 255, a), [(x + off, 0), (x + off + 26, 0), (x + off + 26 - rect.h * 0.6, rect.h), (x + off - rect.h * 0.6, rect.h)])
    if mask:
        sil = mask.copy()
        sil.fill((255, 255, 255, 0), special_flags=pygame.BLEND_RGBA_MAX)  # 색은 흰색, 투명도만 남김
        s.blit(sil, (0, 0), special_flags=pygame.BLEND_RGBA_MULT)
    surf.blit(s, rect)


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


# ---------- 배경 (런처 화면용) ----------

class Backdrop:
    """어두운 우주빛 배경: 번지는 색 구름 + 떠다니는 먼지 + 비네팅. tint 색을 주면 그 색으로 물듦."""

    def __init__(self, seed=5):
        rng = random.Random(seed)
        self.base = gradient((W, H), (5, 7, 16), (16, 18, 38)).copy()
        dots = pygame.Surface((W, H), pygame.SRCALPHA)
        for y in range(12, H, 24):  # 은은한 점 격자
            for x in range(12 + (y // 24 % 2) * 12, W, 24):
                dots.set_at((x, y), (255, 255, 255, 26))
        self.base.blit(dots, (0, 0))
        self.clouds = {}
        self.rng_seed = seed
        self.dust = [(rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0.3, 1.0), rng.uniform(0, 6.28)) for _ in range(70)]
        self.vignette = pygame.Surface((W, H), pygame.SRCALPHA)
        for i in range(50):
            pygame.draw.rect(self.vignette, (0, 0, 0, 5), pygame.Rect(0, 0, W, H).inflate(-i * 7, -i * 6), 7, border_radius=60)

    def cloud(self, colors):
        key = tuple(colors)
        if key not in self.clouds:
            rng = random.Random(self.rng_seed)
            layers = []
            for n in range(2):
                small = pygame.Surface((250, 188), pygame.SRCALPHA)
                for _ in range(8):  # 가장자리가 부드러운 빛 덩어리를 겹쳐서 구름처럼
                    r = rng.randint(40, 78)
                    g = glow(r, rng.choice(colors), rng.randint(70, 120))
                    small.blit(g, (rng.randint(-20, 250) - r, rng.randint(-20, 188) - r))
                layers.append(pygame.transform.smoothscale(small, (1000, 750)))
            self.clouds[key] = layers
        return self.clouds[key]

    def draw(self, surf, now, tint=None):
        surf.blit(self.base, (0, 0))
        colors = [tint, tuple(v // 2 for v in tint), (40, 50, 130)] if tint else [(36, 70, 190), (110, 46, 170), (20, 120, 150), (150, 100, 30)]
        for n, layer in enumerate(self.cloud(colors)):
            ox = -100 + 90 * math.sin(now / (9000 + 4000 * n) + n * 2)
            oy = -75 + 60 * math.cos(now / (11000 + 3000 * n) + n)
            surf.blit(layer, (ox, oy))
        for x, y, depth, ph in self.dust:  # 깊이감 있는 먼지
            xx = (x + now * 0.008 * depth) % W
            yy = (y - now * 0.014 * depth) % H
            tw = 0.55 + 0.45 * math.sin(now / 600 + ph)
            c = int(90 + 150 * depth * tw)
            if depth > 0.8:
                g = glow(7, (200, 220, 255), int(120 * tw))
                surf.blit(g, (xx - 7, yy - 7))
            pygame.draw.circle(surf, (c, c, min(255, c + 20)), (xx, yy), 0.8 + depth)
        surf.blit(self.vignette, (0, 0))


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
    """등급 이름이 빛줄기와 함께 쾅 찍히는 배너. el = 터진 뒤 지난 ms."""
    if not rank or not 0 <= el < hold:
        return
    t = TIERS[min(rank, TOP_TIER)]
    c = t["c"]
    fade_k = clamp((hold - el) / 250)
    band = pygame.Surface((W, 150), pygame.SRCALPHA)  # 글자 뒤 어두운 띠
    for y in range(150):
        k = 1 - abs(y / 149 * 2 - 1)
        band.fill((4, 6, 14, int(200 * k ** 0.7 * fade_k * clamp(el / 120))), (0, y, W, 1))
    surf.blit(band, (0, center[1] - 60))
    flare(surf, (center[0], center[1] - 58), int(760 * ease_out(el / 260)) + 2, c, int(255 * fade_k))
    flare(surf, (center[0], center[1] + 88), int(760 * ease_out(el / 260)) + 2, c, int(255 * fade_k))
    slam = 1 + 1.6 * (1 - ease_out(el / 170))
    size = 104 if len(t["name"]) < 10 else 88
    top = tuple(min(255, v + 150) for v in c) if rank < TOP_TIER else (255, 255, 255)
    img = render(t["name"], size, en=True, spacing=4, metal=(top, c), glow=c, shadow=False)
    img = pygame.transform.rotozoom(img, 0, slam)
    img.set_alpha(int(255 * fade_k))
    surf.blit(img, img.get_rect(center=(center[0], center[1] + 6)))
    text(surf, f"{t['kor']} 등급   ·   {prize}", 26, (center[0], center[1] + 62), WHITE, outline=2, alpha=int(255 * fade_k * clamp((el - 120) / 200)))


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
                    self.sparks.append([x, y, math.cos(a) * v, math.sin(a) * v, r[6] if i % 4 else (255, 255, 255), life, life])
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
            [c, tuple(min(255, v + 70) for v in c), (255, 255, 255), (255, 205, 60)]

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
            white.fill((255, 255, 255))
            white.set_alpha(int(210 * (1 - el / 300) ** 2))
            surf.blit(white, (0, 0))
