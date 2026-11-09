"""두더지 잡기: 20초 안에 마우스로 두더지 15마리 잡으면 승리. 헛클릭은 -1."""
import random

import pygame

NAME = "두더지 잡기"
TIME_MS = 20_000
GOAL = 15
UP_MS = 900          # 두더지가 떠 있는 시간 (난이도 조절은 여기)
GAP_MS = (200, 600)  # 다음 두더지까지 대기

HOLES = [pygame.Rect(170 + c * 170, 170 + r * 140, 120, 80) for r in range(3) for c in range(3)]


def play(screen) -> bool:
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 32)
    start = pygame.time.get_ticks()
    score = 0
    mole, mole_until = None, 0
    next_at = start + 800

    while True:
        now = pygame.time.get_ticks()
        left = TIME_MS - (now - start)
        if score >= GOAL:
            return True
        if left <= 0:
            return False

        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type == pygame.MOUSEBUTTONDOWN and e.button == 1:
                if mole is not None and HOLES[mole].inflate(0, 60).collidepoint(e.pos):
                    score += 1
                    mole, next_at = None, now + random.randint(*GAP_MS)
                else:
                    score = max(0, score - 1)

        if mole is not None and now > mole_until:
            mole, next_at = None, now + random.randint(*GAP_MS)
        if mole is None and now >= next_at:
            mole = random.randrange(len(HOLES))
            mole_until = now + UP_MS

        screen.fill((90, 160, 70))
        for i, h in enumerate(HOLES):
            pygame.draw.ellipse(screen, (50, 30, 20), h)
            if i == mole:
                body = pygame.Rect(0, 0, 80, 90)
                body.midbottom = (h.centerx, h.centery + 10)
                pygame.draw.ellipse(screen, (120, 80, 50), body)
                for dx in (-15, 15):
                    pygame.draw.circle(screen, (0, 0, 0), (h.centerx + dx, body.top + 30), 6)
                pygame.draw.circle(screen, (230, 120, 140), (h.centerx, body.top + 45), 8)
        hud = font.render(f"잡은 수 {score}/{GOAL}   남은 시간 {left / 1000:.1f}초", True, (255, 255, 255))
        screen.blit(hud, (20, 20))
        pygame.display.flip()
        clock.tick(60)
