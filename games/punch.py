"""펀치머신: 게이지에 맞춰 스페이스/터치 한 번 → 샌드백을 쾅! → 점수가 드르륵 올라간다.
멈출 듯… 하다가 등급 선(600 / 750 / 900 / 999)을 뚫을 때마다 RARE! → EPIC!! → LEGENDARY!!! → CRITICAL!!!!
크리티컬(최고 등급)은 999를 넘어 '측정 불가' — 점수판이 깨진다.
점수/등급은 런처가 뽑은 경품 그대로 (게이지 타이밍은 타격 연출 세기에만 반영).
그래픽은 전부 코드로 그림 (에셋 파일 없음)."""
import math
import random

import pygame

from core import sfx, ui
from core.store import LOSE, PRIZES  # 읽기 전용 (등급 표시용)
from core.store import rank as prize_rank

NAME = "펀치머신"
TAGLINE = "한 방에 점수 폭발!"
COLOR = (230, 60, 80)

W, H = ui.W, ui.H
TOP = ui.TOP_TIER
LINES = (0, 600, 750, 900, 999)          # 등급 선: 이 점수를 넘으면 그 등급
CAB = pygame.Rect(238, 56, 324, 520)     # 기계 몸통
SCORE = pygame.Rect(266, 128, 268, 112)  # 점수판
METER = pygame.Rect(266, 252, 268, 14)
MOUNT, BAG_REST, BAG_R = (400, 316), (400, 424), 58
GAUGE = pygame.Rect(118, 150, 34, 300)
HITSTOP_MS, PUNCH_MS = 110, 130


def ladder():
    """[(등급, 경품명)] 높은 등급부터."""
    return sorted(((min(TOP, prize_rank(p.name)), p.name) for p in PRIZES if p.name != LOSE), reverse=True)


def plan(tier, rng=random):
    """(최종 점수, 연출 단계 목록). 단계: ("climb", 목표, ms) / ("hold", ms) / ("boom", 등급)"""
    if tier == 0:
        final = rng.randint(LINES[1] - 14, LINES[1] - 2) if rng.random() < 0.45 else rng.randint(360, LINES[1] - 30)
        return final, [("climb", final, 2700)]
    final = LINES[TOP] if tier >= TOP else rng.randint(LINES[tier] + 8, LINES[tier + 1] - 20)
    steps = []
    for lv in range(1, tier + 1):
        steps += [("climb", LINES[lv] - rng.randint(3, 12), 2300 if lv == 1 else 1150), ("hold", 950), ("boom", lv)]
    return final, steps + [("climb", final, 1300)]


# ---------- 그림 만들기 ----------

def make_bg():
    rng = random.Random(4)
    bg = ui.gradient((W, H), (7, 7, 18), (24, 12, 40)).copy()
    for _ in range(9):  # 뒤쪽 벽의 흐릿한 네온 불빛
        c = rng.choice([(255, 60, 140), (60, 200, 255), (160, 90, 255), (255, 170, 40)])
        r = rng.randint(50, 120)
        g = ui.glow(r, c, rng.randint(40, 90))
        bg.blit(g, (rng.choice([rng.randint(-40, 200), rng.randint(560, 800)]) - r, rng.randint(20, 330) - r))
    floor = pygame.Surface((W, 150), pygame.SRCALPHA)
    floor.blit(ui.gradient((W, 150), (10, 8, 22), (3, 3, 8)), (0, 0))
    for x in range(-600, 1401, 100):  # 바닥 원근선
        pygame.draw.line(floor, (70, 200, 255, 46), (400 + (x - 400) * 0.25, 0), (x, 150), 2)
    for i in range(7):
        y = int(150 * (i / 7) ** 1.8)
        pygame.draw.line(floor, (70, 200, 255, 46), (0, y), (W, y), 1)
    bg.blit(floor, (0, 450))
    pygame.draw.line(bg, (90, 210, 255), (0, 450), (W, 450), 1)
    vig = pygame.Surface((W, H), pygame.SRCALPHA)
    for i in range(46):
        pygame.draw.rect(vig, (0, 0, 0, 5), pygame.Rect(0, 0, W, H).inflate(-i * 7, -i * 6), 7, border_radius=50)
    bg.blit(vig, (0, 0))
    return bg


