extends Node
## 런처(키오스크). 대기 화면 → 게임 선택 → 추첨 → 게임 → 결과 → 대기 화면.
##
## 실행: godot --path godot [-- --kiosk]
##   --kiosk : 전체화면 + ESC/창닫기로 종료 불가 (종료는 관리자 화면 F10)
## 키: F1 관리자(PIN, 환경변수 FESTIVAL_PIN / 기본 0000) · F11 전체화면 · 당첨 화면에서 F2 = 그 자리에서 쿠폰 사용 처리
##     터치만 있을 때: 대기 화면 왼쪽 위 로고를 빠르게 5번 누르면 관리자
##
## 개발/테스트용 인자 (전부 `--` 뒤에):
##   --screen=attract|menu|result|pin|admin   그 화면에서 시작 (admin 은 PIN 생략)
##   --force-rank=<0~4>     추첨 대신 그 등급으로 고정 (0 = 꽝)
##   --pick=<번호|폴더명>    --auto 일 때 고를 게임 (기본 0)
##   --auto                 대기 → 메뉴 → 게임 → 결과를 스스로 진행 (Kit.auto)
##   --dry                  기록 파일(user://festival.json)을 건드리지 않음: 가짜 코드, 메모리 안에서만 기록/사용 처리
##                          (--shots 나 --auto 가 있으면 자동으로 켜짐. 그래도 진짜로 기록하려면 --live)
##   --demo                 (dry 전용) 관리자 화면 확인용 가짜 기록 140판. 코드 AAAAAA = 미사용, BBBBBB = 사용됨
##   --dev-games            '_' 로 시작하는 폴더(_template)도 메뉴에 표시
##   --fake-games=<N>       메뉴 배치 확인용으로 가짜 카드 N개 추가
##   --broken-game          일부러 깨진 게임 카드를 하나 추가 (오류가 나도 메뉴로 돌아오는지 확인용)
##   --keys=<초>:<키>;...    그 시각에 입력 흉내. 키 이름(F1, Enter, Escape, Right…), 글자열(0000, AAAAAA), click@x,y, result=<등급>(결과 화면 미리보기)
##                          (--keys 나 --shots 가 있으면 진짜 키보드/마우스 입력은 무시 — 자동 실행 중 사람 손이 닿아도 안 흔들리게)
##                          예) --keys="1:F1;2:0000;2.5:Enter;4:AAAAAA;4.5:Enter;6:F5"

const Backdrop := preload("res://core/launcher/backdrop.gd")
const UI := preload("res://core/launcher/ui.gd")

const W := 1280.0
const H := 720.0
const TITLE := "종 페스티벌"
const BRAND := "JONG FESTIVAL"
const IDLE_MENU := 30.0       # 메뉴에서 입력 없으면 대기 화면으로
const IDLE_ADMIN := 120.0     # 관리자 화면을 열어둔 채 자리를 비우면 닫힘
const RESULT_LOCK := 1.5      # 결과 화면 연타 스킵 방지
const GAME_STALL := 150.0     # 게임 중 이만큼 아무 입력이 없으면(멈춘 게임/떠난 손님) 메뉴로
const COLS := 4
const PER_PAGE := 8
const CARD_HUES := [Color(0.12, 0.3, 0.62), Color(0.42, 0.18, 0.58), Color(0.6, 0.38, 0.1), Color(0.58, 0.13, 0.2), Color(0.08, 0.42, 0.42), Color(0.3, 0.34, 0.5)]

var games: Array = []       # {id, name, tagline, path, thumb}
var sel := 0
var pending := ""           # 뽑아놓고 아직 안 쓴 경품 (게임 중 ESC 로 다시 뽑기 방지)
var last_prize := ""
var last_code := ""
var kiosk := false
var dry := false

var _args := {}
var _pin := "0000"
var _dry_plays: Array = []
var _state := ""
var _t := 0.0
var _idle := 0.0
var _busy := false
var _game: Node
var _game_name := ""

var _back: Node3D
var _ui: CanvasLayer
var _dim: ColorRect
var _holder: Control
var _screen: Control
var _right: Label
var _hints: HBoxContainer
var _top: CanvasLayer
var _fade: ColorRect
var _toast_box: Control

# 화면별 상태
var _tier_hl: Array = []
var _hot := -1
var _cards: Array = []
var _grid: Control
var _page := -1
var _counter: Label
var _dots: Control
var _bar: ColorRect
var _timeout := 9.0
var _ticket: Control
var _redeemed := false
var _typed := ""
var _pin_panel: Panel
var _pin_dots: Control
var _admin_stats: Control
var _code_label: Label
var _msg: Label
var _taps: Array = []
var _fake_only := false   # 자동 실행 중: 흉내 낸 입력만 받음
var _faking := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	kiosk = _args.has("kiosk")
	_fake_only = _args.has("shots") or _args.has("keys")
	dry = (_args.has("dry") or _args.has("shots") or _args.has("auto")) and not _args.has("live")
	var env_pin := OS.get_environment("FESTIVAL_PIN").strip_edges()
	if env_pin != "":
		_pin = env_pin
	if dry:
		_dry_plays = Store.plays.duplicate(true)
		if _args.has("demo"):
			_seed_demo()
		print("[launcher] dry 모드: 기록 파일을 건드리지 않음")
	if kiosk:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_tree().auto_accept_quit = false
	_discover()

	_back = Backdrop.new()
	add_child(_back)
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	_dim = UI.rect(_ui, Rect2(0, 0, W, H), Color(0.01, 0.012, 0.03, 0.0))
	UI.gradient(_ui, Rect2(0, 0, W, 150), [[0.0, Color(0, 0, 0.02, 0.6)], [1.0, Color(0, 0, 0.02, 0.0)]])
	UI.gradient(_ui, Rect2(0, H - 170, W, 170), [[0.0, Color(0, 0, 0.02, 0.0)], [1.0, Color(0, 0, 0.02, 0.7)]])
	_holder = Control.new()
	_holder.size = Vector2(W, H)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_holder)
	UI.text(_ui, BRAND, 28, Vector2(56, 26), Kit.GOLD, true, 6)
	_right = UI.text(_ui, "", 22, Vector2(W - 56, 30), UI.GRAY, true, 5, 1)
	UI.rect(_ui, Rect2(56, 70, W - 112, 1), UI.LINE)
	UI.rect(_ui, Rect2(56, 69, 84, 2), Kit.GOLD)
	_hints = HBoxContainer.new()
	_hints.position = Vector2(0, 668)
	_hints.size = Vector2(W, 34)
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 34)
	_ui.add_child(_hints)

	_top = CanvasLayer.new()
	_top.layer = 60
	add_child(_top)
	_toast_box = Control.new()
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_toast_box)
	_fade = UI.rect(_top, Rect2(0, 0, W, H), Color(0, 0, 0, 1))
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)

	var first: String = _args.get("screen", "attract")
	if first == "result":
		last_prize = _forced() if _forced() != "" else Store.prize_of_rank(1)
		last_code = _record("미리보기", last_prize)
	if first not in ["attract", "menu", "result", "pin", "admin"]:
		first = "attract"
	_goto(first)
	if _args.has("keys"):
		_schedule_keys(_args["keys"])


