"""레전드 룰렛: 스페이스/터치 한 번 → 룰렛이 돌다가 멈출 듯… 하는 순간 등급이 터진다!
RARE! → EPIC!! → LEGENDARY!!! → CRITICAL!!!! 등급이 오를 때마다 화면 색이 바뀌고 더 빨리 돈다.
등급은 런처가 뽑은 경품 그대로 (확률 낮은 경품일수록 높은 등급). 칸 넓이도 실제 확률과 같음.
그래픽은 전부 코드로 그림 (에셋 파일 없음)."""
import colorsys
import math
import random
from bisect import bisect_right

import pygame

from core import sfx, ui
from core.store import LOSE, PRIZES  # 읽기 전용 (칸 이름/넓이 표시용)

NAME = "레전드 룰렛"
TAGLINE = "돌려라! 등급이 터진다!"
COLOR = (150, 60, 220)

W, H = ui.W, ui.H
CX, CY, R = 300, 322, 188
SPIN_MS, SLOW_MS, BOOST_MS = 1700, 1150, 1250
FINAL_MIN_S = 3.4       # 마지막 감속 최소 시간
LAND_MS = 2800

TIERS = [  # 등급 0 = 꽝(기본 화면)
    {"name": "", "kor": "", "c": (120, 132, 180), "bg": ((8, 10, 34), (36, 22, 78))},
    {"name": "RARE!", "kor": "레어", "c": (80, 180, 255), "bg": ((4, 26, 92), (22, 104, 214))},
    {"name": "EPIC!!", "kor": "에픽", "c": (198, 112, 255), "bg": ((46, 6, 98), (152, 50, 214))},
    {"name": "LEGENDARY!!!", "kor": "전설", "c": (255, 198, 50), "bg": ((104, 36, 0), (238, 150, 22))},
    {"name": "CRITICAL!!!!", "kor": "크리티컬", "c": (255, 72, 96), "bg": ((116, 0, 22), (255, 92, 56))},
]
SLICE = [((46, 50, 82), (36, 40, 68)), ((36, 118, 232),) * 2, ((150, 68, 232),) * 2, ((246, 160, 28),) * 2, ((255, 56, 92),) * 2]
TOP = len(TIERS) - 1


def ranks():
    """경품 이름 → 등급. 꽝 0, 나머지는 확률 높은 순서대로 1, 2, 3…"""
    wins = sorted((p for p in PRIZES if p.name != LOSE), key=lambda p: -p.pct)
    out = {LOSE: 0}
    out.update((p.name, min(TOP, i)) for i, p in enumerate(wins, 1))
    return out


def build_slices():
    """[(이름, 등급, 시작각, 넓이)] — 넓이 합은 360, 경품별 넓이 합 = 확률."""
    rk = ranks()
    lose, other = [], []
    for p in PRIZES:
        n = max(1, round(p.pct / (10 if p.name == LOSE else 5)))
        (lose if p.name == LOSE else other).extend([(p.name, rk[p.name], p.pct * 3.6 / n)] * n)
    random.Random(3).shuffle(other)
    other.sort(key=lambda s: -(s[1] == max(rk.values())))  # 최고 등급 칸을 맨 앞에 → 바로 뒤에 꽝이 옴 (아깝다 연출용)
    seq, li = [], 0
    for i, s in enumerate(other):
        seq.append(s)
        while li < len(lose) and li < (i + 1) * len(lose) / len(other):
            seq.append(lose[li])
            li += 1
    seq += lose[li:]
    out, a = [], 0.0
    for name, rank, width in seq:
        out.append((name, rank, a, width))
        a += width
    return out


def polar(phi, r, cx=CX, cy=CY):
    """위쪽(포인터)에서 시계방향 phi 도, 반지름 r 인 점."""
    a = math.radians(phi)
    return (cx + r * math.sin(a), cy - r * math.cos(a))


