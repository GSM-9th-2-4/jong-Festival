"""복사해서 games/<내게임>.py 로 저장. '_' 로 시작하는 파일은 메뉴에 안 뜸.

결과(당첨/꽝)는 런처가 확률표(coupon.py)로 미리 뽑아서 win 으로 넘겨줌.
게임은 그 결과에 맞게 연출만 하면 됨. 경품 화면도 런처가 띄움.

규칙:
- NAME: 메뉴에 보일 이름
- play(screen, win) -> bool : 끝까지 진행했으면 True, ESC/창닫기면 False(경품 없음)
- screen 은 800x600. 자기 게임 루프 안에서만 놀고, pygame.quit() 호출 금지
- 이미지/사운드는 games/assets/<내게임>/ 에
"""
import pygame

NAME = "템플릿"


def play(screen, win: bool) -> bool:
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 48)
    while True:
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type == pygame.KEYDOWN and e.key == pygame.K_SPACE:
                return True  # 예시: 스페이스 누르면 끝
        screen.fill((0, 0, 0))
        msg = font.render("스페이스! (" + ("당첨" if win else "꽝") + " 예정)", True, (255, 255, 255))
        screen.blit(msg, msg.get_rect(center=(400, 300)))
        pygame.display.flip()
        clock.tick(60)
