"""예시 게임: 화면이 초록색 되면 0.4초 안에 스페이스."""
import random

import pygame

NAME = "반응속도"
LIMIT_MS = 400


def play(screen) -> bool:
    clock = pygame.time.Clock()
    go_at = pygame.time.get_ticks() + random.randint(1500, 4000)
    while True:
        now = pygame.time.get_ticks()
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type == pygame.KEYDOWN and e.key == pygame.K_SPACE:
                return go_at <= now <= go_at + LIMIT_MS  # too early = lose
        if now > go_at + LIMIT_MS:
            return False
        screen.fill((0, 200, 0) if now >= go_at else (200, 0, 0))
        pygame.display.flip()
        clock.tick(120)
