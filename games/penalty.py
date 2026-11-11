"""페널티킥: 스페이스(또는 클릭/터치) 한 번 → 슛. 골/선방/빗나감은 런처가 넘겨준 win 대로 연출 (조준 없음).
골이면 경품 등급(레어~크리티컬)이 터지고, 등급이 높을수록 폭죽이 많이 터짐. 공 꼬리 색도 등급 색.
그래픽은 전부 코드로 그림 (에셋 파일 없음)."""
import math
import random

import pygame

from core import sfx, ui
from core.store import rank as prize_rank  # 읽기 전용

NAME = "페널티킥"
TAGLINE = "단 한 번의 슛!"
COLOR = (40, 140, 60)
FLY_MS = 550
SAVE_RATIO = 0.7  # 꽝일 때 키퍼 선방 비율 (나머지는 빗나감)

W, H = 800, 600
GOAL = pygame.Rect(220, 150, 360, 170)  # 골문 앞 프레임, bottom = 골라인
BACK = pygame.Rect(255, 168, 290, 140)  # 그물 뒤 프레임 (원근)
SPOT = (400, 520)
KEEPER_FEET_Y = 318
DIVES = {  # 막는 범위, 회전 방향
    "left": (pygame.Rect(220, 205, 170, 115), 1),
    "center": (pygame.Rect(345, 175, 110, 145), 0),
    "right": (pygame.Rect(410, 205, 170, 115), -1),
}


def pick_shot(win, rng=random):
    """(키퍼 다이브 방향, 슛 목표 x, y, 결과). 결과는 win 그대로."""
    dive = rng.choice(list(DIVES))
    hit = DIVES[dive][0]
    if win:  # 골대 안 + 키퍼 범위 밖
        while True:
            x, y = rng.uniform(GOAL.left + 20, GOAL.right - 20), rng.uniform(GOAL.top + 20, GOAL.bottom - 15)
            if not hit.collidepoint(x, y):
                return dive, x, y, "goal"
    if rng.random() < SAVE_RATIO:  # 키퍼 정면
        r = hit.inflate(-30, -30)
        return dive, rng.uniform(r.left, r.right), rng.uniform(r.top, r.bottom), "save"
    if rng.random() < 0.5:  # 크로스바 위
        return dive, rng.uniform(GOAL.left + 30, GOAL.right - 30), GOAL.top - rng.uniform(20, 40), "miss"
    side = rng.choice((-1, 1))
    x = GOAL.left - rng.uniform(20, 40) if side < 0 else GOAL.right + rng.uniform(20, 40)
    return dive, x, rng.uniform(GOAL.top + 30, GOAL.bottom - 20), "miss"


def lerp(a, b, t):
    return a + (b - a) * t


