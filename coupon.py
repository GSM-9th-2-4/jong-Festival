"""Coupon issuing. Games never touch this; main.py calls it on a win."""
import csv
import secrets
from datetime import datetime
from pathlib import Path

LOG = Path(__file__).with_name("coupons.csv")
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I confusion


def issue(game_name: str) -> str:
    code = "".join(secrets.choice(ALPHABET) for _ in range(6))
    new = not LOG.exists()
    with LOG.open("a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new:
            w.writerow(["time", "game", "code"])
        w.writerow([datetime.now().isoformat(timespec="seconds"), game_name, code])
    return code
