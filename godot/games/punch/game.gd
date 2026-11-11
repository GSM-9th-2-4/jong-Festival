extends Node3D
## 펀치머신: 게이지에 맞춰 한 번 누르면 글러브가 샌드백을 쾅! → 기계의 LED 점수판이 드르륵 올라간다.
## 멈출 듯… 하다가 등급 선(600 / 750 / 900 / 999)을 뚫을 때마다 기계 조명이 그 등급 색으로 바뀐다.
## 결과(등급)는 런처가 정해 준 rank 그대로 — 게이지 타이밍은 타격 세기 연출에만 반영.
## 장면: 밤의 오락실 구석. 전부 코드로 조립 (geo.gd = 둥근 모서리 상자/회전체), 재질·조명은 Kit.

const NAME := "펀치머신"
const TAGLINE := "한 방에 점수 폭발!"

signal finished(completed: bool)

var win := false      ## 당첨 여부
var prize := ""       ## 경품 이름
var rank := 0         ## 등급 0(꽝)~4(크리티컬)

const Geo := preload("res://games/punch/geo.gd")
const Stage := preload("res://games/punch/stage.gd")
const Hud := preload("res://games/punch/hud.gd")

const LINES := [0, 600, 750, 900, 999]   # 등급 선: 이 점수를 넘으면 그 등급
const PUNCH_T := 0.15
const HITSTOP_T := 0.12

var _stage: Stage
var _hud: Hud
var _rng := RandomNumberGenerator.new()

var _state := "ready"
var _el := 0.0            # 현재 상태에서 흐른 시간
var _t := 0.0             # 전체 시간
var _over := false
var _final := 0
var _steps: Array = []
var _value := 0.0
var _start_value := 0.0
var _level := 0
var _power := 0.5
var _maxed := false
var _tick_at := 0.0
var _heart_at := 0.0
var _hold_started := false

# 샌드백 (뒤로 젖혀지는 각도/각속도)
var _theta := 0.0
var _omega := 0.0
var _squash := 0.0

# 카메라
var _cam_pos := Vector3(0.85, 1.25, 3.6)
var _cam_tgt := Vector3(0, 1.25, 0)
var _cam_fov := 38.0
var _shot_pos := Vector3.ZERO
var _shot_tgt := Vector3.ZERO
var _shot_fov := 40.0
var _shot_rate := 2.2
var _shake := 0.0
var _fov_kick := 0.0

# 조명 연출
var _dim := 0.0           # 0 = 평소, 1 = 숨죽임(어둡게)
var _dim_goal := 0.0
var _boost := 0.0         # 등급 돌파 순간 번쩍
var _accent := Color(0.5, 0.72, 1.0)
var _accent_goal := Color(0.5, 0.72, 1.0)
var _led := Color(1.0, 0.24, 0.1)
var _led_goal := Color(1.0, 0.24, 0.1)
var _glove_k := 0.0       # 0 = 대기 자세, 1 = 샌드백에 닿음
var _glove_out := 0.0     # 1 = 화면 밖으로 내림


var _dbg: Array = []


