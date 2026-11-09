"""두더지 잡기: 15초 동안 마우스로 두더지 잡기. 점수는 재미용, 경품은 런처가 뽑은 결과 그대로."""
import random

import pygame

NAME = "두더지 잡기"
TIME_MS = 15_000
UP_MS = 900          # 두더지가 떠 있는 시간
GAP_MS = (200, 600)  # 다음 두더지까지 대기
END_MS = 1500        # "시간 종료" 보여주는 시간

HOLES = [pygame.Rect(170 + c * 170, 170 + r * 140, 120, 80) for r in range(3) for c in range(3)]


def play(screen, win: bool) -> bool:  # win 은 안 씀: 결과 화면은 런처가 띄움
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 32)
    big = pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 64, bold=True)
    start = pygame.time.get_ticks()
    score = 0
    mole, mole_until = None, 0
    next_at = start + 800

    while True:
        now = pygame.time.get_ticks()
        left = TIME_MS - (now - start)
        if left <= -END_MS:
            return True

        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if left > 0 and e.type == pygame.MOUSEBUTTONDOWN and e.button == 1:
                if mole is not None and HOLES[mole].inflate(0, 60).collidepoint(e.pos):
                    score += 1
                    mole, next_at = None, now + random.randint(*GAP_MS)

        if left <= 0:
            mole = None
        elif mole is not None and now > mole_until:
            mole, next_at = None, now + random.randint(*GAP_MS)
        elif mole is None and now >= next_at:
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
        hud = font.render(f"잡은 수 {score}   남은 시간 {max(0, left) / 1000:.1f}초", True, (255, 255, 255))
        screen.blit(hud, (20, 20))
        if left <= 0:
            s = big.render(f"시간 종료! {score}마리", True, (255, 230, 0))
            screen.blit(s, s.get_rect(center=(400, 300)))
        pygame.display.flip()
        clock.tick(60)