# ---------- 게임 목록 ----------

func _discover() -> void:
	var found: Array = []
	var hidden: Array = []
	for d in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/game.gd" % d
		if not FileAccess.file_exists(path):
			continue
		var e := {"id": d, "name": d, "tagline": "", "path": path, "thumb": null}
		var script = load(path)  # 게임 하나가 깨져 있어도 부스는 계속 돌아가야 함
		if not (script is Script) or not (script as Script).can_instantiate():
			push_warning("[skip] games/%s/game.gd 를 읽을 수 없음" % d)
			continue
		var consts: Dictionary = (script as Script).get_script_constant_map()
		e["name"] = str(consts.get("NAME", d))
		e["tagline"] = str(consts.get("TAGLINE", ""))
		var thumb := ProjectSettings.globalize_path("res://games/%s/thumb.png" % d)
		if FileAccess.file_exists(thumb):
			var img := Image.load_from_file(thumb)
			if img != null:
				img.generate_mipmaps()
				e["thumb"] = ImageTexture.create_from_image(img)
		if d.begins_with("_"):
			hidden.append(e)
		else:
			found.append(e)
	found.sort_custom(func(a, b): return a["id"] < b["id"])
	if _args.has("dev-games") or found.is_empty():
		if found.is_empty() and not hidden.is_empty() and not _args.has("dev-games"):
			push_warning("games/ 에 게임이 없어서 템플릿을 대신 표시")
		found.append_array(hidden)
	for i in int(_args.get("fake-games", "0")):
		found.append({"id": "fake%d" % i, "name": ["별똥별 잡기", "행운의 문", "스피드 퀴즈", "보물 상자", "풍선 터뜨리기", "카드 뒤집기", "주사위 왕", "미로 탈출"][i % 8], "tagline": "배치 확인용 카드", "path": "res://games/_template/game.gd", "thumb": null})
	if _args.has("broken-game"):
		found.append({"id": "broken", "name": "깨진 게임", "tagline": "오류 처리 확인용", "path": "res://games/_nope/game.gd", "thumb": null})
	games = found


# ---------- 기록 (dry 모드에서는 메모리 안에서만) ----------

func _plays() -> Array:
	return _dry_plays if dry else Store.plays


func _record(game: String, prize: String) -> String:
	if not dry:
		return Store.record(game, prize)
	var code := ""
	if prize != Store.LOSE:
		for i in 6:
			code += Store.ALPHABET[randi() % Store.ALPHABET.length()]
	_dry_plays.append({"ts": Time.get_datetime_string_from_system(), "game": game, "prize": prize, "code": code, "redeemed_at": ""})
	return code


func _redeem(code: String) -> Dictionary:
	if not dry:
		return Store.redeem(code)
	code = code.strip_edges().to_upper()
	for p in _dry_plays:
		if code != "" and p["code"] == code:
			if p["redeemed_at"] != "":
				return {"status": "used", "prize": p["prize"], "at": p["redeemed_at"]}
			p["redeemed_at"] = Time.get_datetime_string_from_system()
			return {"status": "ok", "prize": p["prize"], "at": p["redeemed_at"]}
	return {"status": "none", "prize": "", "at": ""}


func _seed_demo() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var names := ["펀치머신", "룰렛", "승부차기", "두더지 잡기"]
	_dry_plays.append({"ts": "2026-11-12T10:00:00", "game": names[0], "prize": Store.prize_of_rank(2), "code": "AAAAAA", "redeemed_at": ""})
	_dry_plays.append({"ts": "2026-11-12T10:01:00", "game": names[1], "prize": Store.prize_of_rank(1), "code": "BBBBBB", "redeemed_at": "2026-11-12T10:07:42"})
	for i in 138:
		var roll := rng.randf() * 100.0
		var prize: String = Store.LOSE
		for p in Store.PRIZES:
			roll -= p["pct"]
			if roll < 0.0:
				prize = p["name"]
				break
		var code := ""
		if prize != Store.LOSE:
			for j in 6:
				code += Store.ALPHABET[rng.randi() % Store.ALPHABET.length()]
		_dry_plays.append({"ts": "2026-11-12T10:%02d:%02d" % [2 + i / 3, (i * 20) % 60], "game": names[rng.randi() % 4 if rng.randf() < 0.8 else 0], "prize": prize, "code": code,
			"redeemed_at": "2026-11-12T11:00:00" if code != "" and rng.randf() < 0.4 else ""})


func _export_csv() -> String:
	var path := "user://coupons_dry.csv" if dry else "user://coupons.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	var q := func(v) -> String: return "\"" + str(v).replace("\"", "\"\"") + "\""
	var out := "﻿" + "시각,게임,경품,코드,사용시각\r\n"  # BOM: 엑셀에서 한글이 깨지지 않게
	for p in _plays():
		out += ",".join([q.call(p.get("ts", "")), q.call(p.get("game", "")), q.call(p.get("prize", "")), q.call(p.get("code", "")), q.call(p.get("redeemed_at", ""))]) + "\r\n"
	f.store_string(out)
	f.close()
	var real := ProjectSettings.globalize_path(path)
	print("[launcher] CSV 내보냄: ", real)
	return real


func _forced() -> String:
	if _args.has("force-rank"):
		return Store.prize_of_rank(clampi(int(_args["force-rank"]), 0, Kit.TOP_TIER))
	return ""


# ---------- 공통 ----------

func _goto(state: String) -> void:
	_state = state
	_t = 0.0
	_idle = 0.0
	_typed = ""
	var scr := Control.new()
	scr.size = Vector2(W, H)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match state:
		"attract": _build_attract(scr)
		"menu": _build_menu(scr)
		"result": _build_result(scr)
		"pin": _build_pin(scr)
		"admin": _build_admin(scr)
	var old := _screen
	_screen = scr
	_holder.add_child(scr)
	scr.modulate.a = 0.0
	scr.position.y = 14.0
	var tw := scr.create_tween().set_parallel()
	tw.tween_property(scr, "modulate:a", 1.0, 0.4).set_delay(0.12)
	tw.tween_property(scr, "position:y", 0.0, 0.5).set_delay(0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if old != null:
		old.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
		var t2 := old.create_tween()
		t2.tween_property(old, "modulate:a", 0.0, 0.2)
		t2.tween_callback(old.queue_free)


func _set_dim(a: float) -> void:
	create_tween().tween_property(_dim, "color:a", a, 0.6)


func _set_hints(items: Array) -> void:  # [[키, 설명, 눌렀을 때(선택)], ...]
	for c in _hints.get_children():
		c.queue_free()
	for it in items:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _chip_style())
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := Label.new()
		k.text = it[0]
		k.label_settings = UI.settings(19, UI.WHITE, true, 2)
		chip.add_child(k)
		box.add_child(chip)
		var l := Label.new()
		l.text = it[1]
		l.label_settings = UI.settings(18, UI.GRAY, false, 0, true)
		box.add_child(l)
		if it.size() > 2:
			var cb: Callable = it[2]
			box.mouse_filter = Control.MOUSE_FILTER_STOP
			box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			box.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					cb.call())
		_hints.add_child(box)


