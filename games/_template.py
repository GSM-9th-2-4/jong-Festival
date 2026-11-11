"""복사해서 games/<내게임>.py 로 저장. '_' 로 시작하는 파일은 메뉴에 안 뜸.

결과(당첨/꽝)는 런처가 확률표(core/store.py)로 미리 뽑아서 win 으로 넘겨줌.
게임은 그 결과에 맞게 연출만 하면 됨. 경품 화면도 런처가 띄움.

필수:
- NAME: 메뉴에 보일 이름
- play(screen, win) -> bool : 끝까지 진행했으면 True, ESC/창닫기면 False(경품 없음)
선택 (메뉴 카드용):
- TAGLINE: 한 줄 설명 / COLOR: 썸네일 없을 때 카드 색 / thumbnail() -> Surface: 카드 그림

공용 도구 (써도 되고 안 써도 됨):
- from core import ui   → ui.text / ui.pill / ui.panel / ui.Particles / ui.out_back ... (core/ui.py)
- from core import sfx  → sfx.play("hit") 등 (core/sfx.py 에 목록)

규칙: screen 은 800x600. 자기 게임 루프 안에서만 놀고, pygame.quit() 호출 금지.
이미지/사운드 파일은 games/assets/<내게임>/ 에.
"""
import pygame

from core import sfx, ui

NAME = "템플릿"
TAGLINE = "스페이스 한 번!"
COLOR = ui.SKY


def play(screen, win: bool) -> bool:
    clock = pygame.time.Clock()
    fx = ui.Particles()
    done_at = None
    while True:
        now = pygame.time.get_ticks()
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type == pygame.KEYDOWN and e.key == pygame.K_SPACE and done_at is None:
                done_at = now  # 예시: 스페이스 누르면 결과 연출 시작
                sfx.play("coin" if win else "groan")
                if win:
                    fx.burst((400, 300), 60)
        if done_at is not None and now - done_at > 1500:
            return True

        screen.fill((24, 28, 48))
        if done_at is None:
            ui.pill(screen, "SPACE 를 누르세요", (400, 300), 30)
        else:
            ui.text(screen, "성공!" if win else "실패…", 90, (400, 300), ui.GOLD if win else ui.GRAY, outline=5,
                    scale=ui.out_back((now - done_at) / 300))
        fx.update_draw(screen)
        pygame.display.flip()
        clock.tick(60)
