"""페널티킥: 스페이스로 좌우 조준 → 상하 조준 → 슛. 5번 중 3골이면 승리.
키퍼는 랜덤으로 왼/가운데/오른쪽을 막음. 위쪽 구석은 키퍼 손이 안 닿음(대신 골대 밖으로 나가기 쉬움)."""
import random

import pygame

NAME = "페널티킥"
SHOTS = 5
GOAL_NEED = 3
SWEEP_MS = 1100  # 조준 마커 왕복 시간. 작을수록 어려움

GOAL = pygame.Rect(150, 150, 500, 200)
AIM = GOAL.inflate(80, 60)  # 조준 범위가 골대보다 넓어서 빗나갈 수 있음
SPOT = (400, 540)
KEEPER_STAND = pygame.Rect(370, 230, 60, 120)
KEEPER_DIVE = {
    "left": pygame.Rect(150, 210, 190, 140),
    "center": pygame.Rect(320, 170, 160, 180),
    "right": pygame.Rect(460, 210, 190, 140),
}


def tri(now, lo, hi):
    """lo~hi 사이를 왕복하는 값."""
    p = (now % SWEEP_MS) / SWEEP_MS
    p = 2 * p if p < 0.5 else 2 - 2 * p
    return lo + (hi - lo) * p


def lerp(a, b, t):
    return a + (b - a) * t


def play(screen) -> bool:
    clock = pygame.time.Clock()
    font = pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 32)
    big = pygame.font.SysFont("applegothic,malgungothic,nanumgothic", 72)
    goals = shot = 0
    state, t0 = "aim_x", pygame.time.get_ticks()
    tx = ty = 0
    keeper = KEEPER_STAND
    result = ""

    while True:
        now = pygame.time.get_ticks()
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return False
            if e.type == pygame.KEYDOWN and e.key == pygame.K_SPACE:
                if state == "aim_x":
                    tx, state, t0 = tri(now - t0, AIM.left, AIM.right), "aim_y", now
                elif state == "aim_y":
                    ty, state, t0 = tri(now - t0, AIM.top, AIM.bottom), "fly", now
                    keeper = KEEPER_DIVE[random.choice(list(KEEPER_DIVE))]

        # 상태 진행
        if state == "fly" and now - t0 > 500:
            if not GOAL.collidepoint(tx, ty):
                result = "빗나감!"
            elif keeper.collidepoint(tx, ty):
                result = "막힘!"
            else:
                result, goals = "골!", goals + 1
            shot += 1
            state, t0 = "result", now
        elif state == "result" and now - t0 > 1000:
            if goals >= GOAL_NEED:
                return True
            if shot >= SHOTS or goals + (SHOTS - shot) < GOAL_NEED:
                return False  # 남은 슛 다 넣어도 못 이기면 바로 종료
            state, t0, keeper = "aim_x", now, KEEPER_STAND

        # 그리기
        screen.fill((40, 140, 60))
        pygame.draw.rect(screen, (230, 230, 230), GOAL, 6)
        pygame.draw.circle(screen, (255, 255, 255), SPOT, 5)

        if state in ("fly", "result"):
            t = min(1, (now - t0) / 500) if state == "fly" else 1
            k = KEEPER_STAND.copy()
            for attr in ("x", "y", "w", "h"):
                setattr(k, attr, round(lerp(getattr(KEEPER_STAND, attr), getattr(keeper, attr), t)))
            pygame.draw.rect(screen, (230, 180, 0), k, border_radius=20)
            ball = (lerp(SPOT[0], tx, t), lerp(SPOT[1], ty, t))
        else:
            pygame.draw.rect(screen, (230, 180, 0), KEEPER_STAND, border_radius=20)
            ball = SPOT
        pygame.draw.circle(screen, (255, 255, 255), ball, 14)
        pygame.draw.circle(screen, (0, 0, 0), ball, 14, 2)

        if state == "aim_x":
            x = tri(now - t0, AIM.left, AIM.right)
            pygame.draw.line(screen, (255, 60, 60), (x, AIM.top), (x, AIM.bottom), 4)
        elif state == "aim_y":
            y = tri(now - t0, AIM.top, AIM.bottom)
            pygame.draw.line(screen, (255, 60, 60), (tx, AIM.top), (tx, AIM.bottom), 2)
            pygame.draw.line(screen, (255, 60, 60), (AIM.left, y), (AIM.right, y), 4)
        elif state == "result":
            s = big.render(result, True, (255, 255, 0))
            screen.blit(s, s.get_rect(center=(400, 440)))

        hud = font.render(f"골 {goals}/{GOAL_NEED}   슛 {shot}/{SHOTS}   (스페이스)", True, (255, 255, 255))
        screen.blit(hud, (20, 20))
        pygame.display.flip()
        clock.tick(60)
