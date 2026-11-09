"""두더지 잡기: 15초 동안 두더지 잡기(점수는 재미용) → 마지막 한 방: 구멍 3개 중 하나 골라 때리기.
당첨이면 황금 두더지, 꽝이면 꽝 두더지. 어느 구멍을 골라도 결과는 런처가 뽑은 win 그대로."""
import math
import random

import pygame

NAME = "두더지 잡기"
TIME_MS = 15_000
UP_MS = 900          # 두더지가 떠 있는 시간
GAP_MS = (200, 600)  # 다음 두더지까지 대기
REVEAL_MS = 2000     # 마지막 결과 보여주는 시간

HOLES = [pygame.Rect(170 + c * 170, 170 + r * 140, 120, 80) for r in range(3) for c in range(3)]
PICK = (3, 4, 5)  # 마지막 한 방 후보: 가운데 줄
KOR = "applegothic,malgungothic,nanumgothic"


def draw_mole(screen, hole, body_color, dead=False):
    body = pygame.Rect(0, 0, 80, 90)
    body.midbottom = (hole.centerx, hole.centery + 10)
    pygame.draw.ellipse(screen, body_color, body)
    for dx in (-15, 15):
        c = (hole.centerx + dx, body.top + 30)
        if dead:  # X 눈
            pygame.draw.line(screen, (0, 0, 0), (c[0] - 5, c[1] - 5), (c[0] + 5, c[1] + 5), 3)
            pygame.draw.line(screen, (0, 0, 0), (c[0] - 5, c[1] + 5), (c[0] + 5, c[1] - 5), 3)
        else:
            pygame.draw.circle(screen, (0, 0, 0), c, 6)
    pygame.draw.circle(screen, (230, 120, 140), (hole.centerx, body.top + 45), 8)
    return body


def play(screen, win: bool) -> bool:
    clock = pygame.time.Clock()
    font = pygame.font.SysFont(KOR, 32)
    big = pygame.font.SysFont(KOR, 64, bold=True)
    start = pygame.time.get_ticks()
    score = 0
    mole, mole_until = None, 0
    next_at = start + 800
    phase, picked, reveal_at = "play", None, 0

    while True:
        now = pygame.time.get_ticks()
        left = TIME_MS - (now - start)
        if phase == "play" and left <= 0:
            phase, mole = "pick", None
        if phase == "reveal" and now - reveal_at > REVEAL_MS:
            return True

        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type != pygame.MOUSEBUTTONDOWN or e.button != 1:
                continue
            if phase == "play" and mole is not None and HOLES[mole].inflate(0, 60).collidepoint(e.pos):
                score += 1
                mole, next_at = None, now + random.randint(*GAP_MS)
            elif phase == "pick":
                for i in PICK:
                    if HOLES[i].inflate(20, 60).collidepoint(e.pos):
                        phase, picked, reveal_at = "reveal", i, now

        if phase == "play":
            if mole is not None and now > mole_until:
                mole, next_at = None, now + random.randint(*GAP_MS)
            elif mole is None and now >= next_at:
                mole = random.randrange(len(HOLES))
                mole_until = now + UP_MS

        screen.fill((90, 160, 70))
        for i, h in enumerate(HOLES):
            pygame.draw.ellipse(screen, (50, 30, 20), h)
            if phase == "pick" and i in PICK:
                r = 6 + 3 * math.sin(now / 120)
                pygame.draw.ellipse(screen, (255, 230, 0), h.inflate(r * 2, r * 2), 4)
            if phase == "play" and i == mole:
                draw_mole(screen, h, (120, 80, 50))
            if phase == "reveal" and i == picked:
                if win:
                    body = draw_mole(screen, h, (245, 200, 40))
                    for k in range(8):  # 반짝이
                        a = now / 300 + k * math.pi / 4
                        c = body.center
                        pygame.draw.line(screen, (255, 255, 200), (c[0] + 55 * math.cos(a), c[1] + 55 * math.sin(a)),
                                         (c[0] + 75 * math.cos(a), c[1] + 75 * math.sin(a)), 4)
                else:
                    draw_mole(screen, h, (110, 110, 110), dead=True)

        if phase == "play":
            hud = font.render(f"잡은 수 {score}   남은 시간 {left / 1000:.1f}초", True, (255, 255, 255))
            screen.blit(hud, (20, 20))
        else:
            hud = font.render(f"잡은 수 {score}", True, (255, 255, 255))
            screen.blit(hud, (20, 20))
            if phase == "pick":
                msg, color = "마지막 한 방! 노란 구멍 하나 클릭", (255, 230, 0)
            else:
                msg, color = ("황금 두더지! 당첨!", (255, 215, 0)) if win else ("꽝 두더지...", (220, 220, 220))
            s = big.render(msg, True, color) if phase == "reveal" else font.render(msg, True, color)
            screen.blit(s, s.get_rect(center=(400, 110)))
        pygame.display.flip()
        clock.tick(60)
