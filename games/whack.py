"""두더지 잡기: 15초 동안 망치로 두더지 잡기(점수는 재미용) → 마지막 한 방: 빛나는 구멍 3개 중 하나 고르기.
당첨이면 등급 두더지(레어 → 에픽 → 전설의 황금 → 크리티컬), 꽝이면 꽝 두더지. 등급이 높을수록 폭죽이 많이 터짐.
어느 구멍을 골라도 결과는 런처가 뽑은 그대로.
조작: 마우스/터치. 키보드는 숫자 1~9 (숫자패드 배치: 789 윗줄, 456 가운데, 123 아랫줄)."""
import math
import random

import pygame

from core import sfx, ui
from core.store import rank as prize_rank  # 읽기 전용

NAME = "두더지 잡기"
TAGLINE = "잡고 또 잡고, 마지막 한 방!"
COLOR = (90, 170, 80)

PLAY_MS = 15_000
INTRO_MS = 2400
SUSPENSE_MS = 900
REVEAL_MS = 1600  # 공개 후 기본 대기 (+ 등급별 폭죽 시간)

W, H = ui.W, ui.H
ROWS = ((305, 0.82), (410, 0.96), (520, 1.10))  # (구멍 y, 크기) 뒤→앞
HOLES = [(400 + (c - 1) * 215 * sc, y, sc) for y, sc in ROWS for c in range(3)]  # (cx, cy, scale)
PICK = (3, 4, 5)  # 마지막 한 방 후보: 가운데 줄
KEYS = {}
for d in range(1, 10):
    idx = (2 - (d - 1) // 3) * 3 + (d - 1) % 3
    KEYS[pygame.K_0 + d] = KEYS[pygame.K_KP1 + d - 1] = idx

KIND = ("dud", "rare", "epic", "gold", "crit")  # 등급 → 마지막에 나오는 두더지
TITLE = ("꽝 두더지…", "레어 두더지!", "에픽 두더지!!", "전설의 황금 두더지!!!", "크리티컬 두더지!!!!")

BODY = {"normal": ((146, 96, 62), (98, 60, 38), (214, 172, 128)),
        "hit": ((146, 96, 62), (98, 60, 38), (214, 172, 128)),
        "rare": ((84, 168, 250), (34, 96, 180), (190, 226, 255)),
        "epic": ((182, 112, 250), (104, 50, 176), (228, 200, 255)),
        "gold": ((250, 200, 50), (190, 130, 20), (255, 236, 150)),
        "crit": ((255, 92, 120), (176, 30, 60), (255, 206, 214)),
        "dud": ((132, 134, 158), (84, 86, 110), (190, 192, 210))}


# ---------- 그림 만들기 (play 시작 때 1번) ----------

def make_mole(kind):
    """3배 크기로 그린 뒤 줄여서 계단 현상 없앰. 기준 크기 120x150, 몸통은 아래로 이어짐."""
    S = 3
    s = pygame.Surface((120 * S, 150 * S), pygame.SRCALPHA)
    body, line, belly = BODY[kind]

    def el(color, x, y, w, h, width=0):
        pygame.draw.ellipse(s, color, (x * S, y * S, w * S, h * S), width * S)

    def circ(color, x, y, r):
        pygame.draw.circle(s, color, (x * S, y * S), r * S)

    def ln(color, a, b, w=2):
        pygame.draw.line(s, color, (a[0] * S, a[1] * S), (b[0] * S, b[1] * S), w * S)

    for x in (24, 96):  # 귀
        circ(line, x, 44, 13)
        circ(body, x, 44, 10)
        circ((240, 150, 160), x, 44, 5)
    el(line, 8, 28, 104, 190)       # 몸통 외곽
    el(body, 11, 31, 98, 190)
    el(belly, 32, 96, 56, 110)      # 배
    el(tuple(min(255, c + 26) for c in body), 26, 38, 36, 18)  # 머리 윤기
    for x in (27, 93):              # 볼터치
        circ(tuple((c + 2 * q) // 3 for c, q in zip(body, (255, 130, 140))), x, 84, 8)
    el(belly, 38, 72, 44, 30)       # 주둥이
    if kind == "hit":               # 맞은 얼굴: >< 눈, 벌린 입
        for x, d in ((42, 1), (78, -1)):
            ln((30, 20, 20), (x - 7 * d, 56), (x + 5 * d, 63), 3)
            ln((30, 20, 20), (x + 5 * d, 63), (x - 7 * d, 70), 3)
        el((90, 30, 40), 52, 88, 16, 14)
    elif kind == "dud":             # 시큰둥: 반쯤 감은 눈, 메롱
        for x in (42, 78):
            circ((30, 20, 20), x, 63, 7)
            pygame.draw.rect(s, body, ((x - 9) * S, 54 * S, 18 * S, 9 * S))
            ln((30, 20, 20), (x - 8, 63), (x + 8, 63), 2)
        pygame.draw.rect(s, (255, 120, 140), (54 * S, 92 * S, 12 * S, 16 * S), border_radius=6 * S)
        ln((200, 70, 100), (60, 94), (60, 104), 1)
    else:
        for x in (42, 78):
            circ((30, 20, 20), x, 62, 8)
            circ((255, 255, 255), x + 3, 59, 3)
        for x in (54, 60):          # 앞니
            pygame.draw.rect(s, (255, 255, 255), (x * S, 92 * S, 6 * S, 9 * S), border_radius=S)
            pygame.draw.rect(s, (170, 170, 170), (x * S, 92 * S, 6 * S, 9 * S), 1, border_radius=S)
    el((255, 120, 150), 50, 70, 20, 14)  # 코
    el((255, 200, 215), 54, 72, 7, 4)
    for sx, d in ((40, -1), (80, 1)):    # 수염
        for dy in (-4, 3):
            ln(line, (sx, 86), (sx + 20 * d, 86 + dy), 1)
    if kind in ("gold", "crit"):    # 왕관
        pts = [(34, 34), (30, 6), (46, 22), (60, 0), (74, 22), (90, 6), (86, 34)]
        pygame.draw.polygon(s, (255, 215, 0), [(x * S, y * S) for x, y in pts])
        pygame.draw.polygon(s, (180, 120, 0), [(x * S, y * S) for x, y in pts], 2 * S)
        for x, c in ((46, (255, 70, 90)), (60, (90, 200, 255)), (74, (255, 70, 90))):
            circ(c, x, 27, 4)
    if kind == "dud":               # 꽝 팻말
        pygame.draw.rect(s, (255, 255, 255), (38 * S, 112 * S, 44 * S, 30 * S), border_radius=5 * S)
        pygame.draw.rect(s, line, (38 * S, 112 * S, 44 * S, 30 * S), 2 * S, border_radius=5 * S)
        t = pygame.transform.smoothscale(ui.render("꽝", 60, ui.RED, shadow=False), (30 * S, 26 * S))
        s.blit(t, t.get_rect(center=(60 * S, 127 * S)))
    return s


def make_holes(sc):
    """(뒤쪽 그림, 앞쪽 그림): 두더지를 그 사이에 그리면 구멍에서 올라오는 것처럼 보임."""
    S = 3
    back = pygame.Surface((190 * S, 84 * S), pygame.SRCALPHA)
    pygame.draw.ellipse(back, (112, 74, 42), (0, 18 * S, 190 * S, 66 * S))
    pygame.draw.ellipse(back, (160, 112, 66), (0, 12 * S, 190 * S, 66 * S))
    pygame.draw.ellipse(back, (184, 136, 86), (22 * S, 16 * S, 146 * S, 40 * S))
    pygame.draw.ellipse(back, (34, 20, 14), (30 * S, 22 * S, 130 * S, 44 * S))
    pygame.draw.ellipse(back, (64, 38, 24), (38 * S, 22 * S, 114 * S, 26 * S))
    pygame.draw.ellipse(back, (34, 20, 14), (38 * S, 27 * S, 114 * S, 30 * S))
    front = back.copy()
    pygame.draw.ellipse(front, (0, 0, 0, 0), (30 * S, 22 * S, 130 * S, 44 * S))
    front.fill((0, 0, 0, 0), (0, 0, 190 * S, 44 * S))
    size = (int(190 * sc), int(84 * sc))
    return pygame.transform.smoothscale(back, size), pygame.transform.smoothscale(front, size)


def make_bg():
    rng = random.Random(11)
    bg = pygame.Surface((W, H))
    bg.blit(ui.gradient((W, 240), (96, 190, 255), (206, 238, 255)), (0, 0))
    sun = ui.glow(120, (255, 244, 180), 200)
    bg.blit(sun, (600, -20))
    pygame.draw.circle(bg, (255, 246, 190), (720, 100), 42)
    pygame.draw.ellipse(bg, (120, 196, 120), (-160, 150, 620, 260))  # 먼 언덕
    pygame.draw.ellipse(bg, (104, 184, 110), (360, 130, 640, 300))
    bg.blit(ui.gradient((W, H - 228), (126, 206, 96), (64, 150, 66)), (0, 228))
    for i in range(9):  # 잔디 줄무늬
        y0 = 228 + 372 * (i / 9) ** 1.3
        y1 = 228 + 372 * ((i + 1) / 9) ** 1.3
        if i % 2:
            band = pygame.Surface((W, int(y1 - y0) + 1), pygame.SRCALPHA)
            band.fill((255, 255, 255, 16))
            bg.blit(band, (0, int(y0)))
    for x in range(-10, W, 46):  # 울타리
        pygame.draw.rect(bg, (150, 104, 62), (x, 196, 14, 44), border_radius=5)
        pygame.draw.rect(bg, (178, 130, 82), (x + 2, 198, 5, 40), border_radius=3)
    for y in (206, 224):
        pygame.draw.rect(bg, (166, 118, 72), (0, y, W, 7))
    for _ in range(90):  # 풀/꽃
        x, y = rng.randint(0, W), rng.randint(240, H - 6)
        k = 0.6 + (y - 240) / 360 * 0.8
        if rng.random() < 0.3:
            c = rng.choice([(255, 255, 255), (255, 220, 90), (255, 150, 180)])
            for a in range(5):
                pygame.draw.circle(bg, c, (x + 4 * k * math.cos(a * 1.257), y + 4 * k * math.sin(a * 1.257)), 2.6 * k)
            pygame.draw.circle(bg, (255, 190, 40), (x, y), 2.2 * k)
        else:
            for dx in (-3, 0, 3):
                pygame.draw.line(bg, (52, 132, 58), (x + dx * k, y), (x + dx * 1.8 * k, y - 8 * k), 2)
    return bg


def make_hammer():
    s = pygame.Surface((220, 220), pygame.SRCALPHA)  # 손잡이 끝(110,110)이 회전 중심
    pygame.draw.rect(s, (120, 76, 40), (103, 34, 14, 82), border_radius=6)
    pygame.draw.rect(s, (168, 116, 66), (106, 36, 5, 78), border_radius=3)
    pygame.draw.rect(s, (150, 30, 40), (66, 6, 88, 50), border_radius=14)
    pygame.draw.rect(s, (232, 60, 70), (68, 8, 84, 42), border_radius=12)
    for x in (80, 132):
        pygame.draw.rect(s, (255, 214, 70), (x, 8, 9, 42))
    pygame.draw.rect(s, (246, 128, 134), (92, 12, 37, 8), border_radius=4)
    return s


def make_cloud(w):
    s = pygame.Surface((w, w // 2), pygame.SRCALPHA)
    for x, y, r in ((0.25, 0.62, 0.2), (0.45, 0.42, 0.26), (0.68, 0.55, 0.22), (0.5, 0.7, 0.3)):
        pygame.draw.ellipse(s, (255, 255, 255, 235), ((x - r) * w, (y - r * 0.6) * w / 2 * 1.2, r * 2 * w, r * w * 0.75))
    return s


class Art:
    def __init__(self):
        self.bg = make_bg()
        self.hammer = make_hammer()
        self.clouds = [make_cloud(w) for w in (190, 130, 160)]
        self.holes = [make_holes(sc) for _, sc in ROWS]
        self.moles = {}
        for kind in BODY:
            big = make_mole(kind)
            for r, (_, sc) in enumerate(ROWS):
                self.moles[kind, r] = pygame.transform.smoothscale(big, (int(120 * sc), int(150 * sc)))


# ---------- 그리기 ----------

def hole_blit(dst, art, i, which):
    cx, cy, sc = HOLES[i]
    img = art.holes[i // 3][which]
    dst.blit(img, (cx - 95 * sc, cy - 44 * sc))


def draw_mole(dst, art, i, kind, k, squash=1.0, dx=0.0):
    """구멍 i 에서 k(0~1)만큼 올라온 두더지."""
    cx, cy, sc = HOLES[i]
    img = art.moles[kind, i // 3]
    w, h = img.get_size()
    if squash != 1.0:
        img = pygame.transform.scale(img, (int(w * (2 - squash)), int(h * squash)))
        w, h = img.get_size()
    floor = int(cy + 20 * sc)
    old = dst.get_clip()
    dst.set_clip(pygame.Rect(0, 0, W, floor))
    dst.blit(img, (cx - w / 2 + dx, floor - h * k))
    dst.set_clip(old)


def mole_rect(i, k):
    cx, cy, sc = HOLES[i]
    h = 150 * sc * k
    return pygame.Rect(cx - 62 * sc, cy + 20 * sc - h - 6, 124 * sc, h + 14)


def draw_scene(dst, art, now, moles, special=None):
    """special: (구멍, 종류, k, dx) — 마지막 한 방 공개용."""
    dst.blit(art.bg, (0, 0))
    for n, c in enumerate(art.clouds):
        x = (now * (0.012 + 0.006 * n) + n * 330) % (W + 260) - 230
        dst.blit(c, (x, 26 + n * 44))
    for i in range(9):
        hole_blit(dst, art, i, 0)
        for m in moles:
            if m["hole"] == i:
                draw_mole(dst, art, i, "hit" if m["hit_at"] else "normal", m["k"], m["squash"])
        if special and special[0] == i:
            draw_mole(dst, art, i, special[1], special[2], dx=special[3])
        hole_blit(dst, art, i, 1)


def draw_hammer(dst, art, pos, swing):
    """swing 0(대기)~1(내려침)."""
    angle = -28 + 92 * swing
    img = pygame.transform.rotozoom(art.hammer, angle, 1.0)
    dst.blit(img, img.get_rect(center=(pos[0] + 64, pos[1] + 40)))


def draw_hud(dst, art, score, combo, left):
    ui.panel(dst, (16, 14, 150, 56), (20, 40, 24, 190), radius=16)
    icon = art.moles["normal", 0]
    dst.blit(pygame.transform.smoothscale(icon.subsurface((0, 0, icon.get_width(), icon.get_width())), (46, 46)), (24, 19))
    ui.text(dst, f"× {score}", 30, (82, 42), ui.WHITE, anchor="midleft")
    bar = pygame.Rect(250, 26, 300, 26)
    ui.panel(dst, bar.inflate(8, 8), (20, 40, 24, 190), radius=17)
    frac = ui.clamp(left / PLAY_MS)
    color = ui.RED if left < 5000 and (left // 250) % 2 else (255, 205, 60) if left < 5000 else (120, 230, 120)
    if frac > 0:
        pygame.draw.rect(dst, color, (bar.x, bar.y, max(bar.h, bar.w * frac), bar.h), border_radius=13)
    ui.text(dst, f"{max(0, left) / 1000:.1f}", 20, bar.center, ui.WHITE)
    if combo >= 2:
        ui.text(dst, f"{combo} COMBO!", 30, (770, 42), ui.GOLD, anchor="midright", outline=3,
                scale=1 + 0.08 * math.sin(pygame.time.get_ticks() / 80))


# ---------- 게임 ----------

def play(screen, win: bool, prize: str = None) -> bool:
    clock = pygame.time.Clock()
    art = Art()
    canvas = pygame.Surface((W, H))
    fx = ui.Particles()
    tier = (min(ui.TOP_TIER, prize_rank(prize)) if prize else 3) if win else 0  # 경품 이름을 못 받으면 황금 두더지
    show = ui.TierShow(tier, prize or "당첨!", banner=False)
    pygame.mouse.set_visible(False)
    try:
        return _run(screen, win, clock, art, canvas, fx, show)
    finally:
        pygame.mouse.set_visible(True)
        sfx.stop("drum")


def _run(screen, win, clock, art, canvas, fx, show):
    tier = show.rank
    t0 = pygame.time.get_ticks()
    phase, t_phase = "intro", t0
    score = combo = 0
    moles, floats = [], []          # floats: [글자, x, y, 시작시각, 색]
    next_spawn = 0
    cursor = pygame.mouse.get_pos()
    swing_at = shake_at = -9999
    picked, last_tick, last_drum, count_shown = None, 99, -9999, -1

    while True:
        now = pygame.time.get_ticks()
        el = now - t_phase
        hits = []  # 이번 프레임에 내려친 위치/구멍
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type == pygame.MOUSEMOTION:
                cursor = e.pos
            elif e.type == pygame.MOUSEBUTTONDOWN and e.button == 1:
                cursor = e.pos
                hits.append((e.pos, None))
            elif e.type == pygame.KEYDOWN and e.key in KEYS:
                cx, cy, sc = HOLES[KEYS[e.key]]
                cursor = (int(cx), int(cy - 40 * sc))
                hits.append((cursor, KEYS[e.key]))

        # ----- 진행 -----
        if phase == "intro":
            step = el // 600
            if step != count_shown and step < 4:
                count_shown = step
                sfx.play("go" if step == 3 else "tick")
            if el >= INTRO_MS:
                phase, t_phase, next_spawn = "play", now, now + 200
                el = 0
        left = PLAY_MS - el if phase == "play" else (PLAY_MS if phase == "intro" else 0)

        if phase == "play":
            prog = el / PLAY_MS
            if now >= next_spawn and len(moles) < (1 if prog < 0.3 else 2 if prog < 0.75 else 3):
                free = [i for i in range(9) if all(m["hole"] != i for m in moles)]
                moles.append({"hole": random.choice(free), "born": now, "up": ui.lerp(1000, 680, prog),
                              "hit_at": 0, "k": 0.0, "squash": 1.0})
                next_spawn = now + random.randint(int(ui.lerp(420, 180, prog)), int(ui.lerp(750, 380, prog)))
                sfx.play("pop", 0.5)
            for pos, key_hole in hits:
                swing_at = now
                target = None
                for m in sorted(moles, key=lambda m: -m["hole"]):  # 앞줄부터 판정
                    if not m["hit_at"] and m["k"] > 0.35 and (m["hole"] == key_hole or
                                                              (key_hole is None and mole_rect(m["hole"], m["k"]).collidepoint(pos))):
                        target = m
                        break
                if target:
                    target["hit_at"] = now
                    score += 1
                    combo += 1
                    shake_at = now
                    cx, cy, sc = HOLES[target["hole"]]
                    head = (cx, cy - 95 * sc)
                    fx.burst(head, 14, [ui.GOLD, ui.WHITE, (255, 240, 150)], speed=8, life=28, size=(6, 11), shape="star")
                    floats.append(["+1" if combo < 3 else f"+1  x{combo}", cx, head[1] - 20, now, ui.GOLD if combo >= 3 else ui.WHITE])
                    sfx.play("hit")
                else:
                    combo = 0
                    sfx.play("swing")
            if left <= 5000 and left // 1000 != last_tick:
                last_tick = left // 1000
                sfx.play("tick")
            if el >= PLAY_MS:
                phase, t_phase, moles = "pick", now, []
                sfx.play("go")
        elif phase == "pick":
            if now - last_drum > 1400:
                last_drum = now
                sfx.play("drum", 0.6)
            for pos, key_hole in hits:
                for i in PICK:
                    cx, cy, sc = HOLES[i]
                    if key_hole == i or (key_hole is None and pygame.Rect(cx - 110 * sc, cy - 120 * sc, 220 * sc, 190 * sc).collidepoint(pos)):
                        picked, phase, t_phase, swing_at, shake_at = i, "suspense", now, now, now
                        cursor = (int(cx), int(cy - 30 * sc))
                        sfx.play("hit")
                        sfx.play("drum")
                        break
                if picked is not None:
                    break
        elif phase == "suspense" and el >= SUSPENSE_MS:
            phase, t_phase = "reveal", now
            sfx.stop("drum")
            cx, cy, sc = HOLES[picked]
            if win:
                sfx.play("coin")
                show.start(now)
                fx.burst((cx, cy - 80 * sc), 70, [ui.GOLD, (255, 236, 150), ui.WHITE], speed=12, life=80, size=(6, 12), shape="circle")
                fx.burst((cx, cy - 80 * sc), 24, [ui.GOLD, ui.WHITE], speed=10, life=60, size=(8, 14), shape="star")
            else:
                sfx.play("groan")
        elif phase == "reveal" and el >= REVEAL_MS + show.duration:
            return True

        for m in moles:  # 두더지 높이/찌그러짐
            age = now - m["born"]
            if m["hit_at"]:
                h = now - m["hit_at"]
                m["squash"] = 0.72 + 0.28 * ui.clamp(h / 140)
                m["k"] = min(m["k"], 1 - ui.ease_in_out((h - 160) / 240))
            elif age < m["up"]:
                m["k"] = ui.out_back(age / 170)
            else:
                m["k"] = 1 - ui.ease_in_out((age - m["up"]) / 180)
        moles = [m for m in moles if not (m["k"] <= 0 and (m["hit_at"] or now - m["born"] > m["up"]))]

        # ----- 그리기 -----
        special = None
        if phase == "suspense":
            special = None
        elif phase == "reveal":
            special = (picked, KIND[tier], ui.out_back(el / 380), 0)
        draw_scene(canvas, art, now, moles, special)

        if phase in ("pick", "suspense", "reveal"):
            veil = pygame.Surface((W, H), pygame.SRCALPHA)
            veil.fill((10, 20, 40, 120 if phase != "reveal" or not win else 90))
            canvas.blit(veil, (0, 0))
            if phase == "reveal" and win:
                cx, cy, sc = HOLES[picked]
                ui.rays(canvas, (cx, cy - 70 * sc), 330, ui.TIERS[tier]["c"], now / 900, alpha=50)
            for i in PICK:  # 후보 구멍만 다시 밝게
                cx, cy, sc = HOLES[i]
                chosen = i == picked
                if phase == "pick" or chosen:
                    pulse = 0.5 + 0.5 * math.sin(now / 160 + i)
                    g = ui.glow(int(120 * sc), ui.GOLD, int(120 + 80 * pulse))
                    canvas.blit(g, g.get_rect(center=(cx, cy)))
                jit = 5 * math.sin(now / 18) if phase == "suspense" and chosen else 0
                canvas.blit(art.holes[1][0], (cx - 95 * sc + jit, cy - 44 * sc))
                if special and chosen:
                    draw_mole(canvas, art, i, special[1], special[2])
                canvas.blit(art.holes[1][1], (cx - 95 * sc + jit, cy - 44 * sc))
                if phase == "pick":
                    bob = 8 * math.sin(now / 170 + i * 1.3)
                    ui.text(canvas, "?", 76, (cx, cy - 92 + bob), ui.GOLD, outline=4)
                elif phase == "suspense" and chosen and (now // 50) % 2:
                    fx.burst((cx + random.uniform(-40, 40), cy), 2, [(150, 104, 62), (112, 74, 42)], speed=6, life=30,
                             size=(5, 9), spread=(40, 140), shape="circle")
        fx.update_draw(canvas)
        for f in floats:
            a = (now - f[3]) / 700
            ui.text(canvas, f[0], 30, (f[1], f[2] - 46 * ui.ease_out(a)), f[4], outline=3, alpha=int(255 * (1 - a ** 2)))
        floats = [f for f in floats if now - f[3] < 700]

        sw = now - swing_at
        swing = ui.clamp(sw / 60) if sw < 60 else 1 - ui.clamp((sw - 60) / 160)
        draw_hammer(canvas, art, cursor, swing)

        show.draw(canvas, now)
        shake = max(0.0, 1 - (now - shake_at) / 140) * 5
        screen.blit(canvas, (random.uniform(-shake, shake), random.uniform(-shake, shake)))

        if phase in ("intro", "play"):
            draw_hud(screen, art, score, combo, left)
        if phase == "intro":
            step = min(3, el // 600)
            k = (el % 600) / 600
            ui.text(screen, ("3", "2", "1", "시작!")[step], 150 if step < 3 else 110, (400, 290),
                    ui.GOLD if step == 3 else ui.WHITE, outline=6, scale=1.6 - 0.6 * ui.ease_out(k * 2.5))
            ui.pill(screen, "나오는 두더지를 망치로 쾅!  (마우스 · 터치 · 숫자키)", (400, 560))
        elif phase == "pick":
            ui.text(screen, "마지막 한 방!", 68, (400, 84), metal=(ui.GOLD_TOP, ui.GOLD_BOT), glow=(255, 140, 20), outline=3,
                    scale=max(0.01, ui.out_back(el / 300)))
            ui.text(screen, f"{score}마리 잡았어요 · 빛나는 구멍 하나를 골라 쾅!", 24, (400, 150), ui.WHITE)
        elif phase == "suspense":
            ui.text(screen, "두구두구두구…", 60, (400, 100), ui.WHITE, outline=5, scale=1 + 0.05 * math.sin(now / 40))
        elif phase == "reveal":
            if win:
                t = ui.TIERS[tier]
                ui.text(screen, TITLE[tier], 66 if tier < 3 else 56, (400, 92), outline=3, glow=t["c"],
                        metal=((255, 255, 255), tuple(min(255, v + 40) for v in t["c"])), scale=max(0.01, ui.out_back(el / 300)))
                ui.text(screen, f"{t['kor']} 등급!   {show.prize}", 32, (400, 164), ui.WHITE, outline=3)
            else:
                ui.text(screen, "꽝 두더지…", 76, (400, 96), outline=3, metal=((226, 232, 250), (120, 132, 180)),
                        scale=max(0.01, ui.out_back(el / 300)))
                ui.text(screen, "메롱~ 다음 기회에!", 30, (400, 168), ui.WHITE, outline=3)
        pygame.display.flip()
        clock.tick(60)


def thumbnail():
    art = Art()
    s = pygame.Surface((W, H))
    moles = [{"hole": 4, "hit_at": 0, "k": 1.0, "squash": 1.0}, {"hole": 0, "hit_at": 0, "k": 0.55, "squash": 1.0}]
    draw_scene(s, art, 0, moles)
    draw_hammer(s, art, (520, 300), 0.15)
    return s.subsurface((160, 190, 480, 300)).copy()
