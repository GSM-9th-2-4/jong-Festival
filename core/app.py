"""런처(키오스크). 대기 화면 → 게임 선택 → 추첨 → 게임 → 결과 → 대기 화면.

실행: python main.py [--kiosk]
  --kiosk : 전체화면 + ESC로 종료 불가 (종료는 관리자 화면 F10)
키: F1 관리자(PIN) · F11 전체화면 · 결과 화면에서 F2 = 그 자리에서 쿠폰 사용 처리
"""
import importlib
import inspect
import math
import os
import pkgutil
import random
import sys
import traceback

import pygame

import games
from core import sfx, ui
from core.store import LOSE, PRIZES, Store, rank

TITLE = "종 페스티벌"
BRAND = "JONG FESTIVAL"
PIN = os.environ.get("FESTIVAL_PIN", "0000")  # 부스에서는 환경변수로 바꿔서 실행
IDLE_MS = 30_000        # 메뉴에서 입력 없으면 대기 화면으로
RESULT_LOCK_MS = 1500   # 결과 화면 연타 스킵 방지
COLS, PER_PAGE = 3, 6
LINE = (46, 52, 78)


def tier_of(prize):
    return ui.TIERS[min(ui.TOP_TIER, rank(prize))]


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


def cover(surf, size):
    """비율 유지하며 size 를 꽉 채우도록 확대 후 가운데를 잘라냄."""
    w, h = size
    k = max(w / surf.get_width(), h / surf.get_height())
    big = pygame.transform.smoothscale(surf, (math.ceil(surf.get_width() * k), math.ceil(surf.get_height() * k)))
    return big.subsurface(((big.get_width() - w) // 2, (big.get_height() - h) // 2, w, h)).copy()


def round_corners(surf, radius):
    s = surf.convert_alpha()
    mask = pygame.Surface(s.get_size(), pygame.SRCALPHA)
    pygame.draw.rect(mask, (255, 255, 255, 255), mask.get_rect(), border_radius=radius)
    s.blit(mask, (0, 0), special_flags=pygame.BLEND_RGBA_MIN)
    return s


def halo(size, color, spread=34, alpha=170):
    """사각형 뒤에 까는 부드러운 빛."""
    s = pygame.Surface((size[0] + spread * 2, size[1] + spread * 2), pygame.SRCALPHA)
    pygame.draw.rect(s, (*color, alpha), (spread, spread, *size), border_radius=18)
    return ui.blur(s, 9)


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
        self._cache = {}

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

    def cached(self, key, make):
        if key not in self._cache:
            self._cache[key] = make()
        return self._cache[key]

    def topbar(self, right=""):
        s = self.screen
        ui.text(s, BRAND, 20, (32, 30), ui.GOLD, anchor="midleft", en=True, spacing=5, shadow=False)
        if right:
            ui.text(s, right, 16, (768, 30), ui.GRAY, anchor="midright", en=True, spacing=4, shadow=False)
        pygame.draw.line(s, LINE, (32, 50), (768, 50))
        pygame.draw.line(s, ui.GOLD, (32, 50), (92, 50), 2)

    # ---------- 대기 화면 ----------

    def attract(self):
        prizes = sorted((p.name for p in PRIZES if p.name != LOSE), key=rank)
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
            self.topbar("COUPON EVENT")
            bob = 4 * math.sin(now / 900)
            ui.text(s, "MINI GAME ARCADE", 24, (400, 132 + bob), ui.SKY, en=True, spacing=12, shadow=False, glow=(40, 120, 255))
            title = ui.render(TITLE, 112, metal=(ui.GOLD_TOP, ui.GOLD_BOT), glow=(255, 150, 30), shadow=False)
            tr = title.get_rect(center=(400, 214 + bob))
            s.blit(title, tr)
            ui.sheen(s, tr, (now % 3800) / 1000, alpha=150, mask=title)
            ui.flare(s, (400, 290 + bob), 560, ui.GOLD, 200)
            ui.text(s, "게임 한 판, 할인 쿠폰 한 장", 24, (400, 322), ui.WHITE, bold=False)

            hot = (now // 1500) % len(prizes)
            w, gap = 170, 12
            x0 = 400 - (len(prizes) * w + (len(prizes) - 1) * gap) / 2
            for i, p in enumerate(prizes):  # 경품 카드
                t = tier_of(p)
                r = pygame.Rect(x0 + i * (w + gap), 372, w, 78)
                on = i == hot
                if on:
                    g = self.cached(("halo", r.size, t["c"]), lambda: halo(r.size, t["c"], 26, 120))
                    s.blit(g, g.get_rect(center=r.center))
                ui.cut_panel(s, r, 12, (16, 20, 38, 235) if on else (10, 13, 26, 200), accent=t["c"])
                ui.text(s, t["name"].rstrip("!"), 19, (r.x + 16, r.y + 24), t["c"], anchor="midleft", en=True, spacing=3, shadow=False)
                ui.text(s, p, 19, (r.x + 16, r.y + 52), ui.WHITE if on else (190, 196, 215), anchor="midleft", shadow=False)
                if on:
                    ui.sheen(s, r, (now % 1500) / 600, alpha=30)

            pulse = 0.5 + 0.5 * math.sin(now / 420)
            ui.text(s, "PRESS ANY KEY", 30, (400, 506), ui.WHITE, en=True, spacing=10, shadow=False, glow=(60, 140, 255),
                    alpha=int(120 + 135 * pulse))
            ui.text(s, "화면을 터치하거나 아무 키나 누르세요", 16, (400, 540), ui.GRAY, bold=False, shadow=False)
            self.frame()

    # ---------- 게임 선택 ----------

    def card_rects(self, count):
        big = count <= COLS
        cw, ch, gap = (226, 336, 22) if big else (226, 190, 18)
        rows = 1 if big else 2
        top = 334 - (rows * ch + (rows - 1) * gap) / 2
        rects = []
        for i in range(count):
            row, col = divmod(i, COLS)
            n = min(COLS, count - row * COLS)
            x0 = 400 - (n * cw + (n - 1) * gap) / 2
            rects.append(pygame.Rect(x0 + col * (cw + gap), top + row * (ch + gap), cw, ch))
        return rects

    def make_card(self, g, size, index):
        w, h = size
        if g.thumb:
            c = cover(g.thumb, size)
        else:  # 썸네일 없는 게임: 색 그라데이션 + 첫 글자
            c = ui.gradient(size, g.color, tuple(v // 5 for v in g.color)).copy()
            ui.text(c, g.name[0], int(h * 0.42), (w / 2, h * 0.36), ui.WHITE, metal=((255, 255, 255), g.color), shadow=False)
        shade = pygame.Surface(size, pygame.SRCALPHA)  # 아래쪽이 어두워지는 그라데이션 (글자 자리)
        for y in range(h):
            k = ui.clamp((y / h - 0.42) / 0.5)
            shade.fill((4, 6, 14, int(238 * k ** 1.3)), (0, y, w, 1))
        c.blit(shade, (0, 0))
        ui.text(c, f"{index + 1:02d}", 24, (16, 24), ui.WHITE, anchor="midleft", en=True, spacing=2, outline=2)
        ui.text(c, g.name, 28, (16, h - 56), ui.WHITE, anchor="midleft")
        ui.text(c, g.tagline, 14, (17, h - 26), (176, 184, 208), anchor="midleft", bold=False, shadow=False)
        c = round_corners(c, 12)
        pygame.draw.rect(c, (255, 255, 255, 60), c.get_rect(), 1, border_radius=12)
        return c

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
            self.topbar("SELECT GAME")
            ui.text(s, "게임을 골라주세요", 34, (32, 96), ui.WHITE, anchor="midleft")
            ui.text(s, f"{self.sel + 1:02d}", 54, (716, 98), ui.GOLD, anchor="midright", en=True, shadow=False, glow=(255, 150, 30))
            ui.text(s, f"/ {len(self.games):02d}", 24, (724, 106), ui.GRAY, anchor="midleft", en=True, shadow=False)
            for i, (g, r) in enumerate(zip(shown, rects)):
                idx = page * PER_PAGE + i
                on = idx == self.sel
                img = self.cached(("card", g.name, r.size), lambda: self.make_card(g, r.size, idx))
                if on:
                    big = self.cached(("cardbig", g.name, r.size),
                                      lambda: pygame.transform.smoothscale(img, (int(r.w * 1.05), int(r.h * 1.05))))
                    rr = big.get_rect(center=(r.centerx, r.centery - 6))
                    gl = self.cached(("halo", rr.size, "sel"), lambda: halo(rr.size, (255, 170, 50), 34, 150)).copy()
                    gl.set_alpha(int(170 + 85 * math.sin(now / 300)))
                    s.blit(gl, gl.get_rect(center=rr.center))
                    s.blit(big, rr)
                    pygame.draw.rect(s, ui.GOLD, rr, 2, border_radius=13)
                    ui.sheen(s, rr, (now % 2600) / 700, alpha=34)
                    tag = pygame.Rect(rr.right - 92, rr.y + 12, 80, 28)
                    pygame.draw.rect(s, ui.GOLD, tag, border_radius=5)
                    ui.text(s, "PLAY", 20, (tag.x + 12, tag.centery + 1), ui.INK, anchor="midleft", en=True, spacing=3, shadow=False)
                    pygame.draw.polygon(s, ui.INK, [(tag.right - 20, tag.y + 8), (tag.right - 20, tag.bottom - 8), (tag.right - 10, tag.centery)])
                else:
                    s.blit(img, r)
                    veil = self.cached(("veil", r.size), lambda: round_corners(pygame.Surface(r.size), 12))
                    veil.set_alpha(120)
                    s.blit(veil, r)
            pages = (len(self.games) - 1) // PER_PAGE + 1
            for p in range(pages if pages > 1 else 0):
                pygame.draw.circle(s, ui.GOLD if p == page else LINE, (400 - (pages - 1) * 9 + p * 18, 540), 4)
            ui.hints(s, [("<  >", "선택"), ("ENTER", "시작"), ("ESC", "처음으로")])
            if now < self.toast[1]:
                ui.pill(s, self.toast[0], (400, 150), 20, bg=(170, 36, 50, 235))
            self.frame()

    # ---------- 게임 실행 ----------

    def game(self):
        g = self.games[self.sel]
        if self.pending is None:
            self.pending = self.store.draw()  # 결과는 게임 시작 전에 확률표로 결정
        prize = self.pending
        ui.fade(self.screen, self.clock)
        try:
            args = (self.screen, prize != LOSE)
            if len(inspect.signature(g.mod.play).parameters) >= 3:  # 경품 이름까지 받는 게임
                args += (prize,)
            done = bool(g.mod.play(*args))
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

    def make_ticket(self, prize, code):
        t = tier_of(prize)
        c = t["c"]
        w, h, split = 640, 236, 410
        s = pygame.Surface((w, h), pygame.SRCALPHA)
        ui.cut_panel(s, (0, 0, w, h), 22, (12, 14, 28, 246), border=(*c, 255))
        s.blit(ui.gradient((5, h - 46), tuple(min(255, v + 80) for v in c), c), (1, 23))
        ui.text(s, "DISCOUNT COUPON", 17, (34, 36), ui.GRAY, anchor="midleft", en=True, spacing=6, shadow=False)
        ui.text(s, t["name"].rstrip("!"), 17, (split - 24, 36), c, anchor="midright", en=True, spacing=4, shadow=False)
        pygame.draw.line(s, LINE, (34, 58), (split - 24, 58))
        size = 54 if len(prize) <= 8 else 42
        ui.text(s, prize, size, (12, 124), ui.WHITE, anchor="midleft", metal=((255, 255, 255), tuple(min(255, v + 90) for v in c)),
                glow=c, shadow=False)
        ui.text(s, f"{TITLE}  ·  1회 사용  ·  스태프 확인 후 할인", 14, (34, 196), ui.GRAY, anchor="midleft", bold=False, shadow=False)
        for y in range(20, h - 20, 12):  # 절취선
            pygame.draw.line(s, (*c, 150), (split, y), (split, y + 5))
        cx = (w + split) // 2
        ui.text(s, "CODE", 17, (cx, 44), ui.GRAY, en=True, spacing=8, shadow=False)
        ui.text(s, code, 54, (cx, 112), ui.WHITE, en=True, spacing=5, metal=(ui.GOLD_TOP, ui.GOLD_BOT), glow=(255, 150, 30), shadow=False)
        rng = random.Random(code)  # 장식용 바코드
        x = cx - 80
        while x < cx + 80:
            bw = rng.choice((1, 1, 2, 3))
            pygame.draw.rect(s, (200, 206, 226), (x, 170, bw, 30))
            x += bw + rng.choice((1, 2, 2, 3))
        return s

    def make_stamp(self):
        img = ui.render("사용 완료", 52, ui.RED, shadow=False)
        st = pygame.Surface((img.get_width() + 20, img.get_height() + 4), pygame.SRCALPHA)
        st.fill((12, 14, 28, 210))
        pygame.draw.rect(st, ui.RED, st.get_rect(), 4, border_radius=6)
        st.blit(img, img.get_rect(center=st.get_rect().center))
        return pygame.transform.rotozoom(st, 12, 1)

    def result(self):
        prize, code = self.last
        win = code is not None
        t = tier_of(prize)
        tier, c = ui.TIERS.index(t), t["c"]
        t0 = pygame.time.get_ticks()
        fx, fw = ui.Particles(), ui.Fireworks()
        ticket = self.make_ticket(prize, code) if win else None
        colors = [c, tuple(min(255, v + 70) for v in c), (255, 255, 255), (255, 205, 60)]
        redeemed = False
        sfx.play("jackpot" if tier == ui.TOP_TIER else "win" if win else "lose")
        if win:
            fx.burst((400, 300), 60 + 30 * tier, colors, speed=13)
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
            self.back.draw(s, now, tint=c if win else None)
            if win:
                self.topbar("YOU WIN")
                ui.rays(s, (400, 310), 460, c, now / 2200, alpha=14 + 5 * tier)
                if tier >= 2 and el < 12_000 and random.random() < 0.012 * tier:
                    fw.launch(1, colors, area=(60, 740, 70, 200))
                fw.update_draw(s)
                ui.text(s, t["name"].rstrip("!"), 28, (400, 84), c, en=True, spacing=14, shadow=False, glow=c,
                        alpha=int(255 * ui.clamp(el / 300)))
                head = "대박 터졌다!" if tier == ui.TOP_TIER else "축하합니다!"
                ui.text(s, head, 50, (400, 132), ui.WHITE, metal=(ui.GOLD_TOP, ui.GOLD_BOT), glow=(255, 150, 30), shadow=False,
                        scale=max(0.01, ui.out_back(el / 350)))
                k = ui.out_back((el - 150) / 450)
                if k > 0.02:
                    g = self.cached(("halo", ticket.get_size(), c), lambda: halo(ticket.get_size(), c, 44, 150)).copy()
                    g.set_alpha(int(ui.clamp(k) * (190 + 60 * math.sin(now / 350))))
                    s.blit(g, g.get_rect(center=(400, 302)))
                    img = ticket if el > 650 else pygame.transform.rotozoom(ticket, 0, k)
                    tr = img.get_rect(center=(400, 302))
                    s.blit(img, tr)
                    if el > 900:
                        ui.sheen(s, tr, ((el - 900) % 3000) / 800, alpha=26)
                    if redeemed:
                        st = self.cached("stamp", self.make_stamp)
                        s.blit(st, st.get_rect(center=(400, 302)))
                ui.text(s, "스태프에게 이 화면을 보여주세요", 24, (400, 462), ui.WHITE, alpha=int(255 * ui.clamp((el - 500) / 300)))
            else:
                self.topbar("RESULT")
                veil = pygame.Surface((ui.W, ui.H))
                veil.set_alpha(90)
                s.blit(veil, (0, 0))
                ui.text(s, "NO LUCK THIS TIME", 24, (400, 150), ui.GRAY, en=True, spacing=14, shadow=False)
                k = max(0.01, ui.out_back(el / 400))
                img = ui.render("꽝", 210, metal=((226, 232, 250), (92, 104, 150)), glow=(50, 70, 160), shadow=False)
                img = pygame.transform.rotozoom(img, 5 * math.sin(now / 260) * max(0.0, 1 - el / 2500), k)
                s.blit(img, img.get_rect(center=(400, 276)))
                ui.flare(s, (400, 384), 420, (150, 165, 220), 170)
                ui.text(s, "아쉽지만 다음 기회에!", 28, (400, 426), ui.WHITE, bold=False)
            fx.update_draw(s)
            if el > RESULT_LOCK_MS:
                ui.hints(s, [("ANY KEY", "처음으로")], y=540)
            pygame.draw.rect(s, LINE, (0, 596, ui.W, 4))
            pygame.draw.rect(s, c if win else ui.GRAY, (0, 596, ui.W * (1 - el / timeout), 4))
            self.frame()

    # ---------- 관리자 ----------

    def admin_bg(self, now):
        self.back.draw(self.screen, now)
        veil = pygame.Surface((ui.W, ui.H))
        veil.set_alpha(120)
        self.screen.blit(veil, (0, 0))

    def admin(self):
        if not self.admin_pin():
            return "attract"
        code, msg, color = "", "쿠폰 코드를 입력하고 Enter", ui.GRAY
        while True:
            now = pygame.time.get_ticks()
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
            self.admin_bg(now)
            self.topbar("ADMIN")
            st = self.store.stats()
            total = st["total"]
            ui.text(s, "관리자", 32, (32, 88), ui.WHITE, anchor="midleft")
            ui.text(s, f"{total}", 44, (724, 88), ui.GOLD, anchor="midright", en=True, shadow=False)
            ui.text(s, "판", 18, (732, 94), ui.GRAY, anchor="midleft", shadow=False)
            cols = [(54, "경품", "midleft"), (366, "목표", "midright"), (456, "실제", "midright"), (546, "나온 수", "midright"),
                    (646, "사용 완료", "midright"), (752, "남은 수량", "midright")]
            ui.cut_panel(s, (32, 116, 736, 236), 14)
            for x, label, anchor in cols:
                ui.text(s, label, 15, (x, 138), ui.GRAY, anchor=anchor, bold=False, shadow=False)
            pygame.draw.line(s, LINE, (48, 154), (752, 154))
            for i, (p, n, used) in enumerate(st["prizes"]):
                y = 178 + i * 36
                tc = tier_of(p.name)["c"] if p.name != LOSE else ui.GRAY
                pygame.draw.rect(s, tc, (42, y - 10, 3, 20))
                real = f"{n / total * 100:.1f}%" if total else "-"
                left = "-" if p.cap is None else str(max(0, p.cap - n))
                vals = [p.name, f"{p.pct}%", real, str(n), "-" if p.name == LOSE else str(used), left]
                for j, ((x, _, anchor), v) in enumerate(zip(cols, vals)):
                    ui.text(s, v, 20 if j == 0 else 24, (x, y), ui.WHITE, anchor=anchor, shadow=False, en=j > 0)
            games_line = "     ".join(f"{g}  {n}판" for g, n in st["games"]) or "아직 기록 없음"
            ui.text(s, games_line, 16, (48, 374), ui.GRAY, anchor="midleft", bold=False, shadow=False)

            ui.cut_panel(s, (32, 400, 736, 138), 14, accent=ui.GOLD)
            ui.text(s, "쿠폰 사용 처리", 18, (48, 424), ui.WHITE, anchor="midleft", shadow=False)
            box = pygame.Rect(48, 448, 290, 66)
            pygame.draw.rect(s, (6, 8, 16), box, border_radius=8)
            pygame.draw.rect(s, ui.GOLD, box, 1, border_radius=8)
            caret = "_" if now // 400 % 2 and len(code) < 6 else ""
            ui.text(s, code + caret, 48, (box.x + 18, box.centery + 2), ui.WHITE, anchor="midleft", en=True, spacing=6, shadow=False)
            ui.text(s, msg, 18, (358, box.centery), color, anchor="midleft", shadow=False)
            ui.hints(s, [("F5", "CSV 내보내기"), ("F10", "프로그램 종료"), ("F11", "전체화면"), ("ESC", "닫기")])
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
            self.admin_bg(now)
            self.topbar("ADMIN")
            dx = 8 * math.sin(now / 25) if now < shake_until else 0
            ui.cut_panel(s, (240 + dx, 196, 320, 200), 16, accent=ui.RED if now < shake_until else ui.GOLD)
            ui.text(s, "ACCESS CODE", 18, (400 + dx, 232), ui.GRAY, en=True, spacing=8, shadow=False)
            ui.text(s, "관리자 PIN", 24, (400 + dx, 266), ui.WHITE)
            slots = max(4, len(typed))
            for i in range(slots):  # 입력 칸
                cx = 400 + dx + (i - (slots - 1) / 2) * 34
                pygame.draw.circle(s, ui.GOLD if i < len(typed) else LINE, (cx, 322), 9, 0 if i < len(typed) else 2)
            ui.hints(s, [("0-9", "입력"), ("ENTER", "확인"), ("ESC", "취소")], y=366)
            self.frame()


def main():
    App(kiosk="--kiosk" in sys.argv).run()
