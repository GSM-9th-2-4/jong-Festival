extends Node3D
## 페널티킥 — 야간 경기장, 공 뒤 중계 카메라. 스페이스/클릭/터치 한 번이면 슛.
## 결과(골/선방/빗나감, 등급)는 런처가 정해 준 win/rank 그대로 연출만 한다.
## 장면은 stadium.gd(경기장) + keeper.gd(골키퍼) 가 코드로 만든다. 길이: 꽝 약 5초 ~ 크리티컬 약 10초.

const NAME := "페널티킥"
const TAGLINE := "단 한 번의 슛!"

signal finished(completed: bool)

var win := false      ## 당첨 여부
var prize := ""       ## 경품 이름
var rank := 0         ## 등급 0(꽝)~4(크리티컬)

const Stadium := preload("res://games/penalty/stadium.gd")
const Keeper := preload("res://games/penalty/keeper.gd")

const SPOT := Vector3(0, 0.11, 11.0)
const BALL_R := 0.11
const SAVE_RATIO := 0.7
enum { READY, WINDUP, FLY, AFTER }

var _state := READY
var _t := 0.0          # 시작부터
var _ts := 0.0         # 현재 상태에 들어온 뒤
var _done := false
var _slow := 1.0       # 개발용 느린 재생 (-- --slow=0.4)
var _snap_dir := ""    # 개발용: -- --pksnap 이면 주요 순간을 shots/penalty 에 저장
var _snapped := {}
var _ui := 1.0         # 화면 높이 720 기준 글자 배율

var _stadium: Node3D
var _keeper: Node3D
var _env: Environment
var _cam: Camera3D
var _attr: CameraAttributesPractical
var _ball: Node3D
var _ball_mesh: Node3D
var _halo: MeshInstance3D
var _ball_light: OmniLight3D
var _trail: CPUParticles3D
var _glow_mat: StandardMaterial3D

# 슛
var _result := ""      # goal / save / miss
var _target := Vector3.ZERO
var _dur := 0.75
var _arc := 0.3
var _curve := 0.0
var _v := Vector3.ZERO
var _spin_axis := Vector3.RIGHT
var _spin := 0.0
var _net_t := -1.0
var _net_p0 := Vector3.ZERO
var _net_dir := Vector3.BACK
var _res_t := -1.0     # 결과가 뜬 뒤 흐른 시간
var _cele_at := -1.0
var _end_at := 3.0
var _fw_left := 0

# 카메라
var _cam_pos := Vector3(0.8, 1.0, 16.3)
var _cam_look := Vector3(0.1, 1.3, 0)
var _cam_pos_goal := Vector3.ZERO
var _cam_look_goal := Vector3.ZERO
var _fov_goal := 38.0
var _shake := 0.0

# HUD
var _hud: CanvasLayer
var _prompt: Control
var _result_label: Label


func _ready() -> void:
	_slow = float(_debug("slow", "1"))
	if _debug("pksnap", "") != "":
		_snap_dir = ProjectSettings.globalize_path("res://shots/penalty")
		DirAccess.make_dir_recursive_absolute(_snap_dir)
	_ui = get_viewport().get_visible_rect().size.y / 720.0
	var we := Kit.environment("qwantani_night_puresky", {"sky_energy": 0.1, "bg_energy": 1.0, "ambient": 2.6, "fog": 0.001, "glow": 0.55, "exposure": 1.15})
	_env = we.environment
	_env.volumetric_fog_length = 110.0
	_env.volumetric_fog_albedo = Color(0.80, 0.86, 1.0)
	_env.volumetric_fog_anisotropy = 0.35
	_env.volumetric_fog_ambient_inject = 0.0
	_env.glow_hdr_threshold = 1.4
	_env.glow_bloom = 0.0
	_env.set_glow_level(4, 1.0)
	_env.set_glow_level(5, 1.0)
	_env.ssr_enabled = false
	add_child(we)

	_stadium = Stadium.new()
	add_child(_stadium)
	_stadium.build()

	_keeper = Keeper.new()
	add_child(_keeper)
	_keeper.position = Vector3(0, 0, 0.35)
	_keeper.build()

	_build_ball()
	_build_camera()
	_build_hud()
	_cam_pos_goal = _cam_pos
	_cam_look_goal = _cam_look
	get_tree().create_timer(0.25).timeout.connect(func(): Kit.sfx("whistle"))