def short_label(name):
    if name == LOSE:
        return "꽝"
    digits = "".join(ch for ch in name if ch.isdigit())
    return digits or "★"


# ---------- 그림 만들기 ----------

def make_wheel(slices):
    S = 3
    c = R * S
    surf = pygame.Surface((2 * c, 2 * c), pygame.SRCALPHA)
    for i, (name, rank, start, width) in enumerate(slices):
        steps = max(2, int(width / 2))
        pts = [(c, c)] + [polar(start + width * k / steps, c, c, c) for k in range(steps + 1)]
        pygame.draw.polygon(surf, SLICE[rank][i % 2], pts)
        if rank:  # 당첨 칸 안쪽 밝은 띠
            inner = [polar(start + width * k / steps, c * 0.93, c, c) for k in range(steps + 1)]
            inner += [polar(start + width * k / steps, c * 0.80, c, c) for k in range(steps, -1, -1)]
            pygame.draw.polygon(surf, tuple(min(255, v + 40) for v in SLICE[rank][0]), inner)
    shade = pygame.Surface((2 * c, 2 * c), pygame.SRCALPHA)  # 가운데는 밝게, 가장자리는 어둡게
    for r in range(c, 0, -4):
        t = r / c
        col = (0, 0, 0, int(110 * (t - 0.8) / 0.2)) if t > 0.8 else (255, 255, 255, int(46 * (1 - t / 0.8) ** 1.4))
        pygame.draw.circle(shade, col, (c, c), r)
    surf.blit(shade, (0, 0))
    for name, rank, start, width in slices:
        pygame.draw.line(surf, (255, 222, 130), polar(start, c * 0.15, c, c), polar(start, c, c, c), 2 * S)
        mid = start + width / 2
        label = short_label(name)
        if label == "★":
            ui.star(surf, polar(mid, c * 0.70, c, c), 9 * S * min(1.6, width / 7), (255, 240, 150), math.radians(mid) - math.pi / 2)
            ui.star(surf, polar(mid, c * 0.48, c, c), 5 * S, (255, 240, 150), math.radians(mid))
        else:
            arc = math.radians(width) * R * 0.66
            size = int(min(38 if rank == 0 else 27, arc * 0.72))
            color = (150, 158, 200) if rank == 0 else ui.WHITE
            t = pygame.transform.rotozoom(ui.render(label, size * S, color, shadow=False), 90 - mid, 1)
            surf.blit(t, t.get_rect(center=polar(mid, c * 0.64, c, c)))
    for name, rank, start, width in slices:  # 가장자리 핀
        p = polar(start, c * 0.955, c, c)
        pygame.draw.circle(surf, (140, 96, 20), p, 5.5 * S)
        pygame.draw.circle(surf, (255, 226, 130), p, 4 * S)
        pygame.draw.circle(surf, (255, 255, 235), (p[0] - S, p[1] - S), 1.5 * S)
    pygame.draw.circle(surf, (110, 76, 14), (c, c), c * 0.17)
    pygame.draw.circle(surf, (236, 186, 70), (c, c), c * 0.15)
    pygame.draw.circle(surf, (255, 232, 150), (c, c), c * 0.15, 2 * S)
    return pygame.transform.smoothscale(surf, (2 * R, 2 * R))


def make_frame():
    """안 도는 부분: 금테, 받침대, 바닥 빛."""
    s = pygame.Surface((W, H), pygame.SRCALPHA)
    floor = ui.glow(260, (255, 255, 255), 60)
    floor = pygame.transform.smoothscale(floor, (560, 90))
    s.blit(floor, floor.get_rect(center=(CX, 578)))
    base = [(CX - 46, CY + R - 6), (CX + 46, CY + R - 6), (CX + 120, 584), (CX - 120, 584)]
    pygame.draw.polygon(s, (22, 22, 42), base)
    pygame.draw.polygon(s, (214, 164, 56), base, 3)
    pygame.draw.rect(s, (214, 164, 56), (CX - 140, 578, 280, 12), border_radius=6)
    for i in range(22, 0, -1):  # 금속 느낌 테두리
        t = i / 22
        k = 0.5 + 0.5 * math.cos(t * math.pi * 2)
        col = (int(120 + 135 * k), int(82 + 124 * k), int(16 + 84 * k))
        pygame.draw.circle(s, col, (CX, CY), R + i)
    pygame.draw.circle(s, (0, 0, 0, 0), (CX, CY), R - 1)
    return s