func _chip_style() -> StyleBoxFlat:
	var sb := UI.flat(Color(1, 1, 1, 0.07), 6, Color(1, 1, 1, 0.28), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 5
	sb.content_margin_bottom = 1
	return sb


func _toast(msg: String, color := Color(0.62, 0.14, 0.2, 0.96)) -> void:
	for c in _toast_box.get_children():
		c.queue_free()
	var p := UI.panel(_toast_box, Rect2(W / 2 - 330, 9, 660, 54), UI.flat(color, 27, Color(1, 1, 1, 0.3), 1))
	UI.text(p, msg, 22, Vector2(330, 12), UI.WHITE, false, 0, 0)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _fade_to(a: float, time := 0.3) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, time)
	await tw.finished


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and kiosk:
		_toast("종료는 관리자 화면(F1)에서 F10")
	elif what == NOTIFICATION_PREDELETE and is_instance_valid(_back) and not _back.is_inside_tree():
		_back.free()  # 게임 도중 종료: 트리에서 빼 둔 무대를 직접 정리


func _key_char(e: InputEventKey) -> String:  # 한/영 상태와 무관하게 키 위치로 읽음
	var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
	if (k >= KEY_A and k <= KEY_Z) or (k >= KEY_0 and k <= KEY_9):
		return char(k)
	if k >= KEY_KP_0 and k <= KEY_KP_9:
		return str(k - KEY_KP_0)
	return ""


func _process(delta: float) -> void:
	_t += delta
	_idle += delta
	if _busy:
		return
	match _state:
		"attract":
			var hot := int(_t / 1.6) % maxi(1, _tier_hl.size())
			if hot != _hot and not _tier_hl.is_empty():
				_hot = hot
				for i in _tier_hl.size():
					if is_instance_valid(_tier_hl[i]):
						(_tier_hl[i] as Control).create_tween().tween_property(_tier_hl[i], "modulate:a", 1.0 if i == hot else 0.0, 0.5)
			if Kit.auto and _t > 1.5:
				_goto("menu")
		"menu":
			if Kit.auto and _t > 1.5:
				sel = _pick_index()
				_start_game()
			elif _idle > IDLE_MENU:
				_goto("attract")
		"result":
			if is_instance_valid(_bar):
				_bar.size.x = W * clampf(1.0 - _t / _timeout, 0.0, 1.0)
			if _t > _timeout:
				_goto("attract")
		"pin", "admin":
			if _idle > IDLE_ADMIN:
				_goto("attract")
		"game":
			if _idle > GAME_STALL and not Kit.auto:
				_toast("입력이 없어서 메뉴로 돌아왔어요")
				_end_game(false)


func _input(e: InputEvent) -> void:
	if _fake_only and not _faking:
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey or e is InputEventMouse or e is InputEventScreenTouch or e is InputEventJoypadButton:
		_idle = 0.0
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.keycode if e.keycode != 0 else e.physical_keycode
		if k == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if _state == "game":
			return
		get_viewport().set_input_as_handled()
		if _busy or k in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
			return
		match _state:
			"attract": _key_attract(k)
			"menu": _key_menu(k)
			"result": _key_result(k)
			"pin": _key_pin(k, e)
			"admin": _key_admin(k, e)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _busy:
		if _state == "attract":
			get_viewport().set_input_as_handled()
			if Rect2(0, 0, 320, 72).has_point(e.position):  # 로고 5번 = 관리자 (키보드 없이)
				var now := Time.get_ticks_msec()
				_taps = _taps.filter(func(t): return now - t < 3000)
				_taps.append(now)
				if _taps.size() >= 5:
					_taps.clear()
					_goto("pin")
				return
			Kit.sfx("click")
			_goto("menu")
		elif _state == "result" and _t > RESULT_LOCK:
			get_viewport().set_input_as_handled()
			_goto("attract")


# ---------- 대기 화면 ----------

func _build_attract(scr: Control) -> void:
	_right.text = "COUPON EVENT"
	_set_hints([])
	_set_dim(0.0)
	_back.set_mode(-1.75)
	_tier_hl.clear()
	_hot = -1
	UI.gradient(scr, Rect2(0, 0, 860, H), [[0.0, Color(0, 0, 0.02, 0.62)], [1.0, Color(0, 0, 0.02, 0.0)]], Vector2(0, 0), Vector2(1, 0))
	UI.text(scr, "MINI GAME ARCADE", 28, Vector2(82, 128), Color(0.56, 0.78, 1.0), true, 12)
	var title := UI.text(scr, TITLE, 132, Vector2(74, 150), Color(1.0, 0.965, 0.9))
	title.label_settings.shadow_size = 2
	title.label_settings.shadow_color = Color(0, 0, 0, 0.45)
	title.label_settings.shadow_offset = Vector2(0, 5)
	UI.rect(scr, Rect2(82, 326, 96, 3), Kit.GOLD)
	UI.text(scr, "게임 한 판, 할인 쿠폰 한 장", 34, Vector2(80, 346), Color(0.9, 0.92, 0.98), false, 0, -1, true)

	var prizes: Array = []
	for p in Store.PRIZES:
		if Store.rank(p["name"]) > 0:
			prizes.append(p["name"])
	prizes.sort_custom(func(a, b): return Store.rank(a) < Store.rank(b))
	var n := prizes.size()
	var gap := 18.0
	var cw := (W - 160.0 - gap * (n - 1)) / maxf(1, n)
	UI.text(scr, "PRIZES", 20, Vector2(82, 428), UI.GRAY, true, 8)
	for i in n:
		var t: Dictionary = Kit.tier(Store.rank(prizes[i]))
		var c: Color = t["color"]
		var r := Rect2(80 + i * (cw + gap), 462, cw, 118)
		var g := UI.glass(scr, r, 14, Color(1, 1, 1, 0.13), 0.6)
		var hl := UI.panel(g, Rect2(Vector2.ZERO, r.size), UI.outline(c, 14, 2))
		hl.modulate.a = 0.0
		_tier_hl.append(hl)
		UI.rect(g, Rect2(22, 22, 4, 30), c)
		UI.text(g, t["name"], 30, Vector2(38, 21), c, true, 4)
		UI.text(g, t["kor"], 17, Vector2(cw - 22, 26), UI.GRAY, false, 0, 1, true)
		UI.text(g, prizes[i], 25, Vector2(22, 68), UI.WHITE)

	var press := UI.text(scr, "PRESS ANY KEY", 34, Vector2(W / 2, 612), UI.WHITE, true, 12, 0)
	var tw := press.create_tween().set_loops()
	tw.tween_property(press, "modulate:a", 0.35, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(press, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	UI.text(scr, "화면을 터치하거나 아무 키나 누르세요", 19, Vector2(W / 2, 660), UI.GRAY, false, 0, 0, true)


func _key_attract(k: int) -> void:
	if k == KEY_F1:
		_goto("pin")
	elif k == KEY_ESCAPE:
		if not kiosk:
			get_tree().quit()
	else:
		Kit.sfx("click")
		_goto("menu")


# ---------- 게임 선택 ----------

func _build_menu(scr: Control) -> void:
	_right.text = "SELECT GAME"
	_set_dim(0.42)
	_back.set_mode(0.0, Backdrop.WARM, 0.16)
	sel = clampi(sel, 0, maxi(0, games.size() - 1))
	UI.text(scr, "게임을 골라주세요", 42, Vector2(56, 96), UI.WHITE)
	if not pending.is_empty():
		UI.text(scr, "이어서 도전! 아무 게임이나 골라도 결과는 같아요", 19, Vector2(58, 152), UI.GRAY, false, 0, -1, true)
	_counter = UI.text(scr, "", 56, Vector2(W - 124, 92), Kit.GOLD, true, 2, 1)
	UI.text(scr, "/ %02d" % games.size(), 28, Vector2(W - 112, 116), UI.GRAY, true, 2)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_grid)
	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_dots)
	if games.size() > PER_PAGE:
		UI.button(scr, Rect2(8, 372, 40, 72), "<", 30, true, func(): _move(-PER_PAGE))
		UI.button(scr, Rect2(W - 48, 372, 40, 72), ">", 30, true, func(): _move(PER_PAGE))
	_set_hints([["<  >", "선택"], ["ENTER", "시작", _start_game], ["ESC", "처음으로", func(): _goto("attract")]])
	_page = -1
	if games.is_empty():
		UI.text(scr, "games/ 폴더에 게임이 없어요", 30, Vector2(W / 2, 340), UI.GRAY, false, 0, 0)
		return
	_refresh_menu(false)