func _exit_tree() -> void:
	_done = true


# ---------- 만들기 ----------

func _build_ball() -> void:
	_ball = Node3D.new()
	_ball.position = SPOT
	add_child(_ball)
	var src := Kit.model("football")
	var inflated := src.find_child("football_inflated", true, false)
	if inflated != null:
		inflated.get_parent().remove_child(inflated)
		inflated.owner = null
		(inflated as Node3D).position = Vector3.ZERO
		_ball_mesh = inflated
	else:  # 모델이 없으면 흰 공
		var m := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = BALL_R
		sp.height = BALL_R * 2
		m.mesh = sp
		m.material_override = Kit.plain(Color(0.92, 0.92, 0.92), 0.0, 0.4)
		_ball_mesh = m
	src.free()
	_ball.add_child(_ball_mesh)
	_ball_mesh.rotation = Vector3(0.4, 0.9, 0.2)

	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.add_point(0.35, Color(1, 1, 1, 0.35))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_texture = gt
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_glow_mat.billboard_keep_scale = true
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.disable_fog = true

	if rank > 0:  # 등급 색 빛 + 꼬리
		var c: Color = Kit.tier(rank)["color"]
		var hm := _glow_mat.duplicate() as StandardMaterial3D
		hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		hm.albedo_color = Color(c.r, c.g, c.b) * (0.30 + 0.07 * rank)
		_halo = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * (0.42 + 0.07 * rank)
		_halo.mesh = q
		_halo.material_override = hm
		_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_halo.visible = false
		_ball.add_child(_halo)
		_ball_light = OmniLight3D.new()
		_ball_light.light_color = c
		_ball_light.light_energy = 0.0
		_ball_light.omni_range = 3.5 + rank
		_ball.add_child(_ball_light)
		_trail = CPUParticles3D.new()
		var tq := QuadMesh.new()
		tq.material = _glow_mat
		_trail.mesh = tq
		_trail.amount = 50 + 30 * rank
		_trail.lifetime = 0.30 + 0.07 * rank
		_trail.local_coords = false
		_trail.emitting = false
		_trail.gravity = Vector3(0, -0.6, 0)
		_trail.spread = 180.0
		_trail.initial_velocity_min = 0.1
		_trail.initial_velocity_max = 0.5 + 0.2 * rank
		_trail.scale_amount_min = 0.05
		_trail.scale_amount_max = 0.13 + 0.02 * rank
		var cr := Gradient.new()
		cr.set_color(0, Color(c.r, c.g, c.b, 1.0).lerp(Color.WHITE, 0.3) * 1.5)
		cr.add_point(0.25, Color(c.r, c.g, c.b, 0.9) * 1.3)
		cr.set_color(cr.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
		_trail.color_ramp = cr
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ball.add_child(_trail)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.1
	_cam.far = 400.0
	_attr = CameraAttributesPractical.new()
	_attr.dof_blur_far_enabled = true
	_attr.dof_blur_far_distance = 22.0
	_attr.dof_blur_far_transition = 16.0
	_attr.dof_blur_near_enabled = true
	_attr.dof_blur_near_distance = 2.4
	_attr.dof_blur_near_transition = 1.4
	_attr.dof_blur_amount = 0.075
	_cam.attributes = _attr
	add_child(_cam)
	_cam.position = _cam_pos
	_cam.look_at(_cam_look)
	_cam.current = true


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	var vig := ColorRect.new()  # 비네팅
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 d = (UV - 0.5) * vec2(1.0, 0.85); COLOR = vec4(0.0, 0.0, 0.02, smoothstep(0.38, 0.86, length(d)) * 0.62); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	vig.material = sm
	root.add_child(vig)

	# 왼쪽 위 대회 표시
	var bug := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.72)
	sb.border_color = Kit.GOLD
	sb.border_width_left = 4
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bug.add_theme_stylebox_override("panel", sb)
	bug.position = Vector2(36, 30) * _ui
	bug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bug)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	bug.add_child(vb)
	var l1 := Label.new()
	l1.text = "FESTIVAL CUP  ·  PENALTY"
	l1.label_settings = Kit.label_settings(int(20 * _ui), Color(0.72, 0.77, 0.86), true, 0, false)
	vb.add_child(l1)
	var l2 := Label.new()
	l2.text = TAGLINE
	l2.label_settings = Kit.label_settings(int(26 * _ui), Color.WHITE, false, 0, false)
	vb.add_child(l2)

	# 아래 안내
	_prompt = PanelContainer.new()
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color(0.02, 0.03, 0.05, 0.66)
	pb.set_corner_radius_all(28)
	pb.border_color = Color(1, 1, 1, 0.28)
	pb.set_border_width_all(1)
	pb.content_margin_left = 34
	pb.content_margin_right = 34
	pb.content_margin_top = 7
	pb.content_margin_bottom = 7
	_prompt.add_theme_stylebox_override("panel", pb)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pl := Label.new()
	pl.text = "SPACE  ·  화면 터치   →   슛!"
	pl.label_settings = Kit.label_settings(int(24 * _ui), Color.WHITE, false, 0, false)
	_prompt.add_child(pl)
	root.add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_prompt.position.y -= 30 * _ui
	_prompt.modulate.a = 0.0

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.anchor_left = 0.0
	_result_label.anchor_right = 1.0
	_result_label.anchor_top = 0.05
	_result_label.anchor_bottom = 0.37
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label.visible = false
	root.add_child(_result_label)