def make_gloss():
    """휠 위에 얹는 유리 반사광 (안 돎)."""
    g = pygame.Surface((2 * R, 2 * R), pygame.SRCALPHA)
    pygame.draw.circle(g, (255, 255, 255, 30), (R, R), R - 4)
    pygame.draw.circle(g, (0, 0, 0, 0), (R + R * 0.12, R + R * 0.5), R * 1.12)
    return g


def make_vignette():
    v = pygame.Surface((W, H), pygame.SRCALPHA)
    for i in range(44):
        pygame.draw.rect(v, (0, 0, 0, 5), pygame.Rect(0, 0, W, H).inflate(-i * 7, -i * 6), 7, border_radius=40)
    return v


class Art:
    def __init__(self):
        self.slices = build_slices()
        self.starts = [s[2] for s in self.slices]
        self.wheel = make_wheel(self.slices)
        self.frame = make_frame()
        self.gloss = make_gloss()
        self.vignette = make_vignette()
        self.bgs = [ui.gradient((W, H), *t["bg"]).copy() for t in TIERS]
        rng = random.Random(9)
        self.stars = [(rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0.6, 2.2), rng.uniform(0, 6.28)) for _ in range(70)]
        rk = ranks()
        self.ladder = sorted(((r, n) for n, r in rk.items() if r), reverse=True)  # [(등급, 경품명)] 위에서부터


# ---------- 그리기 ----------

def draw_background(dst, art, now, level, prev_level, since_boom, omega):
    dst.blit(art.bgs[prev_level], (0, 0))
    if level != prev_level or since_boom < 400:
        top = art.bgs[level].copy()
        top.set_alpha(int(255 * ui.clamp(since_boom / 400)))
        dst.blit(top, (0, 0))
    else:
        dst.blit(art.bgs[level], (0, 0))
    accent = TIERS[level]["c"]
    if level == TOP:  # 크리티컬: 무지개로 물듦
        tint = pygame.Surface((W, H))
        tint.fill([int(v * 255) for v in colorsys.hsv_to_rgb((now / 900) % 1, 0.85, 1)])
        tint.set_alpha(58)
        dst.blit(tint, (0, 0))
    for x, y, r, ph in art.stars:
        tw = 0.5 + 0.5 * math.sin(now / 400 + ph)
        pygame.draw.circle(dst, [min(255, int(v * (0.5 + 0.5 * tw)) + 40) for v in accent], (x, (y + now * 0.01 * r) % H), r * (0.6 + 0.5 * tw))
    if level:
        ui.rays(dst, (CX, CY), 560, accent if level < TOP else ui.WHITE, now / (1400 - 220 * level), n=14, alpha=26 + 12 * level)
    g = ui.glow(R + 120, accent, 110 + 30 * level)
    dst.blit(g, g.get_rect(center=(CX, CY)))
    n = int(omega / 80) + level * 2  # 속도선
    for _ in range(n):
        a = random.uniform(0, 360)
        r0 = random.uniform(R + 40, 560)
        ln = random.uniform(20, 60 + omega / 8)
        col = [min(255, v + 70) for v in accent]
        pygame.draw.line(dst, col, polar(a, r0), polar(a, r0 + ln), 2)


