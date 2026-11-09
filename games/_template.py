"""복사해서 games/<내게임>.py 로 저장. '_' 로 시작하는 파일은 메뉴에 안 뜸.

규칙:
- NAME: 메뉴에 보일 이름
- play(screen) -> bool : 이기면 True, 지거나 ESC면 False
- screen 은 800x600. 자기 게임 루프 안에서만 놀고, pygame.quit() 호출 금지
- 이미지/사운드는 games/assets/<내게임>/ 에
"""
import pygame

NAME = "템플릿"


def play(screen) -> bool:
    clock = pygame.time.Clock()
    while True:
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type == pygame.KEYDOWN and e.key == pygame.K_SPACE:
                return True  # 예시: 스페이스 누르면 승리
        screen.fill((0, 0, 0))
        pygame.display.flip()
        clock.tick(60)