# ---------- 입력 ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_finish(false)
	elif event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_shoot()


func _finish(completed: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(completed)


func _shoot() -> void:
	if _state != READY or _t < 0.6 or _done:
		return
	_enter(WINDUP)
	create_tween().tween_property(_prompt, "modulate:a", 0.0, 0.12)


func _enter(s: int) -> void:
	_state = s
	_ts = 0.0


# ---------- 슛 계획 (결과는 win 그대로) ----------

func _kick() -> void:
	var side: int = int(_debug("side", str([-1, 0, 1].pick_random())))
	var high := float(_debug("high", str(randf())))
	_keeper.plan(side, high)
	if win:
		_result = "goal"
		var sx := float(-side) if side != 0 else (1.0 if randf() < 0.5 else -1.0)
		_target = Vector3(sx * randf_range(1.5, 3.15), randf_range(0.35, 2.0), 0.0)
	elif _debug("pk", "save" if randf() < SAVE_RATIO else "miss") == "save":
		_result = "save"
		_target = _keeper.reach_point() + Vector3(0, 0, 0.16)
		_target.y = maxf(_target.y, 0.2)
	else:
		_result = "miss"
		if randf() < 0.5:  # 크로스바 위
			_target = Vector3(randf_range(-2.8, 2.8), randf_range(3.0, 3.7), 0.0)
		else:              # 골대 옆
			_target = Vector3((1.0 if randf() < 0.5 else -1.0) * randf_range(4.4, 5.3), randf_range(0.4, 1.7), 0.0)
	_dur = 0.72 + 0.03 * rank
	_arc = randf_range(0.25, 0.5)
	_curve = signf(_target.x + 0.001) * randf_range(0.35, 0.9)
	_spin_axis = Vector3(1.0, randf_range(-0.6, 0.6), 0.0).normalized()
	_spin = 26.0
	Kit.sfx("kick")
	_shake = 0.035
	if _trail != null:
		_trail.emitting = true
		_halo.visible = true
		_ball_light.light_energy = 0.6 + 0.3 * rank
	_enter(FLY)


func _debug(key: String, fallback: String) -> String:  # 개발용: -- --pk=save|miss --side=-1|0|1 --high=0~1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.get_slice("=", 1)
	return fallback


func _snap(tag: String) -> void:
	if _snap_dir == "" or _snapped.has(tag):
		return
	_snapped[tag] = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_snap_dir.path_join("%s_r%d_%s.png" % [tag, rank, _result]))


