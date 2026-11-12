"""종 페스티벌 (3D) 한 번에 실행.

    python3 play.py            # 창 모드
    python3 play.py --kiosk    # 부스용: 전체화면, ESC로 못 끔

처음 실행할 때 알아서 준비함 (두 번째부터는 바로 실행):
  1) Godot 4.7 이 없으면 공식 배포판을 godot/.bin/ 에 내려받음 (설치 프로그램/관리자 권한 필요 없음)
  2) 3D 소재(Poly Haven, CC0)와 사람 모델(Microsoft Rocketbox, MIT)을 godot/assets/ 에 내려받음
맥/윈도우/리눅스 공통. 필요한 것: Python 3, 인터넷(처음 한 번, 약 400MB), curl (맥·윈도우 10+ 기본 포함).
"""
import os
import platform
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT / "godot"
BIN = PROJECT / ".bin"
VERSION = "4.7.2-stable"
BASE = f"https://github.com/godotengine/godot/releases/download/{VERSION}/Godot_v{VERSION}_"
BUILDS = {  # 운영체제: (내려받을 파일, 압축 푼 뒤 실행 파일 위치)
    "Darwin": ("macos.universal.zip", "Godot.app/Contents/MacOS/Godot"),
    "Windows": ("win64.exe.zip", f"Godot_v{VERSION}_win64.exe"),
    "Linux": ("linux.x86_64.zip", f"Godot_v{VERSION}_linux.x86_64"),
}


def say(msg):
    print(f"[종 페스티벌] {msg}", flush=True)


def is_right_version(exe):
    try:
        out = subprocess.run([str(exe), "--version"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return out.strip().startswith("4.7")


def find_godot():
    """이미 받아둔 것 → PATH 에 깔린 것 순서로 찾음. 버전이 4.7 이 아니면 쓰지 않음."""
    name, inner = BUILDS[platform.system()]
    local = BIN / inner
    if local.exists():
        return local
    if os.environ.get("FESTIVAL_FORCE_DOWNLOAD"):  # 테스트용: 깔린 Godot 무시
        return None
    for cand in ("godot", "godot4"):
        exe = shutil.which(cand)
        if exe and is_right_version(exe):
            return Path(exe)
    return None


def download_godot():
    name, inner = BUILDS[platform.system()]
    BIN.mkdir(parents=True, exist_ok=True)
    archive = BIN / name
    say(f"Godot {VERSION} 내려받는 중… (처음 한 번, 80~170MB)")
    subprocess.run(["curl", "-fL", "--progress-bar", "-A", "festival-minigame-dev", "-o", str(archive), BASE + name], check=True)
    say("압축 푸는 중…")
    if platform.system() == "Darwin":  # 앱 묶음의 실행 권한/서명을 그대로 살리려면 ditto
        subprocess.run(["ditto", "-x", "-k", str(archive), str(BIN)], check=True)
    else:
        with zipfile.ZipFile(archive) as z:
            z.extractall(BIN)
        if platform.system() == "Linux":
            (BIN / inner).chmod(0o755)
    archive.unlink()
    return BIN / inner


def fetch_assets():
    for script in (PROJECT / "tools" / "fetch_assets.py", PROJECT / "games" / "penalty" / "fetch_keeper.py"):
        say(f"소재 확인: {script.relative_to(ROOT)}")
        if subprocess.run([sys.executable, str(script)]).returncode != 0:
            say("일부 소재를 못 받았어요. 인터넷 연결을 확인하고 다시 실행하면 이어서 받아요. (없는 소재는 단순한 모양으로 대체돼서 게임은 돌아감)")


def main():
    if platform.system() not in BUILDS:
        sys.exit(f"지원하지 않는 운영체제: {platform.system()}")
    if not shutil.which("curl"):
        sys.exit("curl 이 필요해요. (윈도우 10 이상과 맥에는 기본으로 들어 있어요)")
    godot = find_godot() or download_godot()
    if "--skip-assets" not in sys.argv:
        fetch_assets()
    user_args = [a for a in sys.argv[1:] if a != "--skip-assets"]
    say("실행! (끄려면 창을 닫거나 ESC. 부스 모드는 관리자 화면 F1 → F10)")
    return subprocess.run([str(godot), "--path", str(PROJECT), "--"] + user_args).returncode


if __name__ == "__main__":
    sys.exit(main())
