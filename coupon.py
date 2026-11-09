"""경품 추첨 + 쿠폰 발급. 게임은 이 파일을 쓰지 않음 — main.py 만 호출."""
import csv
import secrets
from datetime import datetime
from pathlib import Path

LOG = Path(__file__).with_name("coupons.csv")
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # 0/O/1/I 헷갈림 방지
LOSE = "꽝"
PRIZES = {  # 경품: 확률(%)
    LOSE: 50,
    "대박! 전액 면제": 2,
    "500원 할인": 25,
    "1,000원 할인": 15,
    "2,000원 할인": 8,
}
assert sum(PRIZES.values()) == 100

_rng = secrets.SystemRandom()


def draw() -> str:
    return _rng.choices(list(PRIZES), weights=list(PRIZES.values()))[0]


def issue(game_name: str, prize: str) -> str | None:
    """기록 남기고 쿠폰 코드 반환. 꽝이면 None (기록은 남김 — 통계용)."""
    code = None if prize == LOSE else "".join(secrets.choice(ALPHABET) for _ in range(6))
    new = not LOG.exists()
    with LOG.open("a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["time", "game", "prize", "code"])
        w.writerow([datetime.now().isoformat(timespec="seconds"), game_name, prize, code or ""])
    return code