func _flight(u: float) -> Vector3:
	var s := sin(u * PI)
	return SPOT.lerp(_target, u) + Vector3(_curve * s, _arc * s, 0)


func _warp(tau: float) -> float:  # 공기 저항: 뒤로 갈수록 살짝 느려짐
	return tau * (1.14 - 0.14 * tau)


# ---------- 매 프레임 ----------

func _process(dt: float) -> void:
	if _done:
		return
	dt = minf(dt, 0.05) * _slow  # 멈칫한 프레임이 있어도 연출을 건너뛰지 않게
	_t += dt
	_ts += dt
	match _state:
		READY:
			_keeper.idle(_t)
			if _t > 0.6 and _prompt.modulate.a < 0.01 and _ts > 0.0:
				_prompt.modulate.a = 0.011
				create_tween().tween_property(_prompt, "modulate:a", 1.0, 0.25)
			if _prompt.modulate.a > 0.9:
				_prompt.scale = Vector2.ONE * (1.0 + 0.025 * sin(_t * 5.0))
				_prompt.pivot_offset = _prompt.size / 2
			_cam_pos_goal = Vector3(0.8 - 0.05 * _t, 1.0, 16.3 - 0.12 * _t)
			if _t > 1.1:
				_snap("0ready")
			if Kit.auto and _t > 1.3:
				_shoot()
		WINDUP:
			_keeper.idle(_t)
			_cam_pos_goal = Vector3(0.7, 0.92, 15.9)
			if _ts >= 0.16:
				_kick()
		FLY:
			var tau := minf(_ts / _dur, 1.0)
			var u := _warp(tau)
			_ball.position = _flight(u)
			if tau > 0.55:
				_snap("1fly")
			_ball_mesh.rotate(_spin_axis, _spin * dt)
			_keeper.dive(clampf((_ts - 0.06) / (_dur - 0.06), 0.0, 1.0), 0.0)
			_cam_pos_goal = Vector3(0.5, 1.1, 13.4)
			_cam_look_goal = Vector3(0.1, 1.4, 0).lerp(_ball.position, 0.3)
			_fov_goal = 33.0
			if tau >= 1.0:
				_arrive()
		AFTER:
			_after(dt)
	_update_camera(dt)


func _arrive() -> void:
	# 도착 순간 속도 (비행 곡선의 기울기)
	_v = (_flight(1.0) - _flight(0.98)) / (0.02 * _dur) * 0.86
	_ball.position = _target
	_enter(AFTER)
	if _result == "save":
		Kit.sfx("hit", -2.0)
		Kit.sfx("groan")
		_shake = 0.05
		var sx := signf(_target.x) if absf(_target.x) > 0.6 else (1.0 if randf() < 0.5 else -1.0)
		_v = Vector3(sx * randf_range(2.5, 5.0), randf_range(1.8, 4.2), randf_range(3.0, 6.0))
		_spin = 12.0
		_show_result("SAVED!", Color(0.62, 0.80, 1.0))
		_end_at = 2.8
	elif _result == "miss":
		Kit.sfx("groan")
		_show_result("MISS", Color(1.0, 0.45, 0.45))
		_end_at = 2.8