def make_cabinet():
    s = pygame.Surface((W, H), pygame.SRCALPHA)
    sh = pygame.Surface((420, 60), pygame.SRCALPHA)
    pygame.draw.ellipse(sh, (0, 0, 0, 150), sh.get_rect())
    s.blit(ui.blur(sh, 4), (CAB.centerx - 210, CAB.bottom - 28))
    body = ui.gradient(CAB.size, (44, 46, 70), (14, 15, 26)).copy().convert_alpha()
    mask = pygame.Surface(CAB.size, pygame.SRCALPHA)
    pygame.draw.rect(mask, (255, 255, 255, 255), mask.get_rect(), border_radius=26)
    body.blit(mask, (0, 0), special_flags=pygame.BLEND_RGBA_MIN)
    s.blit(body, CAB)
    pygame.draw.rect(s, (86, 92, 128), CAB, 2, border_radius=26)
    pygame.draw.line(s, (130, 138, 180), (CAB.x + 30, CAB.y + 1), (CAB.right - 30, CAB.y + 1), 2)
    pygame.draw.rect(s, (6, 6, 12), SCORE.inflate(12, 12), border_radius=10)   # 점수판 창
    pygame.draw.rect(s, (70, 76, 108), SCORE.inflate(12, 12), 2, border_radius=10)
    pygame.draw.rect(s, (6, 6, 12), METER.inflate(6, 6), border_radius=6)
    recess = pygame.Rect(CAB.x + 26, 296, CAB.w - 52, 204)                    # 샌드백 들어가는 홈
    s.blit(ui.gradient(recess.size, (4, 4, 10), (20, 20, 34)), recess)
    pygame.draw.rect(s, (70, 76, 108), recess, 2, border_radius=4)
    for i in range(7):  # 아래 스피커 그릴
        pygame.draw.rect(s, (8, 8, 14), (CAB.x + 60, 516 + i * 7, CAB.w - 120, 3), border_radius=2)
    for x in (CAB.x + 34, CAB.right - 34):
        pygame.draw.circle(s, (120, 126, 160), (x, 536), 6)
        pygame.draw.circle(s, (40, 42, 60), (x, 536), 6, 2)
    return s