func _card_rects(count: int) -> Array:
	var big := count <= COLS
	var cw := 300.0 if count <= 3 else 270.0
	var ch := 408.0 if big else 208.0
	var gap := 24.0 if big else 20.0
	var rows := 1 if big else int(ceil(count / float(COLS)))
	var top := 412.0 - (rows * ch + (rows - 1) * gap) / 2.0
	var out: Array = []
	for i in count:
		var row := i / COLS
		var col := i % COLS
		var n := mini(COLS, count - row * COLS)
		var x0 := W / 2 - (n * cw + (n - 1) * gap) / 2.0
		out.append(Rect2(x0 + col * (cw + gap), top + row * (ch + gap), cw, ch))
	return out


func _refresh_menu(animate := true) -> void:
	var page := sel / PER_PAGE
	if page != _page:
		_page = page
		for c in _grid.get_children():
			c.queue_free()
		for c in _dots.get_children():
			c.queue_free()
		_cards.clear()
		var shown := games.slice(page * PER_PAGE, (page + 1) * PER_PAGE)
		var rects := _card_rects(shown.size())
		for i in shown.size():
			_cards.append(_make_card(page * PER_PAGE + i, shown[i], rects[i]))
		var pages := (games.size() - 1) / PER_PAGE + 1
		if pages > 1:
			for p in pages:
				UI.panel(_dots, Rect2(W / 2 - (pages - 1) * 11 + p * 22 - 5, 642, 10, 10), UI.flat(Kit.GOLD if p == page else Color(1, 1, 1, 0.22), 5))
		animate = false
	_counter.text = "%02d" % (sel + 1)
	for card in _cards:
		var on: bool = card.get_meta("index") == sel
		var targets := [[card, "scale", Vector2(1.045, 1.045) if on else Vector2.ONE], [card.get_node("glow"), "modulate:a", 1.0 if on else 0.0],
			[card.get_node("body/veil"), "color:a", 0.0 if on else 0.32], [card.get_node("sel"), "modulate:a", 1.0 if on else 0.0]]
		card.z_index = 1 if on else 0
		if animate:
			var tw: Tween = card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			for t in targets:
				tw.tween_property(t[0], t[1], t[2], 0.22)
		else:
			for t in targets:
				(t[0] as Node).set_indexed(t[1], t[2])


func _make_card(index: int, g: Dictionary, r: Rect2) -> Control:
	var size := r.size
	var card := Control.new()
	card.position = r.position
	card.size = size
	card.pivot_offset = size / 2
	card.set_meta("index", index)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_grid.add_child(card)

	var glow_sb := UI.outline(Color(0, 0, 0, 0), 16, 0)
	glow_sb.shadow_color = Color(1.0, 0.72, 0.3, 0.3)
	glow_sb.shadow_size = 20
	var glow := UI.panel(card, Rect2(Vector2.ZERO, size), glow_sb)
	glow.name = "glow"

	var body := UI.panel(card, Rect2(Vector2.ZERO, size), UI.flat(Color(0.04, 0.045, 0.07), 16))
	body.name = "body"
	body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var hue: Color = CARD_HUES[index % CARD_HUES.size()]
	if g["thumb"] != null:
		var tr := TextureRect.new()
		tr.texture = g["thumb"]
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(tr)
	else:  # 썸네일 없는 게임: 색 그라데이션 + 첫 글자
		UI.gradient(body, Rect2(Vector2.ZERO, size), [[0.0, hue.lightened(0.12)], [0.55, hue.darkened(0.55)], [1.0, Color(0.03, 0.035, 0.06)]], Vector2(0.1, 0), Vector2(0.9, 1))
		if size.y > 300:
			UI.text(body, str(g["name"]).substr(0, 1), int(size.y * 0.42), Vector2(size.x / 2, size.y * 0.06), Color(1, 1, 1, 0.92), false, 0, 0)
			UI.rect(body, Rect2(size.x / 2 - 22, size.y * 0.56, 44, 2), Color(1, 1, 1, 0.5))
		else:
			UI.text(body, str(g["name"]).substr(0, 1), int(size.y * 0.5), Vector2(size.x - 24, size.y * 0.02), Color(1, 1, 1, 0.3), false, 0, 1)
	UI.gradient(body, Rect2(Vector2.ZERO, size), [[0.0, Color(0.02, 0.025, 0.05, 0.35)], [0.22, Color(0.02, 0.025, 0.05, 0.0)], [0.5, Color(0.02, 0.025, 0.05, 0.0)], [0.9, Color(0.02, 0.025, 0.05, 0.94)]])
	UI.text(body, "%02d" % (index + 1), 32, Vector2(22, 16), UI.WHITE, true, 2)
	var big := size.y > 300
	UI.text(body, g["name"], 36 if big else 28, Vector2(22, size.y - (104 if big else 84)), UI.WHITE)
	var tag := UI.text(body, g["tagline"], 19 if big else 17, Vector2(23, size.y - (50 if big else 42)), Color(0.78, 0.81, 0.9), false, 0, -1, true)
	tag.size.x = size.x - 44
	tag.clip_text = true
	var veil := UI.rect(body, Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.03, 0.32))
	veil.name = "veil"

	UI.panel(card, Rect2(Vector2.ZERO, size), UI.outline(Color(1, 1, 1, 0.16), 16, 1))
	var selp := UI.panel(card, Rect2(Vector2.ZERO, size), UI.outline(Kit.GOLD, 16, 2))
	selp.name = "sel"
	var play := UI.panel(selp, Rect2(size.x - 104, 16, 88, 34), UI.flat(Kit.GOLD, 6))
	UI.text(play, "PLAY  >", 22, Vector2(44, 6), UI.INK, true, 3, 0).label_settings.shadow_size = 0

	card.mouse_entered.connect(func():
		if _state == "menu" and sel != index:
			sel = index
			Kit.sfx("move", -8.0)
			_refresh_menu())
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _state == "menu":
			sel = index
			_refresh_menu()
			_start_game())
	return card