func _after(dt: float) -> void:
	if _ts > 0.10:
		_snap("2hit")
	if _ts > 0.22:
		_snap("3hit")
	if _ts > 0.7:
		_snap("4result")
	if _cele_at >= 0.0 and _res_t > _cele_at + 1.5:
		_snap("5cele")
	if _cele_at >= 0.0 and _res_t > _end_at - 1.4:
		_snap("6cele")
	# 골키퍼 착지
	_keeper.dive(1.0, clampf(_ts / _keeper.land_time(), 0.0, 1.0))
	# 공
	if _net_t >= 0.0 and _net_t < 0.13:
		_net_t += dt
		var k := sin(minf(_net_t / 0.13, 1.0) * PI * 0.5)
		_ball.position = _net_p0 + _net_dir * 0.5 * k
		_stadium.net_state(0.6 * k, k)
		if _net_t >= 0.13:
			_v = -_net_dir * 1.3 + Vector3(0, -0.4, 0)
			_spin = 5.0
	else:
		_v.y -= 9.8 * dt
		_v -= _v * 0.25 * dt
		var p := _ball.position + _v * dt
		if p.y < BALL_R:
			p.y = BALL_R
			if _v.y < 0.0:
				_v.y = -_v.y * 0.5 if _v.y < -0.8 else 0.0
				_v.x *= 0.86
				_v.z *= 0.86
				_spin *= 0.7
		if _result == "goal":
			var bz: float = Stadium.net_back_z(p.y) + BALL_R + 0.02
			if _net_t < 0.0:
				if p.z <= bz or absf(p.x) >= 3.52 or (p.y >= 2.30 and p.z < 0.0):
					_net_hit(p)
			else:
				_net_t += dt
				var tt := _net_t - 0.13
				_stadium.net_state(0.6 * exp(-3.0 * tt) * cos(8.0 * tt), exp(-1.6 * tt))
				if p.z < bz:
					p.z = bz
					_v.z = maxf(_v.z, 0.0) * 0.3
				if p.z > -0.25 and _v.z > 0.0:
					_v.z *= 0.5
				if absf(p.x) > 3.5:
					p.x = signf(p.x) * 3.5
					_v.x = 0.0
				if p.y > 2.3:
					p.y = 2.3
					_v.y = minf(_v.y, 0.0)
			if _res_t < 0.0 and _ts > 0.35:  # 혹시 그물에 안 닿아도 결과는 띄움
				_net_hit(p)
		else:
			if p.z < -6.6 and p.y < 1.1 and _v.z < 0.0:  # 광고판
				_v.z = -_v.z * 0.35
				p.z = -6.6
			if p.z < -9.6 and _v.z < 0.0:  # 관중석 벽
				_v.z = -_v.z * 0.3
				p.z = -9.6
		_ball.position = p
		_ball_mesh.rotate(_spin_axis, _spin * dt)
		_spin = maxf(_spin - _spin * 0.6 * dt, 0.0)

	if _halo != null:  # 등급 빛은 서서히 꺼짐
		_trail.emitting = _ts < 0.25
		_ball_light.light_energy = maxf(_ball_light.light_energy - dt * 3.0, 0.0)
		var a := maxf(1.0 - _ts * 1.2, 0.0)
		_halo.scale = Vector3.ONE * a
		_halo.visible = a > 0.02

	# 카메라
	if _result == "goal":
		_cam_pos_goal = Vector3(0.2, 1.45, 11.8)
		_cam_look_goal = Vector3(_target.x * 0.25, 2.0, 0)
		_fov_goal = 36.0
	else:
		_cam_pos_goal = Vector3(0.3, 1.25, 12.4)
		_cam_look_goal = Vector3(_target.x * 0.3, 1.5, 0)

	# 결과 뒤 진행
	if _res_t >= 0.0:
		_res_t += dt
		_stadium.crowd_mat.set_shader_parameter("cheer", clampf(_res_t * 3.0, 0.0, 1.0) if win else 0.0)
		if win:
			_stadium.crowd_mat.set_shader_parameter("flash", clampf(1.6 - _res_t * 0.25, 0.3, 1.0) * (1.0 + rank * 0.5))
			if _cele_at < 0.0 and _res_t >= 1.05:
				_cele_at = _res_t
				create_tween().tween_property(_result_label, "modulate:a", 0.0, 0.18)
				var d := Kit.celebrate(rank, prize)
				_end_at = _res_t + d + 0.35
				_start_fireworks(d)
				_shake = 0.03 + 0.012 * rank
			if _cele_at >= 0.0:
				_cam_pos_goal = Vector3(0.0, 1.6, 13.0)
				_cam_look_goal = Vector3(0, 7.6, -8.0)
				_fov_goal = 46.0
		if _res_t >= _end_at:
			_finish(true)


