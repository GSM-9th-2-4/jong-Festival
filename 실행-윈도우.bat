@echo off
rem 윈도우: 이 파일을 더블클릭하면 실행돼요.
cd /d "%~dp0"
where py >nul 2>nul && (py -3 play.py %*) || (python play.py %*)
if errorlevel 1 pause