func _move(step: int) -> void:
	if games.is_empty():
		return
	if absi(step) == 1:
		sel = posmod(sel + step, games.size())
	else:
		sel = clampi(sel + step, 0, games.size() - 1)
	Kit.sfx("move", -6.0)
	_refresh_menu()


func _key_menu(k: int) -> void:
	match k:
		KEY_LEFT: _move(-1)
		KEY_RIGHT: _move(1)
		KEY_UP: _move(-COLS)
		KEY_DOWN: _move(COLS)
		KEY_PAGEUP: _move(-PER_PAGE)
		KEY_PAGEDOWN: _move(PER_PAGE)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _start_game()
		KEY_ESCAPE: _goto("attract")
		KEY_F1: _goto("pin")


func _pick_index() -> int:
	var pick: String = _args.get("pick", "0")
	for i in games.size():
		if games[i]["id"] == pick:
			return i
	return clampi(int(pick), 0, maxi(0, games.size() - 1))


# ---------- 게임 실행 ----------

func _start_game() -> void:
	if _busy or _state != "menu" or games.is_empty():
		return
	_busy = true
	var g: Dictionary = games[sel]
	Kit.sfx("click")
	if pending.is_empty():  # 결과는 게임 시작 전에 확률표로 결정
		pending = _forced() if _forced() != "" else Store.draw()
	var prize := pending
	await _fade_to(1.0, 0.3)
	var node := _instantiate(g["path"])
	if node == null:
		_busy = false
		_fade_to(0.0, 0.3)
		_toast("게임에 문제가 생겼어요. 다른 게임을 골라주세요")
		return
	var r := Store.rank(prize)
	for kv in [["win", prize != Store.LOSE], ["prize", prize], ["rank", r]]:
		if kv[0] in node:
			node.set(kv[0], kv[1])
	_ui.visible = false
	remove_child(_back)  # 게임의 카메라/환경과 겹치지 않게
	_game = node
	_game_name = g["name"]
	_state = "game"
	_idle = 0.0
	node.connect("finished", _on_game_finished.bind(node))
	add_child(node)
	_busy = false
	_fade_to(0.0, 0.35)


func _instantiate(path: String) -> Node:
	var script = load(path)
	if not (script is Script) or not (script as Script).can_instantiate():
		push_warning("게임을 불러올 수 없음: " + path)
		return null
	var obj = (script as Script).new()
	if not (obj is Node) or not (obj as Node).has_signal("finished"):
		push_warning("게임 형식이 맞지 않음 (Node + finished 신호 필요): " + path)
		if obj is Node:
			(obj as Node).free()
		return null
	return obj


func _on_game_finished(completed, node: Node) -> void:
	if node == _game and _state == "game" and not _busy:
		_end_game.call_deferred(bool(completed))


func _end_game(completed: bool) -> void:
	if _busy or _state != "game":
		return
	_busy = true
	await _fade_to(1.0, 0.3)
	if is_instance_valid(_game):
		if _game.get_parent() == self:
			remove_child(_game)
		_game.queue_free()
	_game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # 게임이 바꿔놓았을 수 있는 것들을 되돌림
	Engine.time_scale = 1.0
	get_tree().paused = false
	add_child(_back)
	move_child(_back, 0)
	_back.cam.make_current()
	_ui.visible = true
	_busy = false
	if completed:
		last_prize = pending
		last_code = _record(_game_name, pending)
		pending = ""
		_goto("result")
	else:  # 중간에 나감: 뽑힌 경품은 다음 판에 그대로 (다시 뽑기 불가)
		_goto("menu")
	_fade_to(0.0, 0.4)


# ---------- 결과 ----------