def draw_wheel(dst, art, now, theta, omega, level, flap, bulbs_all):
    accent = TIERS[level]["c"]
    dst.blit(art.frame, (0, 0))
    if omega > 420:  # 잔상
        for k, alpha in ((2, 50), (1, 90)):
            ghost = pygame.transform.rotozoom(art.wheel, theta - omega * 0.014 * k, 1)
            ghost.set_alpha(alpha)
            dst.blit(ghost, ghost.get_rect(center=(CX, CY)))
    img = pygame.transform.rotozoom(art.wheel, theta, 1)
    dst.blit(img, img.get_rect(center=(CX, CY)))
    dst.blit(art.gloss, (CX - R, CY - R))
    nb = 28  # 테두리 전구
    step = int(now / max(40, 220 - omega / 5))
    for i in range(nb):
        on = bulbs_all or (i + step) % 4 == 0 or (level >= 2 and (i - step) % 7 == 0)
        p = polar(i * 360 / nb, R + 11)
        if on:
            g = ui.glow(15, accent if level else (255, 240, 180), 170)
            dst.blit(g, g.get_rect(center=p))
        pygame.draw.circle(dst, (255, 252, 230) if on else (120, 86, 30), p, 5)
    gem = [min(255, int(v * (0.85 + 0.15 * math.sin(now / 200)))) for v in accent]  # 가운데 보석
    pygame.draw.circle(dst, (60, 40, 8), (CX, CY), 17)
    pygame.draw.circle(dst, gem, (CX, CY), 14)
    pygame.draw.circle(dst, (255, 255, 255), (CX - 4, CY - 5), 4)
    # 포인터 (핀에 걸릴 때마다 튕김)
    piv = (CX, CY - R - 26)
    a = math.radians(flap)

    def rot(x, y):
        return (piv[0] + x * math.cos(a) - y * math.sin(a), piv[1] + x * math.sin(a) + y * math.cos(a))

    pygame.draw.polygon(dst, (120, 16, 30), [rot(-20, -8), rot(20, -8), rot(0, 46)])
    pygame.draw.polygon(dst, (255, 70, 90), [rot(-15, -6), rot(15, -6), rot(0, 38)])
    pygame.draw.polygon(dst, (255, 170, 180), [rot(-9, -4), rot(-2, -4), rot(-1, 22)])
    pygame.draw.circle(dst, (255, 222, 130), piv, 11)
    pygame.draw.circle(dst, (140, 96, 20), piv, 11, 3)


def draw_highlight(dst, slc, theta, now):
    _, rank, start, width = slc
    steps = max(2, int(width / 2))
    pts = [(CX, CY)] + [polar(start - theta + width * k / steps, R - 2) for k in range(steps + 1)]
    layer = pygame.Surface((W, H), pygame.SRCALPHA)
    pygame.draw.polygon(layer, (255, 255, 255, int(70 + 60 * math.sin(now / 90))), pts)
    pygame.draw.polygon(layer, (255, 255, 255, 255), pts[1:] + [pts[0]], 4)
    dst.blit(layer, (0, 0))


