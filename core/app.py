"""런처(키오스크). 대기 화면 → 게임 선택 → 추첨 → 게임 → 결과 → 대기 화면.

실행: python main.py [--kiosk]
  --kiosk : 전체화면 + ESC로 종료 불가 (종료는 관리자 화면 F10)
키: F1 관리자(PIN) · F11 전체화면 · 결과 화면에서 F2 = 그 자리에서 쿠폰 사용 처리
"""
import importlib
import math
import os
import pkgutil
import sys
import traceback

import pygame

import games
from core import sfx, ui
from core.store import LOSE, PRIZES, Store

TITLE = "종 페스티벌"
PIN = os.environ.get("FESTIVAL_PIN", "0000")  # 부스에서는 환경변수로 바꿔서 실행
IDLE_MS = 30_000        # 메뉴에서 입력 없으면 대기 화면으로
RESULT_LOCK_MS = 1500   # 결과 화면 연타 스킵 방지
JACKPOT = "대박"
COLS, PER_PAGE = 3, 6


class Entry:
    """메뉴에 올라가는 게임 하나. NAME/play 외에는 전부 선택 사항."""

    def __init__(self, mod):
        self.mod = mod
        self.name = mod.NAME
        self.tagline = getattr(mod, "TAGLINE", "")
        self.color = getattr(mod, "COLOR", ui.PINK)
        self.thumb = None
        if hasattr(mod, "thumbnail"):
            try:
                self.thumb = mod.thumbnail()
            except Exception:
                traceback.print_exc()


def load_games():
    found = []
    for m in pkgutil.iter_modules(games.__path__):
        if m.name.startswith("_"):
            continue  # _template 등
        try:
            found.append(Entry(importlib.import_module(f"games.{m.name}")))
        except Exception as e:  # 게임 하나가 깨져도 부스는 계속 돌아가야 함
            print(f"[skip] games/{m.name}.py: {e}", file=sys.stderr)
    return sorted(found, key=lambda g: g.name)


def rounded(surf, size, radius):
    """size 로 맞추고 모서리를 둥글게 자른 복사본."""
    s = pygame.transform.smoothscale(surf, size).convert_alpha()
    mask = pygame.Surface(size, pygame.SRCALPHA)
    pygame.draw.rect(mask, (255, 255, 255, 255), mask.get_rect(), border_radius=radius)
    s.blit(mask, (0, 0), special_flags=pygame.BLEND_RGBA_MIN)
    return s


