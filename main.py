"""Launcher: auto-discovers games/*.py, shows a menu, issues a coupon on win.
Adding a game = adding one file in games/. Nobody needs to edit this file."""
import importlib
import pkgutil
import sys

import pygame

import coupon
import games

W, H = 800, 600


def load_games():
    found = []
    for m in pkgutil.iter_modules(games.__path__):
        if m.name.startswith("_"):
            continue  # _template etc.
        try:
            mod = importlib.import_module(f"games.{m.name}")
            found.append(mod)
        except Exception as e:  # one broken game must not kill the booth
            print(f"[skip] games/{m.name}.py: {e}", file=sys.stderr)
    return sorted(found, key=lambda g: g.NAME)


def text(screen, font, msg, y, color=(255, 255, 255)):
    s = font.render(msg, True, color)
    screen.blit(s, s.get_rect(center=(W // 2, y)))


def show_coupon(screen, font, code):
    while True:
        screen.fill((20, 60, 20))
        text(screen, font, "축하합니다! 쿠폰 코드", 220)
        text(screen, pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 96), code, 320, (255, 230, 0))
        text(screen, font, "스태프에게 보여주세요 (아무 키)", 450)
        pygame.display.flip()
        for e in pygame.event.get():
            if e.type == pygame.KEYDOWN:
                return


def menu(screen, font, game_list):
    sel = 0
    clock = pygame.time.Clock()
    while True:
        screen.fill((30, 30, 50))
        text(screen, font, "미니게임 선택 (↑↓ / Enter)", 80)
        for i, g in enumerate(game_list):
            text(screen, font, g.NAME, 180 + i * 50, (255, 230, 0) if i == sel else (200, 200, 200))
        pygame.display.flip()
        for e in pygame.event.get():
            if e.type == pygame.QUIT:
                return None
            if e.type == pygame.KEYDOWN:
                if e.key == pygame.K_ESCAPE:
                    return None
                if e.key == pygame.K_UP:
                    sel = (sel - 1) % len(game_list)
                if e.key == pygame.K_DOWN:
                    sel = (sel + 1) % len(game_list)
                if e.key == pygame.K_RETURN:
                    return game_list[sel]
        clock.tick(30)


def main():
    pygame.init()
    screen = pygame.display.set_mode((W, H))
    pygame.display.set_caption("축제 미니게임")
    font = pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 36)
    game_list = load_games()
    if not game_list:
        sys.exit("games/ 에 게임이 없음")
    while (g := menu(screen, font, game_list)) is not None:
        try:
            won = g.play(screen)
        except Exception as e:
            print(f"[crash] {g.NAME}: {e}", file=sys.stderr)
            won = False
        if won:
            show_coupon(screen, font, coupon.issue(g.NAME))
    pygame.quit()


if __name__ == "__main__":
    main()