def draw_ladder(dst, art, now, level, boom_at):
    ui.text(dst, "등급", 18, (680, 132), ui.GRAY, shadow=False)
    for row, (rank, prize) in enumerate(art.ladder):
        t = TIERS[rank]
        r = pygame.Rect(590, 152 + row * 84, 180, 72)
        lit = rank <= level
        if lit:
            fresh = rank == level and now - boom_at < 500
            g = ui.glow(120, t["c"], 150 if fresh else 80)
            dst.blit(g, g.get_rect(center=r.center))
            pop = 1 + 0.12 * (1 - ui.clamp((now - boom_at) / 300)) if rank == level else 1
            rr = r.inflate(r.w * (pop - 1), r.h * (pop - 1))
            ui.panel(dst, rr, (*t["c"], 255), radius=16, border=(255, 255, 255, 230), width=3)
            ui.text(dst, t["name"].rstrip("!"), 22, (rr.centerx, rr.y + 23), ui.INK, shadow=False)
            ui.text(dst, prize, 17, (rr.centerx, rr.y + 50), ui.INK, shadow=False)
        else:
            ui.panel(dst, r, (10, 10, 26, 170), radius=16, border=(*t["c"], 120))
            ui.text(dst, t["name"].rstrip("!"), 20, (r.centerx, r.y + 23), tuple(v // 2 + 40 for v in t["c"]), shadow=False)
            ui.text(dst, prize, 15, (r.centerx, r.y + 50), (110, 114, 140), bold=False, shadow=False)


def make_bolt(a, b, rng=random):
    pts = [a]
    for i in range(1, 9):
        t = i / 9
        pts.append((ui.lerp(a[0], b[0], t) + rng.uniform(-34, 34), ui.lerp(a[1], b[1], t) + rng.uniform(-12, 12)))
    return pts + [b]


def draw_bolts(dst, bolts, color):
    for pts in bolts:
        pygame.draw.lines(dst, color, False, pts, 9)
        pygame.draw.lines(dst, (255, 255, 255), False, pts, 3)


# ---------- 게임 ----------

def play(screen, win: bool, prize: str = None) -> bool:
    clock = pygame.time.Clock()
    art = Art()
    rk = ranks()
    if prize in rk:
        rank = rk[prize]
    else:  # 경품 이름을 안 받았을 때(단독 실행): win 만 보고 등급을 확률대로 고름
        wins = [p for p in PRIZES if p.name != LOSE]
        rank = rk[random.choices(wins, [p.pct for p in wins])[0].name] if win else 0
    mine = [s for s in art.slices if s[1] == rank]
    near_miss = rank == 0 and random.random() < 0.45
    if near_miss:  # 최고 등급 칸을 아슬아슬하게 지나쳐서 꽝
        top_i = max(range(len(art.slices)), key=lambda i: art.slices[i][1])
        target = art.slices[(top_i + 1) % len(art.slices)]
        landing = target[2] + target[3] * random.uniform(0.05, 0.13)
    else:
        target = random.choice(mine)
        landing = target[2] + target[3] * random.uniform(0.28, 0.72)

    script = [("spin", SPIN_MS, 560)]
    for lv in range(1, rank + 1):
        script += [("slow", SLOW_MS, 44), ("boom", lv), ("spin", BOOST_MS, 560 + 170 * lv)]
    script.append(("final",))

    canvas = pygame.Surface((W, H))
    fx = ui.Particles()
    state, t_state = "ready", pygame.time.get_ticks()
    theta, omega = random.uniform(0, 360), 24.0
    level = prev_level = 0
    boom_at = shake_at = flash_at = -99999
    flap, last_slice, last_tick, last_heart = 0.0, -1, 0, 0
    bolts, bolts_at = [], 0
    final = None  # (시작각, 거리, 시간)
    riser_for = None
    last = t_state

    while True:
        now = pygame.time.get_ticks()
        dt = min(50, now - last) / 1000
        last = now
        el = now - t_state
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            go = (e.type == pygame.KEYDOWN and e.key in (pygame.K_SPACE, pygame.K_RETURN)) or \
                (e.type == pygame.MOUSEBUTTONDOWN and e.button == 1)
            if go and state == "ready" and el > 500:  # 0.5초: 메뉴에서 넘어온 연타 무시
                state, t_state, el = "run", now, 0
                sfx.play("go")

        # ----- 진행 -----
        if state == "ready":
            theta += omega * dt
        elif state == "run":
            step = script[0]
            if step[0] == "boom":
                prev_level, level = level, step[1]
                boom_at = shake_at = flash_at = now
                script.pop(0)
                t_state = now
                sfx.play("boom")
                sfx.play(f"tier{min(4, level)}")
                if level == TOP:
                    sfx.play("zap")
                c = TIERS[level]["c"]
                fx.burst((CX, CY), 70 + 30 * level, [c, ui.WHITE, tuple(min(255, v + 60) for v in c)], speed=14 + 2 * level,
                         life=70, size=(5, 11), shape="star" if level >= 3 else "rect")
            elif step[0] == "final":
                dist = (landing - theta) % 360
                while 3 * dist / max(omega, 60) < FINAL_MIN_S:
                    dist += 360
                final = (theta, dist, 3 * dist / max(omega, 60))
                state, t_state = "final", now
            else:
                kind, dur, target_omega = step
                omega += (target_omega - omega) * min(1, dt * (2.6 if kind == "slow" else 7))
                theta += omega * dt
                if kind == "slow":
                    if riser_for != len(script):  # 감속 시작할 때 한 번
                        riser_for = len(script)
                        sfx.play("riser", 0.7)
                    if now - last_heart > 430:
                        last_heart = now
                        sfx.play("heart")
                if el >= dur:
                    script.pop(0)
                    t_state = now
        elif state == "final":
            a0, dist, T = final
            t = ui.clamp(el / 1000 / T)
            theta = a0 + dist * (1 - (1 - t) ** 3)
            omega = 3 * dist / T * (1 - t) ** 2
            if omega < 90 and now - last_heart > 520 and t < 1:
                last_heart = now
                sfx.play("heart")
            if t >= 1:
                state, t_state = "land", now
                omega = 0
                if rank:
                    shake_at = flash_at = now
                    c = TIERS[rank]["c"]
                    fx.burst((CX, CY - 40), 120 + 40 * rank, [c, ui.GOLD, ui.WHITE], speed=15, life=90, size=(5, 12))
                    sfx.play("coin")
                    sfx.play("cheer", 0.8)
                else:
                    sfx.play("groan")
        elif state == "land" and el >= (LAND_MS if rank else 2300):
            return True

        idx = bisect_right(art.starts, theta % 360) - 1  # 포인터가 가리키는 칸
        if idx != last_slice:
            if last_slice != -1 and state != "ready":
                flap = -26
                if now - last_tick > 45:
                    last_tick = now
                    sfx.play("tick", 0.5)
            last_slice = idx
        flap += (0 - flap) * min(1, dt * 14)
        if level == TOP and state in ("run", "final") and now - bolts_at > 90:  # 번개
            bolts_at = now
            bolts = [make_bolt((random.uniform(0, W), -10), polar(random.uniform(0, 360), R + 16)) for _ in range(random.randint(1, 3))]
            if random.random() < 0.25:
                sfx.play("zap", 0.35)
        if level and state != "land" and random.random() < 0.3 + 0.15 * level:  # 불티
            fx.burst((random.uniform(0, W), H + 5), 1, [TIERS[level]["c"], ui.WHITE], speed=5, gravity=-0.03, life=110,
                     size=(3, 6), spread=(70, 110), shape="circle")

        # ----- 그리기 -----
        since = now - boom_at
        draw_background(canvas, art, now, level, prev_level, since, omega)
        if level == TOP and state != "land":
            draw_bolts(canvas, bolts, TIERS[TOP]["c"])
        bulbs_all = since < 500 and (since // 70) % 2 == 0 or (state == "land" and rank and (el // 160) % 2 == 0)
        draw_wheel(canvas, art, now, theta, omega, level, flap, bulbs_all)
        if state == "land":
            draw_highlight(canvas, target, theta, now)
        canvas.blit(art.vignette, (0, 0))
        slowing = state == "run" and script and script[0][0] == "slow"
        if slowing or (state == "final" and omega < 140):  # 긴장: 주변이 어두워짐
            dark = pygame.Surface((W, H))
            k = ui.clamp(el / 500) if slowing else ui.clamp((140 - omega) / 140)
            dark.set_alpha(int(70 * k * (0.75 + 0.25 * math.sin(now / 70))))
            canvas.blit(dark, (0, 0))
        fx.update_draw(canvas)
        draw_ladder(canvas, art, now, level, boom_at)

        ui.panel(canvas, (16, 14, 232, 58), (8, 8, 24, 190), radius=14, border=(*TIERS[level]["c"], 255))
        ui.text(canvas, "LEGEND ROULETTE", 22, (132, 43), TIERS[level]["c"] if level else ui.WHITE)
        if state == "ready":
            pulse = 0.5 + 0.5 * math.sin(now / 240)
            ui.pill(canvas, "SPACE 또는 터치  ·  룰렛 돌리기!", (CX, 560 + 3 * pulse), 24, bg=(255, 70, 110, int(190 + 60 * pulse)))
        elif slowing:
            ui.text(canvas, "멈추나…?!", 44, (CX, 558), ui.WHITE, outline=5, scale=1 + 0.06 * math.sin(now / 50))

        if level and since < 1300 and state != "land":  # 등급 터짐 배너
            t = TIERS[level]
            slam = 1 + 2.4 * (1 - ui.ease_out(since / 190))
            fade = int(255 * ui.clamp((1300 - since) / 250))
            size = 96 if len(t["name"]) < 10 else 78
            img = pygame.transform.rotozoom(ui.render(t["name"], size, t["c"] if level < TOP else ui.WHITE, outline=7), 5, slam)
            img.set_alpha(fade)
            canvas.blit(img, img.get_rect(center=(400, 270)))
            got = next(p for r, p in art.ladder if r == level)
            ui.text(canvas, f"{t['kor']} 등급!   {got} 확보", 32, (400, 356), ui.WHITE, outline=4, alpha=fade,
                    scale=ui.out_back((since - 120) / 250) or 0.01)
        if state == "land":  # 결과는 아래쪽 띠에 (멈춘 칸이 가려지지 않게)
            k = max(0.01, ui.out_back(el / 350))
            t = TIERS[rank]
            ui.panel(canvas, (20, 500, 760, 92), (6, 6, 20, 225), radius=22, border=(*t["c"], 255), width=4)
            if rank:
                ui.text(canvas, target[0], 50, (400, 532), ui.WHITE, outline=5, scale=k)
                ui.text(canvas, f"{t['kor']} 등급 당첨!", 24, (400, 572), t["c"], outline=3)
            else:
                ui.text(canvas, "아깝다…! 꽝" if near_miss else "꽝…", 50, (400, 532), (196, 204, 240), outline=5, scale=k)
                ui.text(canvas, "다음엔 등급이 터질지도?", 22, (400, 572), ui.WHITE, outline=3)

        # 화면 전체 효과: 줌 펀치, 흔들림, 번쩍
        punch = 1 + 0.07 * (1 - ui.ease_out((now - boom_at) / 260)) if now - boom_at < 260 else 1
        shake = max(0.0, 1 - (now - shake_at) / 320) * (6 + 3 * level)
        off = (random.uniform(-shake, shake), random.uniform(-shake, shake))
        if punch > 1.001:
            z = pygame.transform.rotozoom(canvas, 0, punch)
            screen.blit(z, z.get_rect(center=(W / 2 + off[0], H / 2 + off[1])))
        else:
            screen.blit(canvas, off)
        fl = now - flash_at
        if fl < 320:
            white = pygame.Surface((W, H))
            white.fill((255, 255, 255))
            white.set_alpha(int(230 * (1 - fl / 320) ** 2))
            screen.blit(white, (0, 0))
        pygame.display.flip()
        clock.tick(60)


def thumbnail():
    art = Art()
    s = pygame.Surface((W, H))
    draw_background(s, art, 0, 3, 3, 9999, 600)
    draw_wheel(s, art, 0, 40, 0, 3, 0, False)
    s.blit(art.vignette, (0, 0))
    return s.subsurface((CX - 240, CY - 170, 480, 300)).copy()