class App:
    def __init__(self, kiosk=False, store=None):
        pygame.mixer.pre_init(22050, -16, 1, 512)
        pygame.init()
        flags = pygame.SCALED | (pygame.FULLSCREEN if kiosk else 0)
        try:
            self.screen = pygame.display.set_mode((ui.W, ui.H), flags)
        except pygame.error:  # SCALED 미지원 환경
            self.screen = pygame.display.set_mode((ui.W, ui.H))
        pygame.display.set_caption(TITLE)
        self.kiosk = kiosk
        self.clock = pygame.time.Clock()
        self.store = store or Store()
        self.back = ui.Backdrop()
        self.games = load_games()
        if not self.games:
            sys.exit("games/ 에 게임이 없음")
        self.sel = 0
        self.pending = None  # 뽑아놓고 아직 안 쓴 경품 (게임 중 ESC로 다시 뽑기 방지)
        self.last = (LOSE, None)
        self.toast = ("", 0)
        self._cards = {}

    # ---------- 공통 ----------

    def run(self):
        state = "attract"
        while state:
            state = getattr(self, state)()
        pygame.quit()

    def frame(self):
        pygame.display.flip()
        self.clock.tick(60)

    def common(self, e):
        """모든 화면 공통 키. 처리했으면 True."""
        if e.type == pygame.KEYDOWN and e.key == pygame.K_F11:
            pygame.display.toggle_fullscreen()
            return True
        return False

    # ---------- 대기 화면 ----------

    def attract(self):
        prizes = [p.name for p in PRIZES if p.name != LOSE]
        prizes.sort(key=lambda n: JACKPOT not in n)
        while True:
            now = pygame.time.get_ticks()
            for e in pygame.event.get():
                if e.type == pygame.QUIT:
                    return None
                if self.common(e):
                    continue
                if e.type == pygame.KEYDOWN:
                    if e.key == pygame.K_F1:
                        return "admin"
                    if e.key == pygame.K_ESCAPE:
                        if self.kiosk:
                            continue
                        return None
                    sfx.play("click")
                    return "menu"
                if e.type == pygame.MOUSEBUTTONDOWN:
                    sfx.play("click")
                    return "menu"

            s = self.screen
            self.back.draw(s, now)
            ui.rays(s, (400, 215), 330, ui.GOLD, now / 2600, alpha=22)
            bob = 6 * math.sin(now / 500)
            ui.text(s, "MINI GAME × DISCOUNT", 20, (400, 128 + bob), ui.MINT)
            ui.text(s, TITLE, 96, (400, 205 + bob), ui.GOLD, outline=5)
            ui.text(s, "게임 한 판에 할인 쿠폰이 팡팡!", 28, (400, 292), ui.WHITE)

            hot = (now // 1400) % len(prizes)
            total_w = sum(ui.render(p, 20, shadow=False).get_width() + 44 for p in prizes) + 14 * (len(prizes) - 1)
            x = 400 - total_w / 2
            for i, p in enumerate(prizes):  # 경품 칩
                w = ui.render(p, 20, shadow=False).get_width() + 44
                on = i == hot
                r = pygame.Rect(x, 352 - (5 if on else 0), w, 42)
                gold = JACKPOT in p
                ui.panel(s, r, (255, 205, 60, 235) if gold else (255, 255, 255, 235 if on else 150), radius=21,
                         border=ui.PINK if on else None, width=3)
                ui.text(s, p, 20, r.center, ui.INK, shadow=False)
                x += w + 14

            pulse = 0.5 + 0.5 * math.sin(now / 350)
            ui.pill(s, "화면을 터치하거나 아무 키나 누르세요", (400, 480 + 3 * pulse), 26,
                    bg=(255, 95, 140, int(170 + 70 * pulse)))
            ui.text(s, "꽝이어도 실망 금지 · 결과는 운에 맡겨요", 16, (400, 560), ui.GRAY, bold=False, shadow=False)
            self.frame()

    # ---------- 게임 선택 ----------

    def card_rects(self, count):
        big = count <= COLS
        cw, ch, gap = (230, 300, 26) if big else (220, 205, 22)
        rects = []
        rows = 1 if big else 2
        top = 345 - (rows * ch + (rows - 1) * gap) / 2
        for i in range(count):
            row, col = divmod(i, COLS)
            n = min(COLS, count - row * COLS)
            x0 = 400 - (n * cw + (n - 1) * gap) / 2
            rects.append(pygame.Rect(x0 + col * (cw + gap), top + row * (ch + gap), cw, ch))
        return rects

    def card(self, g, size):
        key = (g.name, size)
        if key not in self._cards:
            w, h = size
            th = h - 92
            c = pygame.Surface(size, pygame.SRCALPHA)
            pygame.draw.rect(c, (30, 26, 66), c.get_rect(), border_radius=20)
            if g.thumb:
                c.blit(rounded(g.thumb, (w - 16, th), 14), (8, 8))
            else:  # 썸네일 없는 게임: 색 + 첫 글자
                t = pygame.Surface((w - 16, th), pygame.SRCALPHA)
                t.blit(ui.gradient((w - 16, th), g.color, tuple(v // 3 for v in g.color)), (0, 0))
                ui.text(t, g.name[0], th - 30, (t.get_width() / 2, th / 2), ui.WHITE)
                c.blit(rounded(t, (w - 16, th), 14), (8, 8))
            ui.text(c, g.name, 26, (w / 2, th + 34), ui.WHITE)
            ui.text(c, g.tagline, 15, (w / 2, th + 66), ui.GRAY, bold=False, shadow=False)
            self._cards[key] = c
        return self._cards[key]

    def menu(self):
        last_input = pygame.time.get_ticks()
        while True:
            now = pygame.time.get_ticks()
            page = self.sel // PER_PAGE
            shown = self.games[page * PER_PAGE:(page + 1) * PER_PAGE]
            rects = self.card_rects(len(shown))
            start = False
            for e in pygame.event.get():
                if e.type == pygame.QUIT:
                    return None
                if self.common(e):
                    continue
                if e.type in (pygame.KEYDOWN, pygame.MOUSEBUTTONDOWN, pygame.MOUSEMOTION):
                    last_input = now
                if e.type == pygame.KEYDOWN:
                    step = {pygame.K_LEFT: -1, pygame.K_RIGHT: 1, pygame.K_UP: -COLS, pygame.K_DOWN: COLS}.get(e.key)
                    if step:
                        self.sel = (self.sel + step) % len(self.games) if abs(step) == 1 else \
                            max(0, min(len(self.games) - 1, self.sel + step))
                        sfx.play("move")
                    elif e.key in (pygame.K_RETURN, pygame.K_KP_ENTER, pygame.K_SPACE):
                        start = True
                    elif e.key == pygame.K_ESCAPE:
                        return "attract"
                    elif e.key == pygame.K_F1:
                        return "admin"
                if e.type in (pygame.MOUSEMOTION, pygame.MOUSEBUTTONDOWN):
                    for i, r in enumerate(rects):
                        if r.collidepoint(e.pos):
                            if self.sel != page * PER_PAGE + i:
                                self.sel = page * PER_PAGE + i
                                sfx.play("move")
                            start = start or e.type == pygame.MOUSEBUTTONDOWN
            if start:
                sfx.play("click")
                return "game"
            if now - last_input > IDLE_MS:
                return "attract"

            s = self.screen
            self.back.draw(s, now)
            ui.text(s, "게임을 골라주세요", 44, (400, 96), ui.WHITE, outline=3)
            for i, (g, r) in enumerate(zip(shown, rects)):
                on = page * PER_PAGE + i == self.sel
                img = self.card(g, r.size)
                if on:
                    lift = 8 + 3 * math.sin(now / 220)
                    rr = r.move(0, -lift)
                    gl = ui.glow(max(r.w, r.h) // 2 + 60, ui.GOLD, 70)
                    s.blit(gl, gl.get_rect(center=rr.center))
                    s.blit(img, rr)
                    pygame.draw.rect(s, ui.GOLD, rr.inflate(6, 6), 4, border_radius=23)
                    ui.pill(s, "▶ 시작", (rr.centerx, rr.bottom + 4), 20, ui.INK, bg=(255, 205, 60, 255))
                else:
                    dim = img.copy()
                    dim.set_alpha(185)
                    s.blit(dim, r)
            pages = (len(self.games) - 1) // PER_PAGE + 1
            for p in range(pages if pages > 1 else 0):
                pygame.draw.circle(s, ui.GOLD if p == page else ui.GRAY, (400 - (pages - 1) * 9 + p * 18, 545), 5)
            ui.text(s, "←  →  선택   ·   Enter / 터치  시작", 17, (400, 574), ui.GRAY, bold=False, shadow=False)
            if now < self.toast[1]:
                ui.pill(s, self.toast[0], (400, 150), 20, bg=(200, 50, 60, 230))
            self.frame()

    # ---------- 게임 실행 ----------

    def game(self):
        g = self.games[self.sel]
        if self.pending is None:
            self.pending = self.store.draw()  # 결과는 게임 시작 전에 확률표로 결정
        prize = self.pending
        ui.fade(self.screen, self.clock)
        try:
            done = bool(g.mod.play(self.screen, prize != LOSE))
        except Exception:
            traceback.print_exc()
            done = False
            self.toast = ("게임에 문제가 생겼어요. 다른 게임을 골라주세요", pygame.time.get_ticks() + 4000)
        finally:
            pygame.mouse.set_visible(True)
            pygame.event.clear()
        if not done:  # 중간에 나감: 뽑힌 경품은 다음 판에 그대로 (다시 뽑기 불가)
            return "menu"
        self.pending = None
        self.last = (prize, self.store.record(g.name, prize))
        return "result"

    # ---------- 결과 ----------

    def ticket(self, prize, code):
        w, h, split = 620, 220, 400
        t = pygame.Surface((w, h), pygame.SRCALPHA)
        pygame.draw.rect(t, (255, 249, 228), t.get_rect(), border_radius=22)
        pygame.draw.rect(t, (255, 205, 60), (0, 0, w, 46), border_top_left_radius=22, border_top_right_radius=22)
        ui.text(t, f"DISCOUNT COUPON  ·  {TITLE}", 18, (24, 23), ui.INK, anchor="midleft", shadow=False)
        size = 50 if len(prize) <= 8 else 40
        ui.text(t, prize, size, (split / 2, 128), (214, 48, 86), shadow=False)
        for y in range(56, h - 8, 14):  # 절취선
            pygame.draw.line(t, (190, 175, 140), (split, y), (split, y + 7), 2)
        ui.text(t, "쿠폰 코드", 16, ((w + split) / 2, 84), (120, 110, 90), shadow=False)
        ui.text(t, code, 46, ((w + split) / 2, 132), ui.INK, shadow=False)
        ui.text(t, "1회 사용", 14, ((w + split) / 2, 180), (120, 110, 90), bold=False, shadow=False)
        for y in (0, h):  # 절취선 끝 반달 홈
            pygame.draw.circle(t, (0, 0, 0, 0), (split, y), 13)
        return t

    def result(self):
        prize, code = self.last
        win, jackpot = code is not None, JACKPOT in prize
        t0 = pygame.time.get_ticks()
        fx = ui.Particles()
        ticket = self.ticket(prize, code) if win else None
        redeemed = False
        sfx.play("jackpot" if jackpot else "win" if win else "lose")
        if win:
            fx.burst((400, 300), 140 if jackpot else 80, speed=13)
        timeout = 60_000 if win else 9_000
        while True:
            now = pygame.time.get_ticks()
            el = now - t0
            for e in pygame.event.get():
                if e.type == pygame.QUIT:
                    return None
                if self.common(e):
                    continue
                if e.type == pygame.KEYDOWN and e.key == pygame.K_F2 and win and not redeemed:
                    redeemed = self.store.redeem(code)[0] == "ok"  # 스태프가 그 자리에서 사용 처리
                    sfx.play("coin")
                elif e.type in (pygame.KEYDOWN, pygame.MOUSEBUTTONDOWN) and el > RESULT_LOCK_MS:
                    return "attract"
            if el > timeout:
                return "attract"

            s = self.screen
            self.back.draw(s, now)
            if win:
                ui.rays(s, (400, 320), 420, ui.GOLD, now / 1500, alpha=60 if jackpot else 30)
                if jackpot and el % 3 == 0:
                    fx.rain(2, [ui.GOLD, (255, 240, 170), ui.WHITE])
                head = "대박 터졌다!!" if jackpot else "축하합니다!"
                ui.text(s, head, 60, (400, 96), ui.GOLD, outline=4, scale=ui.out_back(el / 350))
                k = ui.out_back((el - 150) / 450)
                if k > 0:
                    img = pygame.transform.rotozoom(ticket, -3 + 1.2 * math.sin(now / 700), max(0.01, k))
                    s.blit(img, img.get_rect(center=(400, 300)))
                    if redeemed:
                        st = pygame.transform.rotozoom(ui.render("사용 완료", 56, ui.RED, outline=3), 14, 1)
                        s.blit(st, st.get_rect(center=(400, 300)))
                ui.text(s, "스태프에게 이 화면을 보여주세요", 28, (400, 462), ui.WHITE)
            else:
                veil = pygame.Surface((ui.W, ui.H), pygame.SRCALPHA)
                veil.fill((10, 10, 30, 120))
                s.blit(veil, (0, 0))
                k = ui.out_back(el / 400)
                img = pygame.transform.rotozoom(ui.render("꽝!", 170, (190, 200, 235), outline=6),
                                                6 * math.sin(now / 260) * max(0.0, 1 - el / 2500), max(0.01, k))
                s.blit(img, img.get_rect(center=(400, 250)))
                ui.text(s, "아쉽지만 다음 기회에!", 34, (400, 400), ui.WHITE)
            fx.update_draw(s)
            if el > RESULT_LOCK_MS:
                ui.text(s, "아무 키나 누르거나 터치하면 처음으로", 18, (400, 532), ui.GRAY, bold=False, shadow=False,
                        alpha=int(150 + 100 * math.sin(now / 300)))
            left = 1 - el / timeout
            pygame.draw.rect(s, (255, 255, 255), (250, 560, 300 * left, 4), border_radius=2)
            self.frame()

    # ---------- 관리자 ----------

    def admin(self):
        if not self.admin_pin():
            return "attract"
        code, msg, color = "", "쿠폰 코드를 입력하고 Enter", ui.GRAY
        while True:
            for e in pygame.event.get():
                if e.type == pygame.QUIT:
                    return None
                if self.common(e) or e.type != pygame.KEYDOWN:
                    continue
                if e.key == pygame.K_ESCAPE:
                    return "attract"
                if e.key == pygame.K_F10:
                    return None
                if e.key == pygame.K_F5:
                    msg, color = f"{self.store.export_csv().name} 로 내보냈어요", ui.MINT
                elif e.key == pygame.K_BACKSPACE:
                    code = code[:-1]
                elif e.key in (pygame.K_RETURN, pygame.K_KP_ENTER) and code:
                    status, prize, ts = self.store.redeem(code)
                    msg, color = {"ok": (f"완료!  {code} 사용 처리 — {prize}", ui.MINT),
                                  "used": (f"이미 사용된 쿠폰  {code} ({(ts or '')[11:]}) — {prize}", ui.RED),
                                  "none": (f"없는 코드  {code}", ui.RED)}[status]
                    sfx.play("coin" if status == "ok" else "error")
                    code = ""
                elif len(code) < 6:  # 한/영 상태와 무관하게 키 위치로 입력
                    ch = chr(e.key).upper() if pygame.K_a <= e.key <= pygame.K_z or pygame.K_0 <= e.key <= pygame.K_9 else \
                        str(e.key - pygame.K_KP1 + 1) if pygame.K_KP1 <= e.key <= pygame.K_KP9 else ""
                    code += ch

            s = self.screen
            s.blit(ui.gradient((ui.W, ui.H), (18, 20, 34), (30, 34, 54)), (0, 0))
            st = self.store.stats()
            total = st["total"]
            ui.text(s, "관리자", 34, (40, 44), ui.WHITE, anchor="midleft")
            ui.text(s, f"총 플레이 {total}판", 24, (760, 44), ui.GOLD, anchor="midright")
            cols = [(40, "경품", "midleft"), (360, "목표", "midright"), (450, "실제", "midright"), (540, "나온 수", "midright"),
                    (640, "사용 완료", "midright"), (760, "남은 수량", "midright")]
            ui.panel(s, (24, 78, 752, 250), (255, 255, 255, 14), radius=14)
            for x, label, anchor in cols:
                ui.text(s, label, 17, (x, 100), ui.GRAY, anchor=anchor, shadow=False)
            for i, (p, n, used) in enumerate(st["prizes"]):
                y = 138 + i * 38
                real = f"{n / total * 100:.1f}%" if total else "-"
                left = "-" if p.cap is None else str(max(0, p.cap - n))
                vals = [p.name, f"{p.pct}%", real, str(n), "-" if p.name == LOSE else str(used), left]
                for (x, _, anchor), v in zip(cols, vals):
                    ui.text(s, v, 21, (x, y), ui.GOLD if JACKPOT in p.name else ui.WHITE, anchor=anchor, shadow=False)
            games_line = "   ".join(f"{g} {n}판" for g, n in st["games"]) or "아직 기록 없음"
            ui.text(s, "게임별  " + games_line, 18, (40, 352), ui.GRAY, anchor="midleft", bold=False, shadow=False)

            ui.panel(s, (24, 384, 752, 150), (255, 255, 255, 14), radius=14)
            ui.text(s, "쿠폰 사용 처리", 20, (40, 408), ui.WHITE, anchor="midleft", shadow=False)
            box = pygame.Rect(40, 432, 300, 60)
            pygame.draw.rect(s, (10, 12, 22), box, border_radius=10)
            pygame.draw.rect(s, ui.GOLD, box, 2, border_radius=10)
            caret = "_" if pygame.time.get_ticks() // 400 % 2 and len(code) < 6 else ""
            ui.text(s, code + caret, 38, (box.x + 18, box.centery), ui.WHITE, anchor="midleft", shadow=False)
            ui.text(s, msg, 19, (360, box.centery), color, anchor="midleft", shadow=False)
            ui.text(s, "F5 CSV 내보내기   ·   F10 프로그램 종료   ·   F11 전체화면   ·   ESC 닫기", 16, (400, 570), ui.GRAY,
                    bold=False, shadow=False)
            self.frame()

    def admin_pin(self):
        typed, shake_until = "", 0
        while True:
            now = pygame.time.get_ticks()
            for e in pygame.event.get():
                if e.type == pygame.QUIT:
                    pygame.event.post(e)
                    return False
                if self.common(e) or e.type != pygame.KEYDOWN:
                    continue
                if e.key == pygame.K_ESCAPE:
                    return False
                if e.key == pygame.K_BACKSPACE:
                    typed = typed[:-1]
                elif e.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                    if typed == PIN:
                        return True
                    typed, shake_until = "", now + 350
                    sfx.play("error")
                elif pygame.K_0 <= e.key <= pygame.K_9 and len(typed) < 8:
                    typed += chr(e.key)
                elif pygame.K_KP1 <= e.key <= pygame.K_KP0 and len(typed) < 8:
                    typed += str((e.key - pygame.K_KP1 + 1) % 10)
            s = self.screen
            s.blit(ui.gradient((ui.W, ui.H), (18, 20, 34), (30, 34, 54)), (0, 0))
            dx = 8 * math.sin(now / 25) if now < shake_until else 0
            ui.panel(s, (250 + dx, 200, 300, 190), (255, 255, 255, 18), radius=18)
            ui.text(s, "관리자 PIN", 26, (400 + dx, 244), ui.WHITE)
            ui.text(s, "●" * len(typed) or "—", 34, (400 + dx, 304), ui.GOLD, shadow=False)
            ui.text(s, "숫자 입력 후 Enter  ·  ESC 취소", 15, (400 + dx, 358), ui.GRAY, bold=False, shadow=False)
            self.frame()


def main():
    App(kiosk="--kiosk" in sys.argv).run()