func _build_result(scr: Control) -> void:
	var win := last_prize != Store.LOSE and last_prize != ""
	var rank := Store.rank(last_prize)
	var t: Dictionary = Kit.tier(rank)
	var c: Color = t["color"]
	_redeemed = false
	_ticket = null
	_set_hints([])
	_timeout = 60.0 if win else 9.0
	UI.rect(scr, Rect2(0, H - 4, W, 4), Color(1, 1, 1, 0.1))
	_bar = UI.rect(scr, Rect2(0, H - 4, W, 4), c if win else UI.GRAY)
	var hint := UI.text(scr, "아무 키나 누르거나 화면을 터치하면 처음으로", 18, Vector2(W / 2, 672), UI.GRAY, false, 0, 0, true)
	hint.modulate.a = 0.0
	hint.create_tween().tween_property(hint, "modulate:a", 1.0, 0.4).set_delay(RESULT_LOCK)
	if not win:
		_right.text = "RESULT"
		_set_dim(0.74)
		_back.set_mode(0.0, Color(0.4, 0.46, 0.7), 0.24)
		Kit.sfx("lose")
		UI.text(scr, "NO LUCK THIS TIME", 30, Vector2(W / 2, 150), UI.GRAY, true, 14, 0)
		var holder := Control.new()
		holder.position = Vector2(W / 2, 350)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scr.add_child(holder)
		var big := UI.text(holder, "꽝", 250, Vector2(0, -170), Color(0.84, 0.87, 0.97), false, 0, 0)
		big.label_settings.shadow_size = 2
		big.label_settings.shadow_color = Color(0.1, 0.14, 0.4, 0.6)
		big.label_settings.shadow_offset = Vector2(0, 7)
		holder.scale = Vector2(0.6, 0.6)
		holder.rotation_degrees = -6.0
		var tw := holder.create_tween().set_parallel()
		tw.tween_property(holder, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(holder, "rotation_degrees", 0.0, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		UI.rect(scr, Rect2(W / 2 - 48, 520, 96, 2), Color(1, 1, 1, 0.35))
		UI.text(scr, "아쉽지만 다음 기회에!", 36, Vector2(W / 2, 544), UI.WHITE, false, 0, 0, true)
		return

	_right.text = "YOU WIN"
	_set_dim(0.4)
	_back.set_mode(0.0, c, 0.2)
	Kit.sfx("jackpot" if rank == Kit.TOP_TIER else "win")

	var embers := CPUParticles2D.new()  # 등급 색 불티가 천천히 떠오름
	embers.position = Vector2(W / 2, H + 10)
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(W / 2, 6)
	embers.amount = 14 + 12 * rank
	embers.lifetime = 7.0
	embers.preprocess = 3.0
	embers.direction = Vector2(0, -1)
	embers.spread = 14.0
	embers.gravity = Vector2(0, -6)
	embers.initial_velocity_min = 50.0
	embers.initial_velocity_max = 120.0
	embers.scale_amount_min = 0.4
	embers.scale_amount_max = 1.3
	var eg := Gradient.new()
	eg.set_color(0, Color(c.lightened(0.4), 0.0))
	eg.add_point(0.15, Color(c.lightened(0.3), 0.8))
	eg.set_color(eg.get_point_count() - 1, Color(c, 0.0))
	embers.color_ramp = eg
	var dot := GradientTexture2D.new()
	dot.gradient = Gradient.new()
	dot.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 8
	dot.height = 8
	embers.texture = dot
	scr.add_child(embers)

	UI.text(scr, t["name"], 40, Vector2(W / 2, 92), c, true, 16, 0)
	UI.text(scr, "대박 터졌다!" if rank == Kit.TOP_TIER else "축하합니다!", 54, Vector2(W / 2, 134), Color(1.0, 0.95, 0.84), false, 0, 0)

	var tw_size := Vector2(940, 300)
	var split := 548.0
	_ticket = Control.new()
	_ticket.position = Vector2(W / 2 - tw_size.x / 2, 228)
	_ticket.size = tw_size
	_ticket.pivot_offset = tw_size / 2
	_ticket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_ticket)
	var halo_sb := UI.outline(Color(0, 0, 0, 0), 22, 0)
	halo_sb.shadow_color = Color(c, 0.38)
	halo_sb.shadow_size = 46
	var halo := UI.panel(_ticket, Rect2(Vector2.ZERO, tw_size), halo_sb)
	var hw := halo.create_tween().set_loops()
	hw.tween_property(halo, "modulate:a", 0.55, 1.2).set_trans(Tween.TRANS_SINE)
	hw.tween_property(halo, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	var body := UI.glass(_ticket, Rect2(Vector2.ZERO, tw_size), 22, Color(c, 0.9), 0.74, Color(0.035, 0.04, 0.075))
	(body.get_meta("border") as Panel).add_theme_stylebox_override("panel", UI.outline(Color(c, 0.95), 22, 2))
	UI.rect(body, Rect2(2, 30, 6, tw_size.y - 60), c)
	UI.text(body, "DISCOUNT COUPON", 24, Vector2(44, 30), UI.GRAY, true, 7)
	UI.text(body, "%s 등급" % t["kor"], 22, Vector2(split - 34, 31), c, false, 1, 1)
	UI.rect(body, Rect2(44, 72, split - 78, 1), UI.LINE)
	var psize := 78
	var pfont := UI.font(false)
	while psize > 36 and pfont.get_string_size(last_prize, HORIZONTAL_ALIGNMENT_LEFT, -1, psize).x > split - 84:
		psize -= 2
	var pl := UI.text(body, last_prize, psize, Vector2(42, 150 - psize * 0.62), UI.WHITE)
	pl.label_settings.shadow_color = Color(0, 0, 0, 0.6)
	pl.label_settings.shadow_offset = Vector2(0, 4)
	UI.text(body, "%s  ·  1회 사용  ·  스태프 확인 후 할인" % TITLE, 19, Vector2(44, 248), UI.GRAY, false, 0, -1, true)
	var cx := (split + tw_size.x) / 2
	UI.text(body, "COUPON CODE", 22, Vector2(cx, 30), UI.GRAY, true, 8, 0)
	var code := UI.text(body, last_code, 98, Vector2(cx + 3, 86), Color(1.0, 0.91, 0.66), true, 6, 0)
	code.label_settings.shadow_color = Color(0, 0, 0, 0.6)
	code.label_settings.shadow_offset = Vector2(0, 4)
	var deco := Control.new()
	deco.size = tw_size
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(deco)
	var seed_code := last_code
	deco.draw.connect(func():
		var y := 18.0
		while y < tw_size.y - 18:  # 절취선
			deco.draw_line(Vector2(split, y), Vector2(split, y + 7), Color(c, 0.75), 1.5)
			y += 14.0
		var rng := RandomNumberGenerator.new()  # 장식용 바코드
		rng.seed = hash(seed_code)
		var x := cx - 130.0
		while x < cx + 130.0:
			var bw := float([1, 1, 2, 3][rng.randi() % 4])
			deco.draw_rect(Rect2(x, 222, bw, 44), Color(0.82, 0.85, 0.94, 0.85))
			x += bw + float([2, 2, 3, 4][rng.randi() % 4]))
	_ticket.scale = Vector2(0.86, 0.86)
	_ticket.modulate.a = 0.0
	var tt := _ticket.create_tween().set_parallel()
	tt.tween_property(_ticket, "scale", Vector2.ONE, 0.6).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(_ticket, "modulate:a", 1.0, 0.3).set_delay(0.2)

	var show := UI.text(scr, "스태프에게 이 화면을 보여주세요", 34, Vector2(W / 2, 566), UI.WHITE, false, 0, 0)
	show.modulate.a = 0.0
	show.create_tween().tween_property(show, "modulate:a", 1.0, 0.4).set_delay(0.7)
	UI.text(scr, "STAFF  F2  사용 처리", 15, Vector2(W - 56, 680), Color(1, 1, 1, 0.28), false, 1, 1, true)


func _key_result(k: int) -> void:
	if k == KEY_F2:
		if _ticket != null and not _redeemed:  # 스태프가 그 자리에서 사용 처리
			var res := _redeem(last_code)
			if res["status"] != "none":
				_redeemed = true
				_stamp()
	elif _t > RESULT_LOCK:
		_goto("attract")


func _stamp() -> void:
	Kit.sfx("coin")
	var st := Control.new()
	st.position = Vector2(372, 196)  # 왼쪽 칸 아래 — 쿠폰 코드는 가리지 않게
	st.rotation_degrees = -11.0
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticket.add_child(st)
	var p := UI.panel(st, Rect2(-150, -50, 300, 100), UI.flat(Color(0.05, 0.02, 0.04, 0.92), 10, UI.RED, 4))
	UI.panel(p, Rect2(8, 8, 284, 84), UI.outline(Color(UI.RED, 0.6), 5, 1))
	UI.text(p, "사용 완료", 52, Vector2(150, 16), UI.RED, false, 5, 0)
	st.scale = Vector2(2.2, 2.2)
	st.modulate.a = 0.0
	var tw := st.create_tween().set_parallel()
	tw.tween_property(st, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(st, "modulate:a", 1.0, 0.12)


# ---------- 관리자: PIN ----------

func _build_pin(scr: Control) -> void:
	_right.text = "ADMIN"
	_set_dim(0.66)
	_back.set_mode(0.0, Backdrop.WARM, 0.22)
	_set_hints([["0-9", "입력"], ["ENTER", "확인", _pin_submit], ["ESC", "취소", func(): _goto("attract")]])
	_pin_panel = UI.glass(scr, Rect2(W / 2 - 210, 104, 420, 536), 20, Color(Kit.GOLD, 0.6), 0.7)
	UI.text(_pin_panel, "ACCESS CODE", 22, Vector2(210, 34), UI.GRAY, true, 9, 0)
	UI.text(_pin_panel, "관리자 PIN", 32, Vector2(210, 66), UI.WHITE, false, 0, 0)
	_pin_dots = Control.new()
	_pin_dots.position = Vector2(210, 150)
	_pin_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_panel.add_child(_pin_dots)
	_pin_dots.draw.connect(func():
		var slots := maxi(4, _typed.length())
		for i in slots:
			var x := (i - (slots - 1) / 2.0) * 38.0
			if i < _typed.length():
				_pin_dots.draw_circle(Vector2(x, 0), 10, Kit.GOLD)
			else:
				_pin_dots.draw_arc(Vector2(x, 0), 9, 0, TAU, 32, Color(1, 1, 1, 0.3), 2.0, true))
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "DEL", "0", "OK"]
	for i in keys.size():
		var key: String = keys[i]
		var r := Rect2(48 + (i % 3) * 112, 200 + (i / 3) * 76, 100, 64)
		var cb := func():
			if key == "DEL":
				_typed = _typed.left(-1)
			elif key == "OK":
				_pin_submit()
				return
			elif _typed.length() < 8:
				_typed += key
			Kit.sfx("tick", -8.0)
			_pin_dots.queue_redraw()
		var b := UI.button(_pin_panel, r, key, 30 if key.length() == 1 else 22, true, cb)
		if key == "OK":
			b.add_theme_stylebox_override("normal", UI.flat(Color(Kit.GOLD, 0.16), 8, Color(Kit.GOLD, 0.7), 1))


func _pin_submit() -> void:
	if _state != "pin":
		return
	if _typed == _pin:
		Kit.sfx("click")
		_goto("admin")
		return
	_typed = ""
	_pin_dots.queue_redraw()
	Kit.sfx("error")
	var b: Panel = _pin_panel.get_meta("border")
	b.add_theme_stylebox_override("panel", UI.outline(UI.RED, 20, 2))
	var x0 := W / 2 - 210
	var tw := _pin_panel.create_tween()
	for i in 6:
		tw.tween_property(_pin_panel, "position:x", x0 + (10.0 if i % 2 == 0 else -10.0) * (1.0 - i / 6.0), 0.05)
	tw.tween_property(_pin_panel, "position:x", x0, 0.05)
	tw.tween_callback(func(): b.add_theme_stylebox_override("panel", UI.outline(Color(Kit.GOLD, 0.6), 20, 1)))


func _key_pin(k: int, e: InputEventKey) -> void:
	if k == KEY_ESCAPE:
		_goto("attract")
	elif k == KEY_BACKSPACE:
		_typed = _typed.left(-1)
	elif k in [KEY_ENTER, KEY_KP_ENTER]:
		_pin_submit()
		return
	else:
		var ch := _key_char(e)
		if ch != "" and ch.is_valid_int() and _typed.length() < 8:
			_typed += ch
			Kit.sfx("tick", -8.0)
	if is_instance_valid(_pin_dots):
		_pin_dots.queue_redraw()


# ---------- 관리자 ----------

func _build_admin(scr: Control) -> void:
	_right.text = "ADMIN"
	_set_dim(0.7)
	_back.set_mode(0.0, Backdrop.WARM, 0.22)
	_set_hints([["F5", "CSV 내보내기", _admin_export], ["F10", "프로그램 종료", func(): get_tree().quit()], ["F11", "전체화면", _toggle_fullscreen], ["ESC", "닫기", func(): _goto("attract")]])
	UI.text(scr, "관리자", 40, Vector2(56, 90), UI.WHITE)
	if dry:
		UI.text(scr, "DRY RUN  ·  기록 파일에 저장되지 않음", 17, Vector2(190, 110), UI.RED, false, 1, -1, true)
	UI.glass(scr, Rect2(56, 158, 790, 300), 16)
	UI.glass(scr, Rect2(866, 158, 358, 300), 16)
	_admin_stats = Control.new()
	_admin_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_admin_stats)
	_admin_refresh()

	var box := UI.glass(scr, Rect2(56, 474, 1168, 180), 16, Color(Kit.GOLD, 0.55))
	UI.text(box, "쿠폰 사용 처리", 20, Vector2(24, 14), UI.WHITE)
	UI.panel(box, Rect2(24, 50, 300, 78), UI.flat(Color(0.01, 0.012, 0.025, 0.85), 10, Color(Kit.GOLD, 0.8), 1))
	_code_label = UI.text(box, "", 60, Vector2(174, 56), UI.WHITE, true, 9, 0)
	_msg = UI.text(box, "쿠폰 코드를 입력하고 Enter", 20, Vector2(24, 140), UI.GRAY, false, 0, -1, true)
	for i in Store.ALPHABET.length():  # 터치/마우스용 글자판
		var ch: String = Store.ALPHABET[i]
		UI.button(box, Rect2(360 + (i % 16) * 49, 22 + (i / 16) * 50, 45, 44), ch, 24, true, func(): _admin_type(ch))
	UI.button(box, Rect2(360 + 12 * 49, 124, 94, 40), "지우기", 18, false, func(): _admin_type("<"))
	var ok := UI.button(box, Rect2(360 + 14 * 49, 124, 94, 40), "확인", 18, false, _admin_submit)
	ok.add_theme_stylebox_override("normal", UI.flat(Color(Kit.GOLD, 0.16), 8, Color(Kit.GOLD, 0.7), 1))
	_admin_type("")


func _admin_refresh() -> void:
	for c in _admin_stats.get_children():
		c.queue_free()
	var s := _admin_stats
	var plays := _plays()
	var total := plays.size()
	var tl := UI.text(s, str(total), 64, Vector2(W - 96, 84), Kit.GOLD, true, 2, 1)
	UI.text(s, "판", 24, Vector2(W - 86, 114), UI.GRAY)
	UI.text(s, "TOTAL PLAYS", 18, Vector2(W - 112 - tl.get_minimum_size().x, 120), UI.GRAY, true, 5, 1)

	var cols := [[92.0, "경품", -1], [470.0, "목표", 1], [560.0, "실제", 1], [650.0, "나온 수", 1], [740.0, "사용 완료", 1], [826.0, "남은 수량", 1]]
	for c in cols:
		UI.text(s, c[1], 17, Vector2(c[0], 172), UI.GRAY, false, 0, c[2], true)
	UI.rect(s, Rect2(76, 204, 750, 1), UI.LINE)
	for i in Store.PRIZES.size():
		var p: Dictionary = Store.PRIZES[i]
		var name: String = p["name"]
		var mine := plays.filter(func(x): return x.get("prize", "") == name)
		var n := mine.size()
		var used := mine.filter(func(x): return str(x.get("redeemed_at", "")) != "").size()
		var y := 214.0 + i * 47.0
		var lose := name == Store.LOSE
		UI.rect(s, Rect2(76, y + 9, 4, 24), UI.GRAY if lose else Kit.tier(Store.rank(name))["color"])
		UI.text(s, name, 23, Vector2(cols[0][0], y + 5), UI.WHITE)
		var vals := ["%s%%" % str(p["pct"]), ("%.1f%%" % (n * 100.0 / total)) if total > 0 else "-", str(n), "-" if lose else str(used),
			"-" if int(p["cap"]) < 0 else str(maxi(0, int(p["cap"]) - n))]
		for j in vals.size():
			UI.text(s, vals[j], 30, Vector2(cols[j + 1][0], y + 4), UI.WHITE if j != 1 else Color(0.8, 0.9, 1.0), true, 1, 1)
		if i < Store.PRIZES.size() - 1:
			UI.rect(s, Rect2(76, y + 44, 750, 1), Color(1, 1, 1, 0.06))

	UI.text(s, "게임별 플레이", 17, Vector2(886, 172), UI.GRAY, false, 0, -1, true)
	UI.rect(s, Rect2(886, 204, 318, 1), UI.LINE)
	var per := {}
	for x in plays:
		var gname := str(x.get("game", "?"))
		per[gname] = int(per.get(gname, 0)) + 1
	var names := per.keys()
	names.sort_custom(func(a, b): return per[a] > per[b])
	if names.is_empty():
		UI.text(s, "아직 기록 없음", 20, Vector2(886, 222), UI.GRAY, false, 0, -1, true)
	var top := int(per[names[0]]) if not names.is_empty() else 1
	for i in mini(names.size(), 6):
		var y := 216.0 + i * 40.0
		if i == 5 and names.size() > 6:
			UI.text(s, "외 %d개 게임" % (names.size() - 5), 19, Vector2(886, y + 4), UI.GRAY, false, 0, -1, true)
			break
		UI.text(s, names[i], 21, Vector2(886, y + 2), UI.WHITE)
		UI.text(s, str(per[names[i]]), 28, Vector2(1204, y), UI.WHITE, true, 1, 1)
		UI.rect(s, Rect2(886, y + 33, 318, 2), Color(1, 1, 1, 0.07))
		UI.rect(s, Rect2(886, y + 33, 318.0 * int(per[names[i]]) / top, 2), Color(Kit.GOLD, 0.8))


func _admin_type(ch: String) -> void:
	if ch == "<":
		_typed = _typed.left(-1)
	elif ch != "" and _typed.length() < 6:
		_typed += ch
	if ch != "":
		Kit.sfx("tick", -8.0)
	_code_label.text = _typed if _typed != "" else "------"
	_code_label.label_settings.font_color = UI.WHITE if _typed != "" else Color(1, 1, 1, 0.16)


func _admin_submit() -> void:
	if _typed == "":
		return
	var code := _typed
	var res := _redeem(code)
	var at := str(res["at"]).replace("T", " ")
	match res["status"]:
		"ok": _admin_msg("완료!  %s 사용 처리  —  %s" % [code, res["prize"]], UI.MINT)
		"used": _admin_msg("이미 사용된 쿠폰  %s  (%s)  —  %s" % [code, at, res["prize"]], UI.RED)
		_: _admin_msg("없는 코드  %s" % code, UI.RED)
	Kit.sfx("coin" if res["status"] == "ok" else "error")
	_typed = ""
	_admin_type("")
	_admin_refresh()


func _admin_msg(s: String, color: Color) -> void:
	_msg.text = s
	_msg.label_settings.font_color = color
	_msg.label_settings.font = UI.font(false)


func _admin_export() -> void:
	var path := _export_csv()
	if path == "":
		_admin_msg("CSV 를 저장하지 못했어요", UI.RED)
	else:
		_admin_msg("내보냄 (%d판):  %s" % [_plays().size(), path], UI.MINT)
		_msg.label_settings.font_size = 16


func _key_admin(k: int, e: InputEventKey) -> void:
	match k:
		KEY_ESCAPE: _goto("attract")
		KEY_F10: get_tree().quit()
		KEY_F5: _admin_export()
		KEY_BACKSPACE: _admin_type("<")
		KEY_ENTER, KEY_KP_ENTER: _admin_submit()
		_:
			var ch := _key_char(e)
			if ch != "":
				_admin_type(ch)


# ---------- 개발용: 입력 흉내 ----------

func _schedule_keys(spec: String) -> void:
	for item in spec.split(";", false):
		var kv := item.split(":", true, 1)
		if kv.size() == 2:
			get_tree().create_timer(float(kv[0])).timeout.connect(_fake_input.bind(kv[1]))


func _fake_input(tok: String) -> void:
	if tok.begins_with("result="):  # 결과 화면 미리보기 (등급 지정)
		last_prize = Store.prize_of_rank(clampi(int(tok.trim_prefix("result=")), 0, Kit.TOP_TIER))
		last_code = _record("미리보기", last_prize)
		_goto("result")
		return
	if tok.begins_with("click@"):
		var xy := tok.trim_prefix("click@").split(",")
		for pressed in [true, false]:
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = pressed
			m.position = Vector2(float(xy[0]), float(xy[1]))
			m.global_position = m.position
			_dispatch(m)
		return
	var code := OS.find_keycode_from_string(tok)
	var codes: Array = [code]
	if code == KEY_NONE or (tok.length() > 1 and tok.is_valid_int()):
		codes = []
		for ch in tok.to_upper():
			codes.append(ch.unicode_at(0))
	for c in codes:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = c
			ev.physical_keycode = c
			ev.pressed = pressed
			_dispatch(ev)


func _dispatch(ev: InputEvent) -> void:
	_faking = true
	get_viewport().push_input(ev)
	_faking = false