def ease(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 2


# ---------- 그림 만들기 (play 시작 때 1번) ----------

def make_bg():
    rng = random.Random(7)
    bg = pygame.Surface((W, H))
    for y in range(210):  # 밤하늘
        c = lerp(0, 1, y / 210)
        bg.fill((int(lerp(8, 30, c)), int(lerp(12, 38, c)), int(lerp(30, 70, c))), (0, y, W, 1))
    glow = pygame.Surface((W, H), pygame.SRCALPHA)
    for cx in (70, 730):  # 조명
        for r in range(160, 0, -8):
            pygame.draw.circle(glow, (255, 250, 220, 6), (cx, 10), r)
        pygame.draw.circle(glow, (255, 255, 240, 255), (cx, 10), 10)
    bg.blit(glow, (0, 0))
    crowd = [(220, 40, 60), (30, 90, 200), (240, 240, 240), (250, 200, 40), (40, 160, 90)]
    for i, y in enumerate(range(48, 186, 9)):  # 관중석
        bg.fill((30, 34, 52) if i % 2 else (38, 42, 62), (0, y, W, 9))
        for x in range(0, W, 6):
            c = rng.choice(crowd)
            k = rng.uniform(0.35, 0.8)
            pygame.draw.circle(bg, (int(c[0] * k), int(c[1] * k), int(c[2] * k)), (x + rng.randint(0, 3), y + 4), 3)
    bg.fill((14, 16, 26), (0, 186, W, 24))  # 광고판
    ad = ui.font(15)
    x = 0
    for i in range(20):
        s = ad.render(("FESTIVAL CUP", "할인 쿠폰 GET", "승부차기")[i % 3], True,
                      ((255, 150, 20), (90, 200, 255), (255, 255, 255))[i % 3])
        bg.blit(s, (x, 189))
        x += s.get_width() + 40
    for i in range(10):  # 잔디 줄무늬 (원근)
        y0 = 210 + 390 * (i / 10) ** 1.5
        y1 = 210 + 390 * ((i + 1) / 10) ** 1.5
        bg.fill((46, 128, 56) if i % 2 else (56, 146, 64), (0, int(y0), W, int(y1 - y0) + 1))
    lines = pygame.Surface((W, H), pygame.SRCALPHA)
    white = (255, 255, 255, 190)
    pygame.draw.line(lines, white, (0, GOAL.bottom), (W, GOAL.bottom), 3)
    pygame.draw.lines(lines, white, False, [(170, 320), (150, 362), (650, 362), (630, 320)], 3)
    pygame.draw.lines(lines, white, False, [(60, 320), (0, 450), (800, 450), (740, 320)], 3)
    pygame.draw.arc(lines, white, pygame.Rect(300, 410, 200, 80), math.pi + 0.55, 2 * math.pi - 0.55, 3)
    pygame.draw.circle(lines, white, (SPOT[0], SPOT[1] + 8), 5)
    pygame.draw.polygon(lines, (0, 0, 0, 60), [GOAL.bottomleft, GOAL.bottomright, BACK.bottomright, BACK.bottomleft])
    bg.blit(lines, (0, 0))
    vig = pygame.Surface((W, H), pygame.SRCALPHA)
    for i in range(30):  # 비네팅
        pygame.draw.rect(vig, (0, 0, 0, 4), pygame.Rect(0, 0, W, H).inflate(-i * 6, -i * 6), 6)
    bg.blit(vig, (0, 0))
    return bg


def make_keeper():
    s = pygame.Surface((90, 120), pygame.SRCALPHA)
    jersey, dark = (255, 140, 20), (25, 25, 35)
    pygame.draw.line(s, jersey, (30, 38), (8, 12), 10)  # 팔
    pygame.draw.line(s, jersey, (60, 38), (82, 12), 10)
    for p in ((8, 10), (82, 10)):  # 장갑
        pygame.draw.circle(s, (245, 245, 245), p, 8)
        pygame.draw.circle(s, (60, 200, 120), p, 8, 2)
    for x in (32, 48):  # 다리
        pygame.draw.rect(s, dark, (x, 82, 11, 30), border_radius=4)
        pygame.draw.rect(s, (10, 10, 10), (x - 2, 110, 15, 8), border_radius=3)
    pygame.draw.rect(s, dark, (28, 70, 34, 20), border_radius=5)  # 반바지
    pygame.draw.rect(s, jersey, (26, 30, 38, 46), border_radius=10)  # 몸통
    pygame.draw.rect(s, (200, 100, 10), (26, 30, 38, 46), 2, border_radius=10)
    num = pygame.font.SysFont("arialblack,impact", 22).render("1", True, dark)
    s.blit(num, num.get_rect(center=(45, 52)))
    pygame.draw.circle(s, (225, 180, 140), (45, 18), 12)  # 머리
    pygame.draw.arc(s, (40, 25, 15), pygame.Rect(33, 5, 24, 22), 0.2, math.pi - 0.2, 6)
    return s


def make_ball():
    s = pygame.Surface((64, 64), pygame.SRCALPHA)
    pygame.draw.circle(s, (250, 250, 250), (32, 32), 31)

    def pent(cx, cy, r, rot):
        return [(cx + r * math.cos(rot + i * 2 * math.pi / 5), cy + r * math.sin(rot + i * 2 * math.pi / 5)) for i in range(5)]

    pygame.draw.polygon(s, (30, 30, 30), pent(32, 32, 10, -math.pi / 2))
    for i in range(5):
        a = -math.pi / 2 + i * 2 * math.pi / 5 + math.pi / 5
        pygame.draw.polygon(s, (30, 30, 30), pent(32 + 27 * math.cos(a), 32 + 27 * math.sin(a), 10, a))
    mask = pygame.Surface((64, 64), pygame.SRCALPHA)
    pygame.draw.circle(mask, (255, 255, 255, 255), (32, 32), 31)
    s.blit(mask, (0, 0), special_flags=pygame.BLEND_RGBA_MIN)  # 원 밖 잘라내기
    pygame.draw.circle(s, (90, 90, 90), (32, 32), 31, 2)
    pygame.draw.ellipse(s, (255, 255, 255, 110), (12, 9, 20, 12))
    return s


def outlined(font, msg, color, ow=4):
    base = font.render(msg, True, color)
    black = font.render(msg, True, (0, 0, 0))
    out = pygame.Surface((base.get_width() + ow * 2, base.get_height() + ow * 2), pygame.SRCALPHA)
    for dx in (-ow, 0, ow):
        for dy in (-ow, 0, ow):
            out.blit(black, (ow + dx, ow + dy))
    out.blit(base, (ow, ow))
    return out


# ---------- 매 프레임 그리기 ----------

def draw_net(layer, hit, amp):
    col = (255, 255, 255, 110)

    def warp(x, y):  # 골 들어가면 맞은 자리 그물이 출렁
        if amp <= 0:
            return (x, y)
        dx, dy = hit[0] - x, hit[1] - y
        g = amp * math.exp(-(dx * dx + dy * dy) / (2 * 40 * 40))
        return (x + dx * g * 0.35, y + dy * g * 0.35 - g * 4)

    pygame.draw.polygon(layer, (0, 0, 0, 45), [GOAL.topleft, GOAL.topright, GOAL.bottomright, GOAL.bottomleft])
    n, m = 16, 9
    for i in range(n + 1):
        x = BACK.left + BACK.w * i / n
        pygame.draw.lines(layer, col, False, [warp(x, BACK.top + BACK.h * k / 8) for k in range(9)])
        pygame.draw.line(layer, col, (GOAL.left + GOAL.w * i / n, GOAL.top), warp(x, BACK.top))
    for j in range(m + 1):
        y = BACK.top + BACK.h * j / m
        pygame.draw.lines(layer, col, False, [warp(BACK.left + BACK.w * k / 12, y) for k in range(13)])
        fy = GOAL.top + GOAL.h * j / m
        pygame.draw.line(layer, col, (GOAL.left, fy), warp(BACK.left, y))
        pygame.draw.line(layer, col, (GOAL.right, fy), warp(BACK.right, y))
    for k in range(1, 4):  # 옆그물/지붕 세로줄
        t = k / 4
        for fx, bx in ((GOAL.left, BACK.left), (GOAL.right, BACK.right)):
            x = lerp(fx, bx, t)
            pygame.draw.line(layer, col, (x, lerp(GOAL.top, BACK.top, t)), (x, lerp(GOAL.bottom, BACK.bottom, t)))
        y = lerp(GOAL.top, BACK.top, t)
        pygame.draw.line(layer, col, (lerp(GOAL.left, BACK.left, t), y), (lerp(GOAL.right, BACK.right, t), y))


def draw_posts(screen):
    for r in (pygame.Rect(GOAL.left - 5, GOAL.top - 5, 10, GOAL.h + 5),
              pygame.Rect(GOAL.right - 5, GOAL.top - 5, 10, GOAL.h + 5),
              pygame.Rect(GOAL.left - 5, GOAL.top - 5, GOAL.w + 10, 10)):
        pygame.draw.rect(screen, (250, 250, 250), r, border_radius=4)
    pygame.draw.line(screen, (190, 190, 190), (GOAL.left + 3, GOAL.top + 5), (GOAL.left + 3, GOAL.bottom), 2)
    pygame.draw.line(screen, (190, 190, 190), (GOAL.right + 3, GOAL.top + 5), (GOAL.right + 3, GOAL.bottom), 2)


def draw_ball(screen, img, pos, r, angle):
    sh = pygame.Surface((int(r * 3), max(4, int(r))), pygame.SRCALPHA)
    pygame.draw.ellipse(sh, (0, 0, 0, 90), sh.get_rect())
    screen.blit(sh, sh.get_rect(center=pos[2]))
    b = pygame.transform.rotozoom(img, angle, r * 2 / 64)
    screen.blit(b, b.get_rect(center=pos[:2]))


def draw_hud(screen, state, now):
    ui.panel(screen, (16, 14, 250, 62), (10, 14, 28, 215), radius=12)
    pygame.draw.rect(screen, (255, 140, 20), (16, 14, 6, 62), border_top_left_radius=12, border_bottom_left_radius=12)
    ui.text(screen, "FESTIVAL CUP · 승부차기", 14, (34, 30), (160, 170, 190), anchor="midleft", bold=False, shadow=False)
    ui.text(screen, "단 한 번의 슛!", 24, (34, 56), ui.WHITE, anchor="midleft")
    if state == "ready":
        pulse = 0.5 + 0.5 * math.sin(now / 250)
        ui.pill(screen, "SPACE 또는 터치  ·  슛!", (400, 568 + 3 * pulse), 24, bg=(0, 0, 0, int(150 + 60 * pulse)))


# ---------- 게임 ----------

def play(screen, win: bool, prize: str = None) -> bool:
    clock = pygame.time.Clock()
    big = pygame.font.SysFont("arialblack,impact", 100)
    bg, keeper_img, ball_img = make_bg(), make_keeper(), make_ball()
    layer = pygame.Surface((W, H), pygame.SRCALPHA)
    banners = {"goal": outlined(big, "GOAL!", (255, 215, 0)),
               "save": outlined(big, "SAVED!", (120, 190, 255)),
               "miss": outlined(big, "MISS", (255, 90, 90))}

    state, t0 = "ready", pygame.time.get_ticks()
    dive, tx, ty, res = pick_shot(win)  # 결과는 시작 전에 정해짐
    sway0 = 0.0
    confetti = []
    shake_at = -9999
    tier = min(ui.TOP_TIER, prize_rank(prize)) if prize else int(win)  # 경품 이름을 못 받으면 당첨=1등급
    show = ui.TierShow(tier if win else 0, prize or "당첨!", center=(400, 236))
    trail = []
    sfx.play("whistle")

    while True:
        now = pygame.time.get_ticks()
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            shoot = (e.type == pygame.KEYDOWN and e.key in (pygame.K_SPACE, pygame.K_RETURN)) or \
                (e.type == pygame.MOUSEBUTTONDOWN and e.button == 1)
            if shoot and state == "ready" and now - t0 > 500:  # 0.5초: 메뉴에서 넘어온 연타 무시
                state, t0, sway0 = "fly", now, 12 * math.sin(now / 250)
                sfx.play("kick")

        # 상태 진행
        if state == "fly" and now - t0 > FLY_MS:
            if res == "goal":
                confetti = [[400, 230, random.uniform(-7, 7), random.uniform(-9, -2),
                             random.choice([(255, 215, 0), (255, 80, 80), (90, 200, 255), (255, 255, 255)])]
                            for _ in range(120)]
            state, t0 = "result", now
            if res == "goal":
                shake_at = now
                sfx.play("net")
                sfx.play("cheer")
            else:
                if res == "save":
                    shake_at = now
                    sfx.play("hit", 0.6)
                sfx.play("groan")
        elif state == "result" and res == "goal" and not show.started and now - t0 > 750:
            show.start(now)  # GOAL! 다음 박자에 등급이 터짐
            shake_at = now
        elif state == "result" and now - t0 > 2000 + (show.duration if res == "goal" else 0):
            return True

        # 공 위치 (x, y, 그림자위치), 반지름, 회전
        el = now - t0
        bx_back = BACK.left + (tx - GOAL.left) / GOAL.w * BACK.w
        by_back = BACK.top + (ty - GOAL.top) / GOAL.h * BACK.h
        if state == "fly":
            k = ease(el / FLY_MS)
            x = lerp(SPOT[0], tx, k) + (tx - 400) * 0.15 * math.sin(math.pi * k)
            y = lerp(SPOT[1], ty, k) - 30 * math.sin(math.pi * k)
            ball = ((x, y, (x, lerp(SPOT[1] + 12, GOAL.bottom, k))), lerp(15, 7, k), k * 900)
            trail.append((x, y, lerp(15, 7, k)))
        elif state == "result":
            k = ease(el / 450)
            if res == "goal":
                x, y = lerp(tx, bx_back, ease(el / 150)), lerp(ty, by_back, ease(el / 150))
                y = lerp(y, BACK.bottom - 6, ease((el - 150) / 400))
                ball = ((x, y, (x, BACK.bottom)), 6.5, 900)
            elif res == "save":
                side = 1 if tx >= 400 else -1
                x, y = lerp(tx, tx + side * 140, k), lerp(ty, 400, k) - 40 * math.sin(math.pi * k)
                ball = ((x, y, (x, lerp(GOAL.bottom, 405, k))), lerp(7, 11, k), 900 - k * 400)
            else:
                x, y = lerp(tx, tx + (tx - 400) * 0.4, k), lerp(ty, ty - 40, k)
                ball = ((x, y, (x, GOAL.bottom - 10 * k)), lerp(7, 4, k), 900 + k * 300) if el < 450 else None
        else:
            ball = ((SPOT[0], SPOT[1], (SPOT[0], SPOT[1] + 12)), 15, 0)

        # 키퍼
        if state in ("fly", "result"):
            rect, d = DIVES[dive]
            k = 1 if state == "result" else ease((el / FLY_MS) * 1.4 - 0.15)
            c0 = (400 + sway0, KEEPER_FEET_Y - 60)
            kc = (lerp(c0[0], rect.centerx, k), lerp(c0[1], rect.centery if d else 215, k))
            kimg = pygame.transform.rotozoom(keeper_img, 75 * d * k, 1)
        else:
            kc = (400 + 12 * math.sin(now / 250), KEEPER_FEET_Y - 60 + 2 * math.sin(now / 120))
            kimg = keeper_img

        # 그리기
        screen.blit(bg, (0, 0))
        if state == "result" and res == "goal" and el < 1000:  # 관중 카메라 플래시
            for _ in range(8):
                pygame.draw.circle(screen, (255, 255, 255), (random.randint(0, W), random.randint(50, 180)), random.randint(1, 3))
        layer.fill((0, 0, 0, 0))
        amp = max(0.0, 1 - el / 700) * (0.6 + 0.4 * math.cos(el / 45)) if state == "result" and res == "goal" else 0
        draw_net(layer, (bx_back, by_back), amp)
        screen.blit(layer, (0, 0))
        if state == "result" and res == "goal" and ball:  # 골이면 공이 그물 안 (키퍼/골대 뒤)
            draw_ball(screen, ball_img, *ball)
        draw_posts(screen)
        sh = pygame.Surface((70, 14), pygame.SRCALPHA)
        pygame.draw.ellipse(sh, (0, 0, 0, 80), sh.get_rect())
        screen.blit(sh, sh.get_rect(center=(kc[0], KEEPER_FEET_Y)))
        screen.blit(kimg, kimg.get_rect(center=kc))
        if state == "fly" and show.rank:  # 등급 색 꼬리
            for i, (x, y, r) in enumerate(trail[-12:]):
                g = ui.glow(int(r * (1.4 + i * 0.12)), ui.TIERS[show.rank]["c"], 40 + i * 12)
                screen.blit(g, g.get_rect(center=(x, y)))
        if ball and not (state == "result" and res == "goal"):
            draw_ball(screen, ball_img, *ball)

        for p in confetti:
            p[0] += p[2]
            p[1] += p[3]
            p[3] += 0.25
            pygame.draw.rect(screen, p[4], (p[0], p[1], 4, 7))
        confetti = [p for p in confetti if p[1] < H]

        if state == "result":
            sc = 1.5 - 0.5 * ease(el / 200)
            b = pygame.transform.rotozoom(banners[res], 0, sc)
            screen.blit(b, b.get_rect(center=(400, 430)))
        show.draw(screen, now)
        draw_hud(screen, state, now)
        shake = max(0.0, 1 - (now - shake_at) / 220) * 7
        if shake > 0.5:
            snap = screen.copy()
            screen.blit(snap, (random.uniform(-shake, shake), random.uniform(-shake, shake)))
        pygame.display.flip()
        clock.tick(60)


def thumbnail():
    s = pygame.Surface((W, H))
    s.blit(make_bg(), (0, 0))
    layer = pygame.Surface((W, H), pygame.SRCALPHA)
    draw_net(layer, (0, 0), 0)
    s.blit(layer, (0, 0))
    draw_posts(s)
    k = pygame.transform.rotozoom(make_keeper(), 60, 1)
    s.blit(k, k.get_rect(center=(330, 250)))
    draw_ball(s, make_ball(), (510, 205, (510, 318)), 14, 30)
    return s.subsurface((160, 110, 480, 300)).copy()