def make_bag():
    S = 3
    r = BAG_R * S
    s = pygame.Surface((r * 2 + 8 * S, r * 2 + 8 * S), pygame.SRCALPHA)
    c = (s.get_width() // 2, s.get_height() // 2)
    pygame.draw.circle(s, (70, 8, 16), c, r + 3 * S)
    for i in range(r, 0, -3):  # 가죽 느낌 명암
        t = i / r
        pygame.draw.circle(s, (int(236 - 120 * t ** 2), int(40 - 24 * t), int(52 - 28 * t)),
                           (c[0] - int((1 - t) * r * 0.3), c[1] - int((1 - t) * r * 0.34)), i)
    pygame.draw.circle(s, (255, 236, 236), c, int(r * 0.52), 3 * S)
    ui.star(s, c, r * 0.36, (255, 236, 236), -math.pi / 2)
    for a in range(0, 360, 20):  # 박음질
        p1 = (c[0] + r * 0.86 * math.cos(math.radians(a)), c[1] + r * 0.86 * math.sin(math.radians(a)))
        p2 = (c[0] + r * 0.86 * math.cos(math.radians(a + 9)), c[1] + r * 0.86 * math.sin(math.radians(a + 9)))
        pygame.draw.line(s, (255, 190, 190), p1, p2, S)
    hl = pygame.Surface(s.get_size(), pygame.SRCALPHA)
    pygame.draw.ellipse(hl, (255, 255, 255, 70), (c[0] - r * 0.62, c[1] - r * 0.74, r * 0.7, r * 0.42))
    s.blit(ui.blur(hl, 3), (0, 0))
    return pygame.transform.smoothscale(s, (s.get_width() // S, s.get_height() // S))


def make_glove():
    S = 3
    s = pygame.Surface((240 * S, 280 * S), pygame.SRCALPHA)

    def el(color, x, y, w, h):
        pygame.draw.ellipse(s, color, (x * S, y * S, w * S, h * S))

    def box(color, x, y, w, h, rad):
        pygame.draw.rect(s, color, (x * S, y * S, w * S, h * S), border_radius=rad * S)

    box((60, 6, 14), 62, 168, 120, 108, 18)      # 손목
    box((238, 240, 250), 66, 172, 112, 100, 16)
    box((200, 30, 44), 66, 206, 112, 22, 4)
    el((60, 6, 14), 16, 8, 208, 196)             # 주먹 외곽
    el((214, 30, 46), 20, 12, 200, 188)
    el((240, 62, 76), 30, 16, 150, 120)
    el((60, 6, 14), 150, 70, 78, 116)            # 엄지
    el((196, 24, 40), 154, 74, 70, 108)
    el((232, 54, 68), 160, 78, 44, 60)
    hl = pygame.Surface(s.get_size(), pygame.SRCALPHA)
    pygame.draw.ellipse(hl, (255, 255, 255, 90), (44 * S, 26 * S, 92 * S, 46 * S))
    s.blit(ui.blur(hl, 4), (0, 0))
    return pygame.transform.smoothscale(s, (240, 280))


def neon(rect, color, radius):
    """네온 테두리 + 번짐."""
    pad = 36
    s = pygame.Surface((rect.w + pad * 2, rect.h + pad * 2), pygame.SRCALPHA)
    pygame.draw.rect(s, (*color, 230), (pad, pad, rect.w, rect.h), 7, border_radius=radius)
    s = ui.blur(s, 7)
    pygame.draw.rect(s, tuple(min(255, v + 110) for v in color), (pad, pad, rect.w, rect.h), 2, border_radius=radius)
    return s, (rect.x - pad, rect.y - pad)


class Art:
    def __init__(self):
        self.bg, self.cabinet, self.bag, self.glove = make_bg(), make_cabinet(), make_bag(), make_glove()
        self.neon = [neon(CAB, ui.TIERS[lv]["c"] if lv else (90, 210, 255), 26) for lv in range(TOP + 1)]
        self.ladder = ladder()
        self.digits = {}

    def digit(self, ch, level):
        key = (ch, level)
        if key not in self.digits:
            c = ui.TIERS[level]["c"] if level else (255, 90, 70)
            self.digits[key] = ui.render(ch, 112, en=True, shadow=False, glow=c,
                                         metal=((255, 255, 255), tuple(min(255, v + 40) for v in c)))
        return self.digits[key]


# ---------- 그리기 ----------

def draw_score(dst, art, text3, level, jitter=0.0, cracked=False, now=0):
    pygame.draw.rect(dst, (16, 4, 8) if not level else tuple(v // 9 for v in ui.TIERS[level]["c"]), SCORE, border_radius=6)
    cell = SCORE.w / 3
    for i, ch in enumerate(text3):
        cx = SCORE.x + cell * (i + 0.5)
        ghost = art.digit("8", level).copy()  # 꺼진 LED 자국
        ghost.set_alpha(22)
        dst.blit(ghost, ghost.get_rect(center=(cx, SCORE.centery + 4)))
        img = art.digit(ch, level)
        dst.blit(img, img.get_rect(center=(cx + random.uniform(-jitter, jitter), SCORE.centery + 4 + random.uniform(-jitter, jitter))))
    for y in range(SCORE.y + 2, SCORE.bottom, 4):  # 주사선
        pygame.draw.line(dst, (0, 0, 0), (SCORE.x, y), (SCORE.right, y))
    if cracked:  # 깨진 점수판
        rng = random.Random(8)
        for _ in range(7):
            p = (SCORE.centerx + rng.uniform(-30, 30), SCORE.centery + rng.uniform(-14, 14))
            pts = [p]
            a = rng.uniform(0, 6.28)
            for _ in range(5):
                a += rng.uniform(-0.5, 0.5)
                p = (p[0] + 30 * math.cos(a), p[1] + 22 * math.sin(a))
                pts.append((max(SCORE.x, min(SCORE.right, p[0])), max(SCORE.y, min(SCORE.bottom, p[1]))))
            pygame.draw.lines(dst, (255, 255, 255), False, pts, 2)
        if (now // 60) % 3 == 0:
            flash = pygame.Surface(SCORE.size)
            flash.fill((255, 255, 255))
            flash.set_alpha(50)
            dst.blit(flash, SCORE)


def draw_meter(dst, value, level):
    frac = ui.clamp(value / LINES[TOP])
    c = ui.TIERS[level]["c"] if level else (255, 90, 70)
    pygame.draw.rect(dst, (26, 28, 44), METER, border_radius=5)
    if frac > 0.01:
        fill = pygame.Rect(METER.x, METER.y, METER.w * frac, METER.h)
        dst.blit(ui.gradient((max(1, fill.w), fill.h), tuple(min(255, v + 90) for v in c), c), fill)
        g = ui.glow(16, c, 220)
        dst.blit(g, g.get_rect(center=(fill.right, METER.centery)))
    for lv in range(1, TOP + 1):  # 등급 선
        x = METER.x + METER.w * LINES[lv] / LINES[TOP] - (2 if lv == TOP else 0)
        tc = ui.TIERS[lv]["c"]
        pygame.draw.line(dst, tc, (x, METER.y - 4), (x, METER.bottom + 4), 2)
        ui.text(dst, str(LINES[lv]), 13, (x, METER.bottom + 14), tc if value >= LINES[lv] else tuple(v // 2 for v in tc),
                en=True, shadow=False, anchor="midright" if lv == TOP else "center")


def draw_bag(dst, art, theta, squash=0.0):
    """theta: 뒤로 젖혀진 각도(도). 화면 안쪽으로 넘어가는 것처럼 위로 올라가며 납작해짐."""
    k = abs(math.sin(math.radians(theta)))
    cy = BAG_REST[1] - k * 84
    sx, sy = 1 - 0.12 * k + squash * 0.25, (1 - 0.5 * k) * (1 - squash * 0.3)
    pygame.draw.line(dst, (20, 20, 30), MOUNT, (BAG_REST[0], cy), 16)
    pygame.draw.line(dst, (150, 156, 190), (MOUNT[0] - 3, MOUNT[1]), (BAG_REST[0] - 3, cy), 4)
    pygame.draw.circle(dst, (150, 156, 190), MOUNT, 12)
    pygame.draw.circle(dst, (40, 42, 60), MOUNT, 12, 3)
    img = pygame.transform.smoothscale(art.bag, (int(art.bag.get_width() * sx), max(8, int(art.bag.get_height() * sy))))
    dst.blit(img, img.get_rect(center=(BAG_REST[0], cy)))


def draw_ladder(dst, art, now, level, boom_at):
    for row, (rk, prize) in enumerate(art.ladder):
        t = ui.TIERS[rk]
        r = pygame.Rect(596, 150 + row * 78, 180, 66)
        lit = rk <= level
        if lit:
            g = ui.glow(110, t["c"], 150 if rk == level and now - boom_at < 500 else 70)
            dst.blit(g, g.get_rect(center=r.center))
        ui.cut_panel(dst, r, 10, (*[v // 3 for v in t["c"]], 240) if lit else (10, 12, 24, 215), accent=t["c"] if lit else None,
                     border=(*t["c"], 255 if lit else 90))
        ui.text(dst, f"{t['name'].rstrip('!')}  {LINES[rk]}+", 17, (r.x + 14, r.y + 21), t["c"] if lit else tuple(v // 2 + 30 for v in t["c"]),
                anchor="midleft", en=True, spacing=2, shadow=False)
        ui.text(dst, prize, 16, (r.x + 14, r.y + 45), ui.WHITE if lit else (110, 116, 144), anchor="midleft", shadow=False)


def draw_gauge(dst, now, g):
    ui.panel(dst, GAUGE.inflate(14, 14), (8, 8, 18, 220), radius=12)
    dst.blit(ui.gradient(GAUGE.size, (255, 70, 90), (60, 200, 255)), GAUGE)
    for i in range(1, 10):
        y = GAUGE.y + GAUGE.h * i / 10
        pygame.draw.line(dst, (8, 8, 18), (GAUGE.x, y), (GAUGE.right, y), 2)
    y = GAUGE.bottom - GAUGE.h * g
    pygame.draw.polygon(dst, ui.WHITE, [(GAUGE.x - 14, y - 9), (GAUGE.x - 14, y + 9), (GAUGE.x + 2, y)])
    pygame.draw.rect(dst, ui.WHITE, (GAUGE.x, y - 2, GAUGE.w, 4))
    ui.text(dst, "POWER", 18, (GAUGE.centerx, GAUGE.y - 26), ui.WHITE, en=True, spacing=4, shadow=False)


# ---------- 게임 ----------

def play(screen, win: bool, prize: str = None) -> bool:
    clock = pygame.time.Clock()
    art = Art()
    tier = (min(TOP, prize_rank(prize)) if prize else 1) if win else 0  # 경품 이름을 못 받으면 당첨=1등급
    final, steps = plan(tier)
    prize_name = prize or ("당첨!" if win else LOSE)
    show = ui.TierShow(tier, prize_name, banner=False)
    canvas = pygame.Surface((W, H))
    fx = ui.Particles()

    state, t_state = "ready", pygame.time.get_ticks()
    value, start_value, level = 0.0, 0.0, 0
    power = 0.5
    theta, omega, squash = 0.0, 0.0, 0.0     # 샌드백 젖힘 각도/각속도
    boom_at = shake_at = flash_at = -99999
    shake_amp = 0
    last_tick = last_heart = 0
    last = t_state
    maxed = False

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
                state, t_state, el = "punch", now, 0
                sfx.play("swing")

        # ----- 진행 -----
        if state == "ready":
            power = 0.5 + 0.5 * math.sin(now / 170)
        elif state == "punch" and el >= PUNCH_MS:  # 맞는 순간
            state, t_state, el = "hitstop", now, 0
            shake_at, flash_at, shake_amp = now, now, 10 + 10 * power
            sfx.play("kick")
            sfx.play("hit")
            fx.burst((BAG_REST[0], BAG_REST[1]), int(26 + 30 * power), [ui.WHITE, (255, 220, 120), (255, 120, 90)], speed=13 + 6 * power,
                     life=34, size=(7, 14), shape="star")
            omega, squash = 760 + 520 * power, 1.0
        elif state == "hitstop" and el >= HITSTOP_MS:
            state, t_state, el = "count", now, 0
        elif state == "count":
            step = steps[0]
            if step[0] == "climb":
                value = start_value + (step[1] - start_value) * ui.ease_out(el / step[2])
                if now - last_tick > 55 and el < step[2] * 0.92:
                    last_tick = now
                    sfx.play("tick", 0.45)
                if step[2] - el < 900 and len(steps) > 1 and now - last_heart > 430:
                    last_heart = now
                    sfx.play("heart")
                done = el >= step[2]
            elif step[0] == "hold":
                if el < 20:
                    sfx.play("riser", 0.7)
                if now - last_heart > 430:
                    last_heart = now
                    sfx.play("heart")
                done = el >= step[1]
            else:  # boom: 등급 선 돌파
                level = step[1]
                value = float(LINES[level])
                boom_at = shake_at = flash_at = now
                shake_amp = 8 + 4 * level
                omega += 500  # 샌드백도 다시 출렁
                sfx.play("boom")
                sfx.play(f"tier{min(4, level)}")
                c = ui.TIERS[level]["c"]
                fx.burst(SCORE.center, 50 + 24 * level, [c, ui.WHITE, tuple(min(255, v + 60) for v in c)], speed=13 + 2 * level,
                         life=60, size=(5, 11), shape="star" if level >= 3 else "rect")
                done = True
            if done:
                steps.pop(0)
                start_value, t_state, el = value, now, 0
                if not steps:
                    state = "land"
                    value = float(final)
                    if tier:
                        show.start(now)
                        shake_at, shake_amp = now, 12
                        sfx.play("coin")
                        if tier == TOP:
                            maxed = True
                            sfx.play("zap")
                    else:
                        sfx.play("groan")
        elif state == "land" and el >= (1400 + show.duration if tier else 2400):
            return True

        if state != "hitstop":  # 샌드백 스프링
            omega += (-theta * 60 - omega * 2.6) * dt
            theta = max(-30.0, min(86.0, theta + omega * dt))
            squash = max(0.0, squash - dt * 6)
        if maxed and random.random() < 0.5:  # 깨진 점수판에서 불꽃
            fx.burst((SCORE.centerx + random.uniform(-110, 110), SCORE.centery), 3, [(255, 240, 160), ui.WHITE, (255, 150, 60)], speed=8, life=30,
                     size=(3, 6), shape="circle")

        # ----- 그리기 -----
        since = now - boom_at
        holding = state == "count" and steps and steps[0][0] == "hold"
        canvas.blit(art.bg, (0, 0))
        floor_glow = ui.glow(180, ui.TIERS[level]["c"] if level else (90, 210, 255), 80)
        canvas.blit(pygame.transform.smoothscale(floor_glow, (460, 70)), (CAB.centerx - 230, CAB.bottom - 36))
        if level:
            ui.rays(canvas, CAB.center, 520, ui.TIERS[level]["c"], now / (1500 - 200 * level), n=14, alpha=14 + 8 * level)
        canvas.blit(art.cabinet, (0, 0))
        img, pos = art.neon[level]
        if since < 500 and (since // 70) % 2 == 0 or random.random() > 0.03:  # 가끔 깜빡이는 네온
            canvas.blit(img, pos)
        ui.text(canvas, "POWER PUNCH", 34, (CAB.centerx, 92), ui.WHITE, en=True, spacing=6, shadow=False,
                metal=((255, 255, 255), ui.TIERS[level]["c"] if level else (120, 220, 255)), glow=ui.TIERS[level]["c"] if level else (40, 150, 255))
        txt = "MAX" if maxed and (now // 140) % 4 else f"{int(value):03d}"
        draw_score(canvas, art, txt, level, jitter=2.5 if holding else 0, cracked=maxed, now=now)
        draw_meter(canvas, value, level)
        draw_bag(canvas, art, theta, squash)
        draw_ladder(canvas, art, now, level, boom_at)

        if state == "ready":
            draw_gauge(canvas, now, power)
            g = art.glove
            canvas.blit(g, g.get_rect(center=(566 + 6 * math.sin(now / 300), 548 + 8 * math.sin(now / 240))))
            pulse = 0.5 + 0.5 * math.sin(now / 240)
            ui.pill(canvas, "SPACE 또는 터치  ·  펀치!", (150, 560 + 3 * pulse), 22, bg=(200, 40, 70, int(190 + 60 * pulse)))
        elif state in ("punch", "hitstop"):
            k = 1.0 if state == "hitstop" else ui.ease_in_out(el / PUNCH_MS)
            g = pygame.transform.rotozoom(art.glove, 18 * k, ui.lerp(1.0, 0.62, k))
            canvas.blit(g, g.get_rect(center=(ui.lerp(566, BAG_REST[0] + 30, k), ui.lerp(548, BAG_REST[1] + 40, k))))
        elif state == "count" and el < 220 and len(steps) and start_value == 0:  # 주먹 빠지는 중
            k = el / 220
            g = pygame.transform.rotozoom(art.glove, 18 * (1 - k), ui.lerp(0.62, 1.0, k))
            g.set_alpha(int(255 * (1 - k)))
            canvas.blit(g, g.get_rect(center=(ui.lerp(BAG_REST[0] + 30, 620, k), ui.lerp(BAG_REST[1] + 40, 640, k))))

        if holding:  # 긴장: 어두워지고 "멈추나"
            dark = pygame.Surface((W, H))
            dark.set_alpha(int(70 * ui.clamp(el / 400) * (0.75 + 0.25 * math.sin(now / 70))))
            canvas.blit(dark, (0, 0))
            ui.text(canvas, "멈추나…?!", 40, (120, 300), ui.WHITE, outline=3, scale=1 + 0.06 * math.sin(now / 50))
        fx.update_draw(canvas)
        show.draw(canvas, now)
        if state != "land":
            ui.tier_banner(canvas, level, next((p for r, p in art.ladder if r == level), "") + " 확보", since, center=(400, 350))
        else:  # 결과 띠
            t = ui.TIERS[tier]
            k = max(0.01, ui.out_back(el / 350))
            ui.cut_panel(canvas, (20, 500, 760, 90), 16, (6, 6, 18, 235), border=(*t["c"], 255), accent=t["c"])
            pts = "측정 불가!" if tier == TOP else f"{final}점"
            if tier:
                ui.text(canvas, prize_name, 46, (400, 532), outline=2, glow=t["c"], metal=((255, 255, 255), tuple(min(255, v + 60) for v in t["c"])), scale=k)
                ui.text(canvas, f"{pts}   ·   {t['kor']} 등급 당첨!", 22, (400, 570), t["c"], shadow=False)
            else:
                near = LINES[1] - final <= 14
                ui.text(canvas, f"{'아깝다…! ' if near else ''}{final}점", 46, (400, 532), outline=2, metal=((226, 232, 250), (120, 132, 180)), scale=k)
                ui.text(canvas, f"{LINES[1]}점을 넘어야 당첨 · 꽝!", 22, (400, 570), ui.GRAY, shadow=False)

        ui.panel(canvas, (16, 14, 204, 54), (8, 8, 22, 200), radius=12, border=(*(ui.TIERS[level]["c"] if level else (90, 210, 255)), 255))
        ui.text(canvas, "PUNCH MACHINE", 22, (118, 42), ui.WHITE, en=True, spacing=3, shadow=False)

        # 화면 전체 효과: 줌 펀치, 흔들림, 번쩍
        hit_age = now - flash_at
        zoom = 1 + 0.06 * (1 - ui.ease_out(hit_age / 240)) if hit_age < 240 else 1
        shake = max(0.0, 1 - (now - shake_at) / 320) * shake_amp
        off = (random.uniform(-shake, shake), random.uniform(-shake, shake))
        if zoom > 1.001:
            z = pygame.transform.rotozoom(canvas, 0, zoom)
            screen.blit(z, z.get_rect(center=(W / 2 + off[0], H / 2 + off[1])))
        else:
            screen.blit(canvas, off)
        fl = now - flash_at
        if fl < 260:
            white = pygame.Surface((W, H))
            white.fill((255, 255, 255))
            white.set_alpha(int(200 * (1 - fl / 260) ** 2))
            screen.blit(white, (0, 0))
        pygame.display.flip()
        clock.tick(60)


def thumbnail():
    art = Art()
    s = pygame.Surface((W, H))
    s.blit(art.bg, (0, 0))
    s.blit(art.cabinet, (0, 0))
    img, pos = art.neon[3]
    s.blit(img, pos)
    ui.text(s, "POWER PUNCH", 34, (CAB.centerx, 92), ui.WHITE, en=True, spacing=6, shadow=False, metal=((255, 255, 255), ui.TIERS[3]["c"]),
            glow=ui.TIERS[3]["c"])
    draw_score(s, art, "934", 3)
    draw_meter(s, 934, 3)
    draw_bag(s, art, 30)
    g = pygame.transform.rotozoom(art.glove, 12, 0.8)
    s.blit(g, g.get_rect(center=(500, 500)))
    return s.subsurface((160, 60, 480, 300)).copy()
