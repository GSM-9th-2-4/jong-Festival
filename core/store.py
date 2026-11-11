"""경품 확률표 + 쿠폰 저장소(SQLite). 게임은 이 파일을 쓰지 않음 — 런처(core/app.py)만 호출.
확률/수량을 바꾸려면 PRIZES 만 고치면 됨."""
import csv
import secrets
import sqlite3
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "festival.db"
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # 0/O/1/I 헷갈림 방지
LOSE = "꽝"


@dataclass(frozen=True)
class Prize:
    name: str
    pct: int                # 확률(%)
    cap: int | None = None  # 최대 수량. 다 나가면 그 뒤로는 꽝 처리. None = 무제한


PRIZES = [
    Prize(LOSE, 50),
    Prize("대박! 전액 면제", 2),
    Prize("500원 할인", 25),
    Prize("1,000원 할인", 15),
    Prize("2,000원 할인", 8),
]
assert sum(p.pct for p in PRIZES) == 100, "확률 합이 100이어야 함"

_rng = secrets.SystemRandom()


def rank(prize: str) -> int:
    """등급: 꽝 0, 당첨은 확률 높은 순서로 1(레어) 2(에픽) 3(전설) 4(크리티컬)… 확률이 낮을수록 높은 등급."""
    wins = sorted((p for p in PRIZES if p.name != LOSE), key=lambda p: -p.pct)
    return next((i for i, p in enumerate(wins, 1) if p.name == prize), 0)


def _now():
    return datetime.now().isoformat(timespec="seconds")


class Store:
    def __init__(self, path=DB_PATH):
        self.db = sqlite3.connect(str(path))
        self.db.execute("""CREATE TABLE IF NOT EXISTS plays(
            id INTEGER PRIMARY KEY, ts TEXT NOT NULL, game TEXT NOT NULL, prize TEXT NOT NULL,
            code TEXT UNIQUE, redeemed_at TEXT)""")
        self.db.commit()

    def _count(self, prize):
        return self.db.execute("SELECT COUNT(*) FROM plays WHERE prize=?", (prize,)).fetchone()[0]

    def draw(self) -> str:
        """확률표대로 경품 하나 뽑기. 수량 제한에 걸린 경품은 꽝."""
        p = _rng.choices(PRIZES, weights=[p.pct for p in PRIZES])[0]
        if p.cap is not None and self._count(p.name) >= p.cap:
            return LOSE
        return p.name

    def record(self, game: str, prize: str) -> str | None:
        """플레이 기록. 당첨이면 쿠폰 코드 반환, 꽝이면 None (기록은 남김 — 통계용)."""
        while True:
            code = None if prize == LOSE else "".join(secrets.choice(ALPHABET) for _ in range(6))
            try:
                self.db.execute("INSERT INTO plays(ts, game, prize, code) VALUES(?,?,?,?)", (_now(), game, prize, code))
                self.db.commit()  # 정전 대비 매번 저장
                return code
            except sqlite3.IntegrityError:  # 코드 중복 → 다시 뽑기
                continue

    def redeem(self, code: str):
        """쿠폰 사용 처리. ("ok" | "used" | "none", 경품명, 사용시각) 반환."""
        code = code.strip().upper()
        row = self.db.execute("SELECT prize, redeemed_at FROM plays WHERE code=?", (code,)).fetchone()
        if not row:
            return "none", None, None
        if row[1]:
            return "used", row[0], row[1]
        ts = _now()
        self.db.execute("UPDATE plays SET redeemed_at=? WHERE code=?", (ts, code))
        self.db.commit()
        return "ok", row[0], ts

    def stats(self):
        total = self.db.execute("SELECT COUNT(*) FROM plays").fetchone()[0]
        rows = dict((r[0], (r[1], r[2])) for r in self.db.execute(
            "SELECT prize, COUNT(*), COUNT(redeemed_at) FROM plays GROUP BY prize"))
        games = self.db.execute("SELECT game, COUNT(*) FROM plays GROUP BY game ORDER BY 2 DESC").fetchall()
        return {"total": total, "prizes": [(p, *rows.get(p.name, (0, 0))) for p in PRIZES], "games": games}

    def export_csv(self, path=ROOT / "coupons.csv"):
        with open(path, "w", newline="", encoding="utf-8-sig") as f:  # 엑셀 한글 깨짐 방지
            w = csv.writer(f)
            w.writerow(["time", "game", "prize", "code", "redeemed_at"])
            w.writerows(self.db.execute("SELECT ts, game, prize, code, redeemed_at FROM plays ORDER BY id"))
        return path