func _dbg_shot(at: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://shots/punch/g_%05.2f.png" % float(at)))


func _ready() -> void:
	_rng.randomize()
	if OS.has_environment("PUNCH_SHOTS"):
		_dbg = Array(OS.get_environment("PUNCH_SHOTS").split(","))
	_stage = Stage.new()
	add_child(_stage)
	_hud = Hud.new()
	add_child(_hud)
	_plan()
	_set_shot(Vector3(0.4, 1.5, 2.5), Vector3(0.0, 1.5, 0.0), 42.0, 2.6)
	_stage.set_display(_text(), _led, 0.0)
	_stage.set_meter(0.0)
	_apply_camera(0.0)


## 최종 점수와 연출 단계. 단계: ["climb", 목표, 초] / ["hold", 초] / ["boom", 등급]
func _plan() -> void:
	var top := Kit.TOP_TIER
	if rank <= 0:
		_final = _rng.randi_range(LINES[1] - 14, LINES[1] - 2) if _rng.randf() < 0.45 else _rng.randi_range(360, LINES[1] - 30)
		_steps = [["climb", _final, 2.7]]
		return
	_final = LINES[top] if rank >= top else _rng.randi_range(LINES[rank] + 8, LINES[rank + 1] - 20)
	for lv in range(1, rank + 1):
		_steps.append(["climb", LINES[lv] - _rng.randi_range(3, 12), 2.3 if lv == 1 else 1.15])
		_steps.append(["hold", 0.95])
		_steps.append(["boom", lv])
	_steps.append(["climb", _final, 1.3])


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		return
	if event.is_action_pressed("ui_cancel"):
		_end(false)
	elif event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_press()


func _press() -> void:
	if _over or _state != "ready" or _t < 0.5:  # 0.5초: 메뉴에서 넘어온 연타 무시
		return
	_go("punch")
	_hud.hide_ready(_power)
	Kit.sfx("swing")


func _go(state: String) -> void:
	_state = state
	_el = 0.0


func _end(completed: bool) -> void:
	if _over:
		return
	_over = true
	finished.emit(completed)


func _set_shot(pos: Vector3, tgt: Vector3, fov: float, rate: float) -> void:
	_shot_pos = pos
	_shot_tgt = tgt
	_shot_fov = fov
	_shot_rate = rate


func _text() -> String:
	if _maxed and int(_t / 0.14) % 4 != 0:
		return "MAX"
	return "%03d" % int(_value)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_t += dt
	_el += dt
	match _state:
		"ready":
			_power = 0.5 + 0.5 * sin(_t * 5.9)
			if Kit.auto and _t >= 1.0:  # 자동 테스트: 1초 뒤 스스로 누름
				_press.call_deferred()
			_hud.set_power(_power)
			_stage.button_pulse(0.5 + 0.5 * sin(_t * 6.0))
		"punch":
			_glove_k = ease(clampf(_el / PUNCH_T, 0.0, 1.0), 2.4)
			if _el >= PUNCH_T:
				_hit()
		"hitstop":
			if _el >= HITSTOP_T:
				_go("count")
				_set_shot(Vector3(0.27, 1.76, 1.72), Vector3(0.0, 1.8, 0.2), 40.0, 1.6)
		"count":
			_count()
		"land":
			pass
	if _state in ["count", "land"]:
		_glove_k = maxf(0.0, _glove_k - dt * 4.0)
		_glove_out = minf(1.0, _glove_out + dt * 1.6)

	if _state != "hitstop":  # 샌드백 진자
		_omega += (-30.0 * sin(_theta) - 1.15 * _omega) * dt
		_theta += _omega * dt
		if _theta > 1.3:  # 뒤쪽 완충 패드에 부딪힘
			_theta = 1.3
			if _omega > 2.0:
				Kit.sfx("pop", -8.0)
				_shake = maxf(_shake, 0.25)
			_omega = -_omega * 0.42
		elif _theta < -0.5:
			_theta = -0.5
			_omega = -_omega * 0.4
		_squash = maxf(0.0, _squash - dt * 7.0)
	_stage.set_bag(_theta, _squash)

	# 조명
	_dim = lerpf(_dim, _dim_goal, 1.0 - exp(-6.0 * dt))
	_boost = maxf(0.0, _boost - dt * 2.2)
	_accent = _accent.lerp(_accent_goal, 1.0 - exp(-10.0 * dt))
	_led = _led.lerp(_led_goal, 1.0 - exp(-10.0 * dt))
	var flicker := 1.0
	if _maxed:
		flicker = 0.55 + 0.45 * float(_rng.randf() > 0.25)
		if _rng.randf() < 0.3:
			_stage.sparks(_stage.display_point(_rng.randf_range(-0.28, 0.28), _rng.randf_range(-0.1, 0.1)), Color(1.0, 0.82, 0.45), 5, 1.8, 0.7)
	_stage.set_lighting(_accent, _level, _dim, _boost, flicker)
	var holding: bool = _state == "count" and not _steps.is_empty() and _steps[0][0] == "hold"
	_stage.set_display(_text(), _led, 0.55 if holding else (0.35 if _maxed else 0.0), _maxed)
	_stage.set_meter(_value / 999.0)
	_hud.set_hold(holding, _t)

	if not _dbg.is_empty() and _t >= float(_dbg[0]):  # 개발용: PUNCH_SHOTS=게임시간,... → shots/punch/g_*.png
		_dbg_shot(_dbg.pop_front())
	_apply_camera(dt)
	_stage.set_glove(_glove_k, _glove_out, _t, _state == "ready")


func _hit() -> void:
	_go("hitstop")
	_glove_k = 1.0
	_shake = 0.7 + 0.6 * _power
	_fov_kick = -3.0
	_omega = 9.5 + 5.5 * _power
	_squash = 1.0
	_boost = 0.6
	Kit.sfx("kick")
	Kit.sfx("hit")
	var p := _stage.hit_point()
	_stage.sparks(p, Color(1.0, 0.8, 0.45), int(34 + 40 * _power), 3.2 + 2.0 * _power, 0.55)
	_stage.sparks(p, Color(1.0, 1.0, 1.0), 14, 1.6, 0.3, 0.03)
	_stage.flash_light(p + Vector3(0, 0, 0.15), Color(1.0, 0.85, 0.6), 5.0, 0.25)
	_hud.flash(0.28, 0.2)


func _count() -> void:
	if _steps.is_empty():
		return
	var step: Array = _steps[0]
	var done := false
	match step[0]:
		"climb":
			var dur: float = step[2]
			var k := clampf(_el / dur, 0.0, 1.0)
			_value = lerpf(_start_value, float(step[1]), 1.0 - pow(1.0 - k, 3.0))
			if _t - _tick_at > 0.055 and _el < dur * 0.92:
				_tick_at = _t
				Kit.sfx("tick", -9.0)
			if dur - _el < 0.9 and _steps.size() > 1 and _t - _heart_at > 0.43:
				_heart_at = _t
				Kit.sfx("heart")
			_dim_goal = 0.5 if (dur - _el < 0.6 and _steps.size() > 1) else 0.0
			done = _el >= dur
		"hold":
			if not _hold_started:
				_hold_started = true
				Kit.sfx("riser", -4.0)
				_set_shot(Vector3(0.16, 1.84, 1.5), Vector3(0.0, 1.85, 0.3), 38.0, 1.3)
			_dim_goal = 1.0
			if _t - _heart_at > 0.43:
				_heart_at = _t
				Kit.sfx("heart")
			done = _el >= float(step[1])
		"boom":
			_boom(int(step[1]))
			done = true
	if done:
		_steps.pop_front()
		_start_value = _value
		_el = 0.0
		_hold_started = false
		if _steps.is_empty():
			_land()


func _boom(lv: int) -> void:  # 등급 선 돌파
	_level = lv
	_value = float(LINES[lv])
	var c: Color = Kit.tier(lv)["color"]
	_accent_goal = c
	_led_goal = c.lerp(Color.WHITE, 0.12)
	_dim_goal = 0.0
	_dim = 0.0
	_boost = 1.0
	_shake = 0.6 + 0.2 * lv
	_fov_kick = 5.0
	_omega += 5.0
	Kit.sfx("boom")
	Kit.sfx("tier%d" % mini(4, lv))
	_set_shot(Vector3(0.27 - 0.1 * lv, 1.74, 1.78 + 0.05 * lv), Vector3(0.0, 1.8, 0.2), 40.0, 3.0)
	var p := _stage.display_point(0, 0)
	_stage.sparks(p, c.lerp(Color.WHITE, 0.2), 60 + 26 * lv, 3.6 + 0.5 * lv, 0.9)
	_stage.sparks(p, Color.WHITE, 24, 2.0, 0.5, 0.02)
	_stage.flash_light(p + Vector3(0, 0, 0.4), c, 7.0, 0.5)
	_hud.flash(0.5, 0.3, c.lerp(Color.WHITE, 0.6))
	_hud.light_tier(lv)
	_hud.stamp(Kit.tier(lv)["name"] + "!".repeat(lv), c)


func _land() -> void:
	_go("land")
	_value = float(_final)
	_dim_goal = 0.0
	if rank > 0:
		_shake = 0.6
		Kit.sfx("coin")
		if rank >= Kit.TOP_TIER:
			_maxed = true
			_stage.crack()
			Kit.sfx("zap")
			_shake = 1.2
			_boost = 1.0
			_hud.flash(0.6, 0.35)
			_stage.sparks(_stage.display_point(0, 0), Color(1.0, 0.9, 0.6), 120, 4.5, 1.1)
	else:
		_dim_goal = 0.55
		_accent_goal = Color(0.3, 0.38, 0.6)
		Kit.sfx("groan")
	_finish()


func _finish() -> void:
	var tree := get_tree()
	await tree.create_timer(0.9 if _maxed else 0.45).timeout
	if _over:
		return
	_set_shot(Vector3(-0.62, 1.3, 3.05), Vector3(0.0, 1.42, 0.0), 40.0, 1.1)
	_hud.result(_final, rank, prize, _maxed, LINES[1] - _final)
	if rank > 0:
		var dur := Kit.celebrate(rank, prize)
		for i in 2 + rank * 3:  # 기계 주변 3D 불꽃 (등급이 높을수록 많이)
			tree.create_timer(0.15 + (dur - 1.0) * i / (2 + rank * 3) + _rng.randf() * 0.2).timeout.connect(_firework)
		await tree.create_timer(dur).timeout
	else:
		Kit.sfx("lose", -4.0)
		await tree.create_timer(2.3).timeout
	_end(true)


func _firework() -> void:
	if _over:
		return
	var c: Color = Kit.tier(rank)["color"] if rank < Kit.TOP_TIER else Color.from_hsv(_rng.randf(), 0.75, 1.0)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var p := Vector3(side * _rng.randf_range(0.75, 2.1), _rng.randf_range(1.5, 2.7), _rng.randf_range(-1.2, 0.5))
	_stage.sparks(p, c, 90, 3.4, 1.3, 0.022, -2.2)
	_stage.sparks(p, Color.WHITE, 20, 1.5, 0.5, 0.03, -1.0)
	_stage.flash_light(p, c, 6.0, 0.6)
	_boost = maxf(_boost, 0.35)


func _apply_camera(dt: float) -> void:
	var k := 1.0 - exp(-_shot_rate * dt)
	_cam_pos = _cam_pos.lerp(_shot_pos, k)
	_cam_tgt = _cam_tgt.lerp(_shot_tgt, k)
	_cam_fov = lerpf(_cam_fov, _shot_fov, k)
	if _state == "land":  # 마지막: 천천히 도는 느낌
		_shot_pos = _shot_pos.rotated(Vector3.UP, -0.035 * dt)
	_shake = maxf(0.0, _shake - dt * 2.6)
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-7.0 * dt))
	var s := _shake * _shake * 0.035
	var off := Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), 0)
	_stage.set_camera(_cam_pos, _cam_tgt, _cam_fov + _fov_kick, off, _rng.randf_range(-s, s) * 0.6)