func _net_hit(p: Vector3) -> void:
	_net_t = 0.0
	_net_p0 = p
	_net_dir = _v.normalized() if _v.length() > 0.5 else Vector3.FORWARD
	_stadium.net_hit(p + _net_dir * 0.1, _net_dir)
	Kit.sfx("net")
	Kit.sfx("cheer")
	_shake = 0.06
	_show_result("GOAL!", Color(1.0, 0.90, 0.55))


func _show_result(text: String, color: Color) -> void:
	_res_t = 0.0
	_result_label.text = text
	_result_label.label_settings = Kit.label_settings(int(150 * _ui), color.lerp(Color.WHITE, 0.25), true, int(12 * _ui))
	_result_label.visible = true
	_result_label.modulate.a = 0.0
	_result_label.pivot_offset = _result_label.size / 2
	_result_label.scale = Vector2(1.7, 1.7)
	var tw := create_tween()
	tw.tween_property(_result_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_result_label, "modulate:a", 1.0, 0.1)


func _update_camera(dt: float) -> void:
	_cam_pos = _cam_pos.lerp(_cam_pos_goal, 1.0 - exp(-dt * 3.0))
	_cam_look = _cam_look.lerp(_cam_look_goal, 1.0 - exp(-dt * 3.2))
	_cam.fov = lerpf(_cam.fov, _fov_goal, 1.0 - exp(-dt * 2.5))
	_shake = maxf(_shake - dt * 0.14, 0.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake
	# 손으로 든 카메라처럼 아주 약하게 흔들림
	var breathe := Vector3(sin(_t * 0.9) * 0.012, sin(_t * 1.3 + 1.0) * 0.008, 0)
	_cam.position = _cam_pos + jitter + breathe
	_cam.look_at(_cam_look + jitter * 0.5)
	var d := _cam.position.distance_to(Vector3(0, 1.2, 0))
	_attr.dof_blur_far_distance = d + 7.0


# ---------- 경기장 폭죽 (등급이 높을수록 하늘을 채움) ----------

func _start_fireworks(dur: float) -> void:
	var n: int = [0, 4, 9, 18, 34][rank]
	_fw_left = n
	for i in n:
		var delay := 0.05 + (dur - 0.9) * float(i) / n + randf() * 0.12
		get_tree().create_timer(delay).timeout.connect(_firework)


func _firework() -> void:
	if _done or not is_inside_tree():
		return
	var c: Color = Kit.tier(rank)["color"]
	if rank >= Kit.TOP_TIER:
		c = Color.from_hsv(randf(), 0.75, 1.0)
	elif randf() < 0.3:
		c = c.lerp(Color.WHITE, 0.6)
	var pos := Vector3(randf_range(-36, 36), randf_range(25, 46), randf_range(-52, -36))
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = _glow_mat
	p.mesh = q
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 150
	p.lifetime = 1.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.6
	p.spread = 180.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 15.0
	p.damping_min = 4.0
	p.damping_max = 7.0
	p.gravity = Vector3(0, -2.6, 0)
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.5
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 0.7).lerp(Color.WHITE, 0.25))
	g.add_point(0.12, Color(c.r, c.g, c.b, 1.0) * 1.5)
	g.add_point(0.7, Color(c.r, c.g, c.b, 0.8) * 1.2)
	g.set_color(g.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	var l := OmniLight3D.new()  # 터질 때 경기장이 그 색으로 번쩍
	l.position = pos
	l.light_color = c
	l.light_energy = 5.0
	l.omni_range = 90.0
	l.omni_attenuation = 0.5
	l.light_volumetric_fog_energy = 0.0
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)
	get_tree().create_timer(2.2).timeout.connect(p.queue_free)
