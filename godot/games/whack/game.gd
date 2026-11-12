extends Node3D
## 두더지 잡기: 15초 동안 망치로 두더지 잡기(점수는 재미용) → "마지막 한 방": 빛나는 가운데 줄 구멍 3개 중 하나 고르기.
## 어느 구멍을 골라도 결과는 런처가 정한 rank 그대로 (꽝 두더지 / 레어 / 에픽 / 전설의 황금 / 크리티컬).
## 조작: 마우스·터치. 키보드는 숫자 1~9 (숫자패드 배치: 789 윗줄, 456 가운데, 123 아랫줄).

const NAME := "두더지 잡기"
const TAGLINE := "잡고 또 잡고, 마지막 한 방!"

signal finished(completed: bool)

var win := false
var prize := ""
var rank := 0

const Mole := preload("res://games/whack/mole.gd")

enum P { INTRO, PLAY, PICK, SUSPENSE, REVEAL, DONE }

const INTRO_T := 2.4
const SUSPENSE_T := 1.7
const SX := 0.47  # 구멍 간격 (m)
const SZ := 0.43
const RIM_Y := 0.068
const DOWN := 0.47  # 숨었을 때 내려가는 깊이
const PICK := [3, 4, 5]
const TITLE := ["꽝 두더지", "레어 두더지", "에픽 두더지", "전설의 황금 두더지", "크리티컬 두더지"]
const PAPER := Color(0.955, 0.94, 0.905)   # 따뜻한 흰색 (순백 대신)
const MALLET_L := 0.5
const MALLET_YAW := 0.5
const CAM_POS := Vector3(0, 1.72, 1.78)
const CAM_LOOK := Vector3(0, 0.0, -0.08)

var play_t := 15.0
var _phase := P.INTRO
var _t := 0.0  # 현재 단계 경과 시간
var _clock := 0.0
var _freeze := 0.0  # 타격 순간 잠깐 멈춤
var _score := 0
var _combo := 0
var _moles: Array = []  # 올라와 있는 두더지 {hole, age, up, hit, k, auto}
var _pool: Array = []  # 구멍마다 보통 두더지 1마리
var _mounds: Array[Node3D] = []
var _next_spawn := 0.0
var _count_shown := -1
var _last_tick := 99
var _picked := -1
var _special: Node3D
var _done := false

var _env: Environment
var _sun: DirectionalLight3D
var _cam: Camera3D
var _cam_attr: CameraAttributesPractical
var _cam_pos := CAM_POS
var _cam_look := CAM_LOOK
var _cam_pos_to := CAM_POS
var _cam_look_to := CAM_LOOK
var _shake := 0.0
var _dim := 0.0
var _dim_to := 0.0
var _sun_base := 3.0

var _mallet: Node3D
var _aim := Vector3(0.3, 0.25, 0.3)
var _aim_to := Vector3(0.3, 0.25, 0.3)
var _swing_t := 9.0
var _mallet_scale := 1.0
var _ptr := Vector2(-1, -1)

var _pick_fx: Array = []  # {light, ring, q, hole}
var _reveal_light: OmniLight3D
var _dust_mesh: SphereMesh
var _dust_mat: StandardMaterial3D
var _star_mesh: ArrayMesh
var _star_mat: StandardMaterial3D
var _suspense_dust: CPUParticles3D

var _hud: CanvasLayer
var _ui: Control
var _ui_scale := 1.0
var _l_score: Label
var _l_combo: Label
var _l_big: Label
var _l_title: Label
var _title_scrim: TextureRect
var _l_sub: Label
var _l_hint: Label
var _hint_box: PanelContainer
var _bar_fill: Panel
var _bar_box: Panel
var _l_time: Label
var _top: Control
var _frames := 0
var _dev_dir := ""  # 개발용: 단계별 스크린샷 저장 폴더 (--whackshots=<폴더>)
var _dev_done := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--whackshots="):
			_dev_dir = a.trim_prefix("--whackshots=")
			DirAccess.make_dir_recursive_absolute(_dev_dir)
	if "--whackquick" in OS.get_cmdline_user_args():  # 개발용: 화면 확인을 빨리 하려고 플레이 시간 단축
		play_t = 4.0
	rank = clampi(rank, 0, Kit.TOP_TIER)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_build_world()
	_build_holes()
	_build_plants()
	_build_mallet()
	_build_fx()
	_build_hud()
	_special = Mole.new()
	add_child(_special)
	_special.build(rank)
	_special.visible = false
	_ptr = get_viewport().get_visible_rect().size * Vector2(0.62, 0.6)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _end(completed: bool) -> void:
	if _done:
		return
	_done = true
	_phase = P.DONE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Kit.auto and _clock > 0.0:
		print("whack: avg fps %.1f" % (_frames / _clock))
	finished.emit(completed)


func _dev_shot(shot: String, phase: int, at: float) -> void:
	if _dev_dir == "" or _phase != phase or _t < at or _dev_done.has(shot):
		return
	_dev_done[shot] = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_dev_dir.path_join(shot + ".png"))


# ---------- 장면 ----------

func _hole_pos(i: int) -> Vector3:
	return Vector3((i % 3 - 1) * SX, 0.0, (i / 3 - 1) * SZ)


func _build_world() -> void:
	var we: WorldEnvironment = Kit.environment("meadow_2", {"sky_energy": 1.0, "rotation": 150.0, "ambient": 0.85, "glow": 0.28, "exposure": 1.0})
	_env = we.environment
	_env.ssr_enabled = false
	_env.ssil_enabled = false
	_env.ssao_intensity = 2.0
	_env.ssao_radius = 0.25
	_env.glow_hdr_threshold = 1.3
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.08
	add_child(we)

	_sun = DirectionalLight3D.new()  # 늦은 오후 햇빛
	_sun.rotation_degrees = Vector3(-36, -58, 0)
	_sun.light_color = Color(1.0, 0.86, 0.68)
	_sun.light_energy = _sun_base
	_sun.light_angular_distance = 1.2
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.4
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 9.0
	_sun.shadow_bias = 0.03
	_sun.shadow_normal_bias = 1.2
	add_child(_sun)

	_cam = Camera3D.new()
	_cam.fov = 36.0
	_cam.near = 0.05
	_cam.far = 200.0
	_cam_attr = CameraAttributesPractical.new()
	_cam_attr.dof_blur_far_enabled = true
	_cam_attr.dof_blur_far_distance = 2.9
	_cam_attr.dof_blur_far_transition = 2.5
	_cam_attr.dof_blur_near_enabled = true
	_cam_attr.dof_blur_near_distance = 0.75
	_cam_attr.dof_blur_near_transition = 0.5
	_cam_attr.dof_blur_amount = 0.09
	_cam.attributes = _cam_attr
	add_child(_cam)
	_cam.position = CAM_POS
	_cam.look_at(CAM_LOOK)
	_cam.make_current()

	# 잔디밭 바닥 (구멍 9개가 뚫린 판)
	var ground := MeshInstance3D.new()
	ground.mesh = _ground_mesh()
	var gm: StandardMaterial3D = Kit.pbr("leafy_grass", Vector3.ONE, Color(0.62, 0.86, 0.42))
	gm.metallic = 0.0
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = gm
	add_child(ground)

	# 뒤쪽 나무 울타리 (배경, 흐리게 보임)
	var wood: StandardMaterial3D = Kit.pbr("wood_planks", Vector3(1.2, 1.2, 1.2), Color(0.95, 0.88, 0.8), true)
	wood.metallic = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var picket := BoxMesh.new()
	picket.size = Vector3(0.11, 1.0, 0.022)
	for i in 60:
		var p := MeshInstance3D.new()
		p.mesh = picket
		p.material_override = wood
		p.position = Vector3(-3.9 + i * 0.132, 0.5 + rng.randf_range(-0.03, 0.02), -3.6 + rng.randf_range(-0.004, 0.004))
		p.rotation.z = rng.randf_range(-0.012, 0.012)
		add_child(p)
	for y in [0.28, 0.78]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(8.2, 0.08, 0.035)
		rail.mesh = rm
		rail.material_override = wood
		rail.position = Vector3(0, y, -3.63)
		add_child(rail)


func _ground_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := SX * 0.5
	var hz := SZ * 0.5
	var add := func(p: Vector2) -> void:
		st.set_normal(Vector3.UP)
		st.set_tangent(Plane(1, 0, 0, 1))
		st.set_uv(p * 1.45)
		st.add_vertex(Vector3(p.x, 0.0, p.y))
	var quad := func(x0: float, x1: float, z0: float, z1: float) -> void:
		for p in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z0), Vector2(x1, z1), Vector2(x0, z1)]:
			add.call(p)
	var angs: Array[float] = []
	for i in 32:
		angs.append(TAU * i / 32.0)
	var ca := atan2(hz, hx)
	angs.append_array([ca, PI - ca, PI + ca, TAU - ca])
	angs.sort()
	for i in 9:
		var c3 := _hole_pos(i)
		var c := Vector2(c3.x, c3.z)
		for k in angs.size():
			var a0: float = angs[k]
			var a1: float = angs[(k + 1) % angs.size()]
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			var o0 := d0 * minf(hx / maxf(absf(d0.x), 1e-5), hz / maxf(absf(d0.y), 1e-5))
			var o1 := d1 * minf(hx / maxf(absf(d1.x), 1e-5), hz / maxf(absf(d1.y), 1e-5))
			for p in [c + d0 * 0.19, c + o0, c + o1, c + d0 * 0.19, c + o1, c + d1 * 0.19]:
				add.call(p)
	var bx := SX * 1.5
	var bz := SZ * 1.5
	var e := 60.0
	quad.call(-e, -bx, -e, e)
	quad.call(bx, e, -e, e)
	quad.call(-bx, bx, -e, -bz)
	quad.call(-bx, bx, bz, e)
	return st.commit()


func _mound_mesh(seed_n: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_n
	noise.frequency = 9.0
	var prof := [Vector2(0.255, -0.02), Vector2(0.24, -0.004), Vector2(0.225, 0.01), Vector2(0.205, 0.028), Vector2(0.185, 0.046),
		Vector2(0.168, 0.06), Vector2(0.154, 0.068), Vector2(0.142, 0.068), Vector2(0.132, 0.06), Vector2(0.125, 0.04),
		Vector2(0.122, 0.0), Vector2(0.12, -0.08), Vector2(0.12, -0.2), Vector2(0.12, -0.4), Vector2(0.12, -0.75)]
	var segs := 56
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in prof.size():
		var pr: Vector2 = prof[j]
		var w := clampf((0.245 - pr.x) / 0.05, 0.0, 1.0) * clampf((pr.y + 0.02) / 0.05, 0.0, 1.0)  # 흙더미 부분만 울퉁불퉁
		for i in segs + 1:
			var ang := TAU * (i % segs) / segs
			var c := cos(ang)
			var s := sin(ang)
			var n := noise.get_noise_2d(c * pr.x, s * pr.x) + 0.5 * noise.get_noise_2d(c * pr.x * 3.0 + 7.0, s * pr.x * 3.0)
			var r := pr.x + n * 0.012 * w + (noise.get_noise_2d(c * 0.4, s * 0.4) * 0.022 if j < 3 else 0.0)
			var y := pr.y + n * 0.016 * w
			var shade := clampf(1.0 + pr.y * 6.0, 0.0, 1.0) if pr.y < 0.04 and j > 7 else 1.0
			st.set_color(Color(shade, shade, shade))
			st.add_vertex(Vector3(r * c, y, r * s))
	for j in prof.size() - 1:
		for i in segs:
			var p := j * (segs + 1) + i
			for q in [p, p + 1, p + segs + 1, p + 1, p + segs + 2, p + segs + 1]:
				st.add_index(q)
	st.generate_normals()
	return st.commit()


func _build_holes() -> void:
	var soil: StandardMaterial3D = Kit.pbr("farm_soil", Vector3(2.6, 2.6, 2.6), Color(0.6, 0.55, 0.5), true)
	soil.metallic = 0.0
	soil.vertex_color_use_as_albedo = true
	soil.cull_mode = BaseMaterial3D.CULL_DISABLED
	soil.normal_scale = 1.4
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# 흙덩이 (작은 알갱이들)
	var clod := SphereMesh.new()
	clod.radius = 1.0
	clod.height = 1.6
	clod.radial_segments = 7
	clod.rings = 4
	var clod_mat: StandardMaterial3D = Kit.pbr("farm_soil", Vector3(30, 30, 30), Color(0.56, 0.5, 0.45), true)
	clod_mat.metallic = 0.0
	clod.material = clod_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = clod
	mm.instance_count = 9 * 46
	var ci := 0
	for i in 9:
		var m := MeshInstance3D.new()
		m.mesh = _mound_mesh(100 + i)
		m.material_override = soil
		m.position = _hole_pos(i)
		m.rotation.y = rng.randf() * TAU
		add_child(m)
		_mounds.append(m)
		var mole := Mole.new()
		add_child(mole)
		mole.build(-1)
		mole.visible = false
		_pool.append(mole)
		for k in 46:
			var r := rng.randf_range(0.14, 0.29)
			var a := rng.randf() * TAU
			var h := clampf(0.068 - maxf(r - 0.154, 0.0) * 0.82, 0.0, 0.068)
			var s := rng.randf_range(0.005, 0.016) * (1.0 if r < 0.24 else 0.7)
			var b := Basis.from_euler(Vector3(rng.randf() * 3.0, rng.randf() * 3.0, rng.randf() * 3.0)).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s))
			mm.set_instance_transform(ci, Transform3D(b, _hole_pos(i) + Vector3(cos(a) * r, h + s * 0.3, sin(a) * r)))
			ci += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func _near_hole(x: float, z: float) -> float:  # 가장 가까운 구멍까지 거리
	var best := 99.0
	for i in 9:
		var h := _hole_pos(i)
		best = minf(best, Vector2(x - h.x, z - h.z).length())
	return best


func _leaf_material(src: BaseMaterial3D, tint: Color) -> ShaderMaterial:
	# Poly Haven 풀 모델은 색 그림에 투명 정보가 없어서(검은 바탕) 어두운 부분을 잘라냄
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
void fragment() {
	vec4 c = textureLod(tex, UV, 0.0);
	float l = max(c.r, max(c.g, c.b));
	if (l < 0.045) { discard; }
	ALBEDO = c.rgb * tint * COLOR.rgb;
	ROUGHNESS = 0.62;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.3, 0.4, 0.08);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", src.albedo_texture)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m


func _build_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# 잔디 포기: 모델에서 모양 여러 개를 꺼내 MultiMesh 로 뿌림
	var model: Node3D = Kit.model("grass_medium_01")
	var parts: Array = []
	_collect_meshes(model, parts)
	var chosen: Array = []
	for want in ["small_a", "small_b", "mid_b", "tall_a", "tall_b", "tall_c", "mid_c"]:
		for mi in parts:
			if want in String(mi.name):
				chosen.append(mi)
	var counts := {"small_a": 1500, "small_b": 1700, "mid_b": 700, "mid_c": 420, "tall_a": 420, "tall_b": 380, "tall_c": 380}
	for mi in chosen:
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null:
				mesh.surface_set_material(s, _leaf_material(mat, Color(1.5, 1.75, 1.2)))
		var count := 400
		var tall := false
		for key in counts:
			if key in String(mi.name):
				count = counts[key]
				tall = key.begins_with("tall")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = count
		var placed := 0
		var tries := 0
		while placed < count and tries < count * 30:
			tries += 1
			# 화면에 보이는 부채꼴 안쪽에 촘촘히, 멀수록 넓게
			var z := 1.25 - pow(rng.randf(), 1.35) * 5.0
			var half := 1.05 + (1.5 - z) * 0.52
			var x := rng.randf_range(-half, half)
			var d := _near_hole(x, z)
			if d < 0.24 or (tall and d < 0.31):
				continue
			var sc := rng.randf_range(0.55, 0.95) * (0.7 if tall else 1.0)
			if d < 0.29:
				sc *= 0.7
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.75, 1.1), sc))
			mm.set_instance_transform(placed, Transform3D(b, Vector3(x, -0.004, z)))
			var g := rng.randf_range(0.7, 1.25)
			mm.set_instance_color(placed, Color(g * rng.randf_range(0.8, 1.15), g, g * rng.randf_range(0.5, 0.9)))
			placed += 1
		mm.visible_instance_count = placed
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if "small_b" in String(mi.name) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
	model.queue_free()

	# 민들레
	var dmodel: Node3D = Kit.model("dandelion_01")
	var dparts: Array = []
	_collect_meshes(dmodel, dparts)
	if dparts.size() > 0:
		for i in 22:
			var src: MeshInstance3D = dparts[rng.randi() % dparts.size()]
			var x := rng.randf_range(-1.7, 1.7)
			var z := rng.randf_range(-2.6, 1.0)
			if _near_hole(x, z) < 0.33:
				continue
			var d := MeshInstance3D.new()
			d.mesh = src.mesh
			var dm := src.mesh.surface_get_material(0) as BaseMaterial3D
			if dm != null:
				src.mesh.surface_set_material(0, _leaf_material(dm, Color(1.25, 1.3, 1.1)))
			d.position = Vector3(x, 0.0, z)
			d.rotation.y = rng.randf() * TAU
			d.scale = Vector3.ONE * rng.randf_range(0.7, 1.0)
			add_child(d)
	dmodel.queue_free()

	# 돌멩이
	var smodel: Node3D = Kit.model("stone_01")
	var sparts: Array = []
	_collect_meshes(smodel, sparts)
	if sparts.size() > 0:
		for p in [Vector3(-1.02, 0.0, 0.2), Vector3(1.0, 0.0, -0.55), Vector3(0.95, 0.0, 0.62), Vector3(-0.9, 0.0, -0.95), Vector3(0.3, 0.0, -1.2)]:
			var s := MeshInstance3D.new()
			s.mesh = (sparts[0] as MeshInstance3D).mesh
			s.position = p + Vector3(0, 0.005, 0)
			s.rotation.y = rng.randf() * TAU
			s.scale = Vector3.ONE * rng.randf_range(0.6, 1.3)
			add_child(s)
	smodel.queue_free()


func _build_mallet() -> void:
	_mallet = Node3D.new()
	add_child(_mallet)
	_mallet_scale = 0.92
	var wood: StandardMaterial3D = Kit.pbr("fine_grained_wood", Vector3(1.0, 1.0, 1.0), Color(1.25, 1.1, 0.95))
	wood.roughness = 0.9
	var wood_dark: StandardMaterial3D = Kit.pbr("fine_grained_wood", Vector3(0.6, 2.0, 1.0), Color(0.95, 0.74, 0.55))
	var leather: StandardMaterial3D = Kit.pbr("leather_red_02", Vector3(2.0, 3.0, 1.0), Color(0.75, 0.7, 0.7))
	var brass := Kit.plain(Color(0.86, 0.66, 0.32), 1.0, 0.32)
	var head := Node3D.new()
	head.position = Vector3(0, 0, -MALLET_L)
	_mallet.add_child(head)
	# 머리: 가운데가 살짝 볼록한 나무통 + 양 끝 쇠테
	var prof := PackedVector2Array()
	prof.append(Vector2(0.0005, -0.092))
	prof.append(Vector2(0.05, -0.092))
	prof.append(Vector2(0.058, -0.086))
	for k in 13:
		var u := -1.0 + 2.0 * k / 12.0
		prof.append(Vector2(0.06 + 0.005 * (1.0 - u * u), u * 0.078))
	prof.append(Vector2(0.058, 0.086))
	prof.append(Vector2(0.05, 0.092))
	prof.append(Vector2(0.0005, 0.092))
	var hm := MeshInstance3D.new()
	hm.mesh = Mole.lathe(prof, 40)
	wood.uv1_scale = Vector3(2.0, 1.0, 1.0)
	hm.material_override = wood
	head.add_child(hm)
	for sy in [-1.0, 1.0]:
		var band := MeshInstance3D.new()
		band.mesh = Mole.lathe(PackedVector2Array([Vector2(0.0605, -0.011), Vector2(0.0635, -0.009), Vector2(0.0635, 0.009), Vector2(0.0605, 0.011)]), 40)
		band.material_override = brass
		band.position.y = sy * 0.062
		head.add_child(band)
	# 손잡이 + 가죽 그립 + 끝 마개
	Mole.rod(_mallet, Vector3(0, 0, -MALLET_L - 0.068), Vector3(0, 0, 0.0), 0.0165, wood_dark, 0.019)
	Mole.rod(_mallet, Vector3(0, 0, -0.2), Vector3(0, 0, 0.012), 0.0215, leather, 0.0225)
	Mole.ball(_mallet, 0.026, Vector3(0, 0, 0.018), brass, Vector3(1, 1, 0.6))
	Mole.ball(_mallet, 0.019, Vector3(0, 0, -MALLET_L - 0.068), brass, Vector3(1, 1, 0.5))


func _build_fx() -> void:
	_dust_mesh = SphereMesh.new()
	_dust_mesh.radius = 0.5
	_dust_mesh.height = 0.8
	_dust_mesh.radial_segments = 6
	_dust_mesh.rings = 3
	_dust_mat = Kit.plain(Color(0.36, 0.26, 0.18), 0.0, 1.0)
	# 별 (평면, 카메라를 향함)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a0 := TAU * i / 10.0 + PI / 2.0
		var a1 := TAU * (i + 1) / 10.0 + PI / 2.0
		var r0 := 0.5 if i % 2 == 0 else 0.22
		var r1 := 0.22 if i % 2 == 0 else 0.5
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * r0, sin(a0) * r0, 0))
		st.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1, 0))
	_star_mesh = st.commit()
	_star_mat = Kit.emissive(Color(1.0, 0.86, 0.3), 2.6)
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_star_mat.billboard_keep_scale = true
	_star_mat.vertex_color_use_as_albedo = true

	# 마지막 한 방: 가운데 줄 구멍의 빛 + 물음표
	for i in PICK:
		var hp := _hole_pos(i)
		var light := OmniLight3D.new()
		light.position = hp + Vector3(0, -0.07, 0)
		light.light_color = Color(1.0, 0.72, 0.25)
		light.omni_range = 0.75
		light.omni_attenuation = 1.3
		light.light_energy = 0.0
		light.visible = false
		add_child(light)
		var top := OmniLight3D.new()
		top.position = hp + Vector3(0, 0.36, 0.08)
		top.light_color = Color(1.0, 0.8, 0.45)
		top.omni_range = 0.6
		top.light_energy = 0.0
		top.visible = false
		add_child(top)
		var q := Label3D.new()
		q.text = "?"
		q.font = Kit.font_en()
		q.font_size = 220
		q.pixel_size = 0.00085
		q.no_depth_test = true
		q.outline_size = 36
		q.modulate = Color(1.0, 0.82, 0.3)
		q.outline_modulate = Color(0.25, 0.1, 0.0, 0.95)
		q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		q.position = hp + Vector3(0, 0.3, 0)
		q.visible = false
		add_child(q)
		_pick_fx.append({"light": light, "top": top, "q": q, "hole": i, "a": 0.0})
	_reveal_light = OmniLight3D.new()
	_reveal_light.omni_range = 1.6
	_reveal_light.light_energy = 0.0
	_reveal_light.shadow_enabled = true
	add_child(_reveal_light)

	_suspense_dust = CPUParticles3D.new()
	_suspense_dust.mesh = _dust_mesh
	_suspense_dust.material_override = _dust_mat
	_suspense_dust.amount = 60
	_suspense_dust.lifetime = 0.55
	_suspense_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_suspense_dust.emission_ring_axis = Vector3.UP
	_suspense_dust.emission_ring_radius = 0.17
	_suspense_dust.emission_ring_inner_radius = 0.12
	_suspense_dust.emission_ring_height = 0.01
	_suspense_dust.direction = Vector3.UP
	_suspense_dust.spread = 50.0
	_suspense_dust.initial_velocity_min = 0.5
	_suspense_dust.initial_velocity_max = 1.3
	_suspense_dust.gravity = Vector3(0, -6.0, 0)
	_suspense_dust.scale_amount_min = 0.008
	_suspense_dust.scale_amount_max = 0.022
	_suspense_dust.emitting = false
	add_child(_suspense_dust)


func _burst(pos: Vector3, mesh: Mesh, mat: Material, amount: int, v0: float, v1: float, life: float, grav: float,
		s0: float, s1: float, spread := 180.0, ramp: Gradient = null) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = Vector3(0, -grav, 0)
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(0.65, 0.9))
	cv.add_point(Vector2(1, 0))
	p.scale_amount_curve = cv
	if ramp != null:
		p.color_initial_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)
	return p


func _rainbow() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color.from_hsv(0.0, 0.85, 1.0))
	g.set_color(1, Color.from_hsv(0.99, 0.85, 1.0))
	for i in range(1, 8):
		g.add_point(i / 8.0, Color.from_hsv(i / 8.0, 0.85, 1.0))
	return g


func _confetti_ramp() -> Gradient:
	var c: Color = Kit.tier(rank)["color"]
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Kit.GOLD)
	g.add_point(0.35, c.darkened(0.25))
	g.add_point(0.7, c.lerp(Color.WHITE, 0.45))
	return g


func _tier_ramp() -> Gradient:
	if rank >= Kit.TOP_TIER:
		return _rainbow()
	var c: Color = Kit.tier(rank)["color"]
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, c.lerp(Color.WHITE, 0.5))
	g.add_point(0.5, c.lerp(Kit.GOLD, 0.4))
	return g


# ---------- 화면 글자 ----------

func _glass(radius := 18.0, alpha := 0.62) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.04, alpha)
	sb.set_corner_radius_all(int(radius * _ui_scale))
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(maxi(1, int(1.5 * _ui_scale)))
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = int(10 * _ui_scale)
	return sb


## 글자: Pretendard 한 가지, 굵기와 크기로만 위계를 만든다. 외곽선·번짐 없음 — 장면 위에 바로 뜨는 글자는
## 뒤에 어두운 판/막을 깔고(scrim), 그게 안 되는 작은 글자만 아래로 떨어진 옅은 그림자를 준다 (shade).
func _mk_label(text: String, size: float, color: Color, weight := 700, num := false, shade := false) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = _ls(size, color, weight, num, shade)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ls(size: float, color: Color, weight := 700, num := false, shade := false) -> LabelSettings:
	var px := int(size * _ui_scale)
	var ls := LabelSettings.new()
	ls.font = Kit.font(weight, num, -int(round(px * 0.02)) if px >= 40 else 0)
	ls.font_size = px
	ls.font_color = color
	if shade:
		ls.shadow_size = 0
		ls.shadow_color = Color(0, 0, 0, 0.5)
		ls.shadow_offset = Vector2(0, maxf(1.0, round(px * 0.05)))
	return ls


func _scrim(radial: bool, alpha: float) -> TextureRect:  # 글자 뒤에 까는 부드러운 어두운 막
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0.01, alpha))
	g.set_color(1, Color(0, 0, 0.01, 0.0))
	g.add_point(0.45, Color(0, 0, 0.01, alpha * 0.72))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 128
	if radial:
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
	else:
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var size := get_viewport().get_visible_rect().size
	_ui_scale = size.y / 720.0
	var k := _ui_scale
	_ui = Control.new()
	_ui.size = size
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_ui)

	# 사진 같은 가장자리 어둡기 (비네트)
	var vg := GradientTexture2D.new()
	vg.fill = GradientTexture2D.FILL_RADIAL
	vg.fill_from = Vector2(0.5, 0.5)
	vg.fill_to = Vector2(1.0, 1.0)
	var vgr := Gradient.new()
	vgr.set_color(0, Color(0, 0, 0, 0))
	vgr.set_color(1, Color(0, 0, 0, 0.5))
	vgr.add_point(0.55, Color(0, 0, 0, 0.0))
	vg.gradient = vgr
	var vrect := TextureRect.new()
	vrect.texture = vg
	vrect.stretch_mode = TextureRect.STRETCH_SCALE
	vrect.size = size
	vrect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(vrect)

	_top = Control.new()
	_top.size = size
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_top)
	# 잡은 수
	var sp := Panel.new()
	sp.add_theme_stylebox_override("panel", _glass())
	sp.position = Vector2(28, 24) * k
	sp.size = Vector2(214, 66) * k
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(sp)
	var cap := _mk_label("잡은 두더지", 18, Color(PAPER, 0.8), 600)
	cap.position = Vector2(18, 0) * k
	cap.size = Vector2(110, 66) * k
	sp.add_child(cap)
	_l_score = _mk_label("0", 40, PAPER, 800, true)
	_l_score.position = Vector2(128, 0) * k
	_l_score.size = Vector2(76, 66) * k
	sp.add_child(_l_score)
	# 시간 막대
	_bar_box = Panel.new()
	_bar_box.add_theme_stylebox_override("panel", _glass(17.0))
	_bar_box.size = Vector2(440, 34) * k
	_bar_box.position = Vector2(size.x * 0.5 - 220 * k, 40 * k)
	_bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_bar_box)
	_bar_fill = Panel.new()
	_bar_fill.position = Vector2(5, 5) * k
	_bar_fill.size = Vector2(430, 24) * k
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_box.add_child(_bar_fill)
	_l_time = _mk_label("15.0", 19, PAPER, 800, true, true)
	_l_time.size = Vector2(440, 34) * k
	_bar_box.add_child(_l_time)
	# 콤보
	_l_combo = _mk_label("", 36, PAPER, 800, true, true)
	_l_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_l_combo.size = Vector2(320, 66) * k
	_l_combo.position = Vector2(size.x - 348 * k, 26 * k)
	_top.add_child(_l_combo)

	_l_big = _mk_label("", 210, PAPER, 900, true)
	_l_big.size = size
	_l_big.pivot_offset = size * 0.5
	_ui.add_child(_l_big)
	var big_scrim := _scrim(true, 0.62)  # 숫자 뒤 둥근 어두운 막 (글자와 함께 커지고 사라짐)
	big_scrim.size = Vector2(520, 520) * k
	big_scrim.position = size * 0.5 - big_scrim.size * 0.5
	big_scrim.show_behind_parent = true
	_l_big.add_child(big_scrim)
	_title_scrim = _scrim(false, 0.74)  # 위쪽 제목 뒤 어두운 막
	_title_scrim.size = Vector2(size.x, 290 * k)
	_title_scrim.modulate.a = 0.0
	_ui.add_child(_title_scrim)
	_l_title = _mk_label("", 84, PAPER, 900)
	_l_title.size = Vector2(size.x, 120 * k)
	_l_title.position = Vector2(0, 36 * k)
	_l_title.pivot_offset = _l_title.size * 0.5
	_ui.add_child(_l_title)
	_l_sub = _mk_label("", 30, Color(PAPER, 0.88), 600)
	_l_sub.size = Vector2(size.x, 50 * k)
	_l_sub.position = Vector2(0, 152 * k)
	_ui.add_child(_l_sub)

	_hint_box = PanelContainer.new()
	_hint_box.add_theme_stylebox_override("panel", _glass(26.0))
	_hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_hint_box)
	var mg := MarginContainer.new()
	for s in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + s, int(30 * k))
	for s in ["top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, int(10 * k))
	_hint_box.add_child(mg)
	_l_hint = _mk_label("", 23, PAPER, 600)
	mg.add_child(_l_hint)
	_set_hint("나오는 두더지를 망치로 쾅  ·  마우스 · 터치 · 숫자키")


func _set_hint(text: String) -> void:
	_l_hint.text = text
	_hint_box.visible = text != ""
	_hint_box.reset_size()
	var size := get_viewport().get_visible_rect().size
	_hint_box.position = Vector2((size.x - _hint_box.size.x) * 0.5, size.y - _hint_box.size.y - 34 * _ui_scale)


func _pop_title(text: String, color: Color, sub: String, size := 84.0) -> void:
	_l_title.text = text
	_l_title.label_settings = _ls(size, color, 900)
	_l_sub.text = sub
	_title_scrim.create_tween().tween_property(_title_scrim, "modulate:a", 1.0, 0.25)
	_l_title.scale = Vector2(0.7, 0.7)
	_l_sub.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_l_title, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_l_sub, "modulate:a", 1.0, 0.3).set_delay(0.15)


func _float_text(world: Vector3, text: String, color: Color) -> void:
	var l := _mk_label(text, 38, color, 900, true, true)
	l.size = Vector2(240, 60) * _ui_scale
	l.position = _cam.unproject_position(world) - l.size * 0.5
	_ui.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 70 * _ui_scale, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tw.tween_callback(l.queue_free)


# ---------- 입력 ----------

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel"):
		_end(false)
	elif event is InputEventMouseMotion:
		_ptr = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_ptr = event.position
		_strike(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		var d := -1
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			d = event.keycode - KEY_0
		elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
			d = event.keycode - KEY_KP_0
		if d >= 1:
			_strike((2 - (d - 1) / 3) * 3 + (d - 1) % 3)


func _head_pos(hole: int, k := 1.0) -> Vector3:
	return _hole_pos(hole) + Vector3(0, RIM_Y - DOWN * (1.0 - k) + 0.15, 0)


func _screen_hit(world: Vector3, radius_m: float) -> bool:  # 포인터가 그 지점 근처(화면 기준)인지
	if _cam.is_position_behind(world):
		return false
	var c := _cam.unproject_position(world)
	var edge := _cam.unproject_position(world + _cam.global_basis.x * radius_m)
	return _ptr.distance_to(c) <= c.distance_to(edge)


## hole >= 0: 숫자키로 그 구멍을 침. -1: 포인터 위치를 침.
func _strike(hole: int) -> void:
	if _phase == P.PLAY:
		var target: Dictionary = {}
		for m in _moles:
			if m["hit"] >= 0.0 or m["k"] < 0.35:
				continue
			if m["hole"] == hole or (hole < 0 and _screen_hit(_head_pos(m["hole"], m["k"]) - Vector3(0, 0.04, 0), 0.17)):
				if target.is_empty() or m["hole"] > target["hole"]:  # 앞줄 우선
					target = m
		if hole >= 0:
			_aim_to = _head_pos(hole) + Vector3(0, 0.1, 0)
			_ptr = Vector2(-1, -1)
		_swing_t = 0.0
		if target.is_empty():
			_combo = 0
			Kit.sfx("swing", -4.0)
			return
		_whack(target)
	elif _phase == P.PICK and _t > 0.35:
		for i in PICK:
			if i == hole or (hole < 0 and _screen_hit(_hole_pos(i) + Vector3(0, 0.1, 0), 0.26)):
				_pick(i)
				return


func _whack(m: Dictionary) -> void:
	m["hit"] = 0.0
	_score += 1
	_combo += 1
	_freeze = 0.055
	_shake = 1.0
	var mole: Node3D = _pool[m["hole"]]
	mole.set_hit(true)
	var head := _head_pos(m["hole"], m["k"])
	_aim = head + Vector3(0, 0.1, 0)
	_aim_to = _aim
	_swing_t = 0.05
	Kit.sfx("hit")
	if _combo >= 3:
		Kit.sfx("coin", -8.0)
	_burst(head + Vector3(0, 0.1, 0.04), _star_mesh, _star_mat, 9, 1.2, 2.4, 0.55, 3.5, 0.05, 0.11)
	_burst(_hole_pos(m["hole"]) + Vector3(0, RIM_Y, 0), _dust_mesh, _dust_mat, 22, 0.6, 1.7, 0.6, 6.0, 0.008, 0.024, 70.0)
	_float_text(head + Vector3(0, 0.2, 0), "+1" if _combo < 3 else "+1  ×%d" % _combo, PAPER)
	_l_score.text = str(_score)
	_l_score.pivot_offset = _l_score.size * 0.5
	_l_score.scale = Vector2(1.5, 1.5)
	create_tween().tween_property(_l_score, "scale", Vector2.ONE, 0.2)


func _pick(i: int) -> void:
	_picked = i
	_phase = P.SUSPENSE
	_t = 0.0
	_aim_to = _hole_pos(i) + Vector3(0, RIM_Y + 0.02, 0)
	_aim = _aim_to
	_ptr = Vector2(-1, -1)
	_swing_t = 0.0
	_shake = 1.0
	Kit.sfx("hit")
	Kit.sfx("drum")
	Kit.sfx("riser", -6.0)
	_burst(_hole_pos(i) + Vector3(0, RIM_Y, 0), _dust_mesh, _dust_mat, 30, 0.8, 2.0, 0.7, 6.0, 0.01, 0.026, 70.0)
	_suspense_dust.position = _hole_pos(i) + Vector3(0, RIM_Y, 0)
	_suspense_dust.emitting = true
	_l_title.text = ""
	_l_sub.text = ""
	_pop_title("두구두구두구…", PAPER, "", 72.0)
	_set_hint("")
	var hp := _hole_pos(i)
	_cam_pos_to = Vector3(hp.x * 0.75, 0.86, hp.z + 1.08)
	_cam_look_to = hp + Vector3(0, 0.08, 0)


# ---------- 진행 ----------

func _out_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0) - 1.0
	return x * x * (2.70158 * x + 1.70158) + 1.0


func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _process(real_dt: float) -> void:
	if _done:
		return
	_frames += 1
	_clock += real_dt
	var dt := real_dt
	if _freeze > 0.0:
		_freeze -= real_dt
		dt = 0.0
	_t += dt

	match _phase:
		P.INTRO:
			var step := int(_t / 0.6)
			if step != _count_shown and step < 4:
				_count_shown = step
				Kit.sfx("go" if step == 3 else "tick")
				_l_big.text = ["3", "2", "1", "시작!"][step]
				_l_big.label_settings = _ls(210 if step < 3 else 140, PAPER, 900, step < 3)
			var f := fmod(_t, 0.6) / 0.6
			_l_big.scale = Vector2.ONE * (1.6 - 0.6 * _smooth(f * 2.5))
			_l_big.modulate.a = clampf((1.0 - f) * 4.0, 0.0, 1.0)
			if _t >= INTRO_T:
				_phase = P.PLAY
				_t = 0.0
				_next_spawn = 0.2
				_l_big.text = ""
				_set_hint("")
		P.PLAY:
			_play(dt)
		P.PICK:
			if (Kit.auto and _t >= 1.0) or _t >= 15.0:
				_pick(PICK[randi() % 3])
		P.SUSPENSE:
			var mound := _mounds[_picked]
			var amp := 0.004 + 0.008 * (_t / SUSPENSE_T)
			mound.position = _hole_pos(_picked) + Vector3(randf_range(-amp, amp), randf_range(-amp, amp) * 0.4, randf_range(-amp, amp))
			_l_title.rotation = sin(_clock * 40.0) * 0.012
			_shake = maxf(_shake, 0.12 + 0.2 * _t / SUSPENSE_T)
			if _t >= SUSPENSE_T:
				_reveal()
		P.REVEAL:
			_reveal_update(dt)
	if _dev_dir != "":
		_dev_shot("1_intro", P.INTRO, 1.0)
		_dev_shot("2_play", P.PLAY, 2.2)
		_dev_shot("3_play_late", P.PLAY, play_t - 0.6)
		_dev_shot("4_pick", P.PICK, 0.85)
		_dev_shot("5_suspense", P.SUSPENSE, 1.2)
		_dev_shot("6_reveal", P.REVEAL, 0.9)
		_dev_shot("7_reveal_late", P.REVEAL, 2.4)
		if _freeze > 0.0 and not _dev_done.has("2_hit"):
			_dev_done["2_hit"] = true
			get_tree().create_timer(0.1).timeout.connect(func():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(_dev_dir.path_join("2_hit.png")))
	_update_moles(dt)
	_update_pick_fx(dt)
	_update_look(real_dt)
	_update_mallet(real_dt)


func _play(_dt: float) -> void:
	var prog := _t / play_t
	var left := maxf(play_t - _t, 0.0)
	var cap := 1 if prog < 0.3 else (2 if prog < 0.75 else 3)
	if _t >= _next_spawn and _moles.size() < cap:
		var free: Array = []
		for i in 9:
			if not _moles.any(func(m): return m["hole"] == i):
				free.append(i)
		var hole: int = free[randi() % free.size()]
		var m := {"hole": hole, "age": 0.0, "up": lerpf(1.0, 0.68, prog), "hit": -1.0, "k": 0.0, "auto": -1.0}
		if Kit.auto and randf() < 0.78:
			m["auto"] = randf_range(0.28, 0.5)
		_moles.append(m)
		var mole: Node3D = _pool[hole]
		mole.set_hit(false)
		mole.rotation.y = randf_range(-0.25, 0.25)
		_next_spawn = _t + randf_range(lerpf(0.42, 0.18, prog), lerpf(0.75, 0.38, prog))
		Kit.sfx("pop", -7.0)
	for m in _moles:
		if m["auto"] >= 0.0 and m["hit"] < 0.0 and m["age"] >= m["auto"]:
			m["auto"] = -1.0
			_ptr = _cam.unproject_position(_head_pos(m["hole"], m["k"]))
			_strike(-1)
	# HUD
	_l_time.text = "%.1f" % left
	var frac := left / play_t
	var col := Color(0.45, 0.9, 0.45)
	if left < 5.0:
		col = Color(1.0, 0.3, 0.3) if int(left * 4.0) % 2 == 1 else Color(1.0, 0.8, 0.25)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(12 * _ui_scale))
	_bar_fill.add_theme_stylebox_override("panel", sb)
	_bar_fill.size.x = maxf(24.0, 430.0 * frac) * _ui_scale
	_l_combo.text = "%d 콤보" % _combo if _combo >= 2 else ""
	_l_combo.pivot_offset = Vector2(_l_combo.size.x, _l_combo.size.y * 0.5)
	_l_combo.scale = Vector2.ONE * (1.0 + 0.06 * sin(_clock * 12.0))
	if left <= 5.0 and int(left) != _last_tick:
		_last_tick = int(left)
		Kit.sfx("tick")
	if _t >= play_t:
		_phase = P.PICK
		_t = 0.0
		for m in _moles:  # 남은 두더지는 쏙 들어감
			if m["hit"] < 0.0:
				m["age"] = maxf(m["age"], m["up"])
		Kit.sfx("go")
		Kit.sfx("drum", -6.0)
		_top.visible = false
		_dim_to = 1.0
		_pop_title("마지막 한 방", PAPER, "%d마리 잡았어요  ·  빛나는 구멍 하나를 골라 쾅" % _score)
		_set_hint("가운데 줄 구멍 하나를 터치  ·  숫자키 4 · 5 · 6")
		_cam_pos_to = Vector3(0, 1.4, 1.62)
		_cam_look_to = Vector3(0, 0.02, -0.02)
		for fx in _pick_fx:
			fx["light"].visible = true
			fx["top"].visible = true
			fx["q"].visible = true


func _update_moles(dt: float) -> void:
	var keep: Array = []
	for m in _moles:
		m["age"] += dt
		var mole: Node3D = _pool[m["hole"]]
		var squash := 1.0
		if m["hit"] >= 0.0:
			m["hit"] += dt
			var h: float = m["hit"]
			squash = 0.62 + 0.38 * _smooth(h / 0.16) + 0.08 * sin(minf(h / 0.16, 1.0) * PI)
			m["k"] = minf(m["k"], 1.0 - _smooth((h - 0.18) / 0.24))
		elif m["age"] < m["up"]:
			m["k"] = _out_back(m["age"] / 0.17)
		else:
			m["k"] = 1.0 - _smooth((m["age"] - m["up"]) / 0.18)
		var k: float = m["k"]
		mole.visible = k > 0.0
		mole.position = _hole_pos(m["hole"]) + Vector3(0, RIM_Y - DOWN * (1.0 - k) - (1.0 - squash) * 0.1, 0)
		mole.scale = Vector3(2.0 - squash, squash, 2.0 - squash) if squash < 1.0 else Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
		if m["hit"] < 0.0:
			mole.rotation.z = sin(_clock * 7.0 + m["hole"]) * 0.035
		if k <= 0.0 and (m["hit"] >= 0.0 or m["age"] > m["up"]):
			mole.visible = false
		else:
			keep.append(m)
	_moles = keep


func _update_pick_fx(dt: float) -> void:
	for fx in _pick_fx:
		var on: bool = _phase == P.PICK or ((_phase == P.SUSPENSE) and fx["hole"] == _picked)
		fx["a"] = move_toward(fx["a"], 1.0 if on else 0.0, dt * 3.5)
		var a: float = fx["a"]
		var pulse := 0.5 + 0.5 * sin(_clock * 5.0 + fx["hole"] * 1.3)
		var boost := 1.0
		if _phase == P.SUSPENSE:
			boost = 1.4 + 2.2 * (_t / SUSPENSE_T) + randf() * 0.8
		(fx["light"] as OmniLight3D).light_energy = a * (2.4 + 1.6 * pulse) * boost
		(fx["top"] as OmniLight3D).light_energy = a * (0.22 + 0.12 * pulse)
		var q: Label3D = fx["q"]
		q.visible = a > 0.01 and _phase == P.PICK
		q.position.y = 0.17 + 0.025 * sin(_clock * 3.6 + fx["hole"] * 1.3)
		q.modulate.a = a
		q.outline_modulate.a = a * 0.95
		if a <= 0.0 and _phase >= P.REVEAL:
			fx["light"].visible = false
			fx["top"].visible = false


func _reveal() -> void:
	_phase = P.REVEAL
	_t = 0.0
	_suspense_dust.emitting = false
	_mounds[_picked].position = _hole_pos(_picked)
	_l_title.rotation = 0.0
	var hp := _hole_pos(_picked)
	_special.visible = true
	_special.position = hp + Vector3(0, RIM_Y - DOWN, 0)
	_shake = 1.2
	Kit.sfx("pop")
	_burst(hp + Vector3(0, RIM_Y, 0), _dust_mesh, _dust_mat, 46, 1.0, 2.8, 0.8, 6.0, 0.01, 0.03, 60.0)
	var tc: Color = Kit.tier(rank)["color"]
	_reveal_light.position = hp + Vector3(0.1, 0.5, 0.42)
	_cam_pos_to = Vector3(hp.x * 0.8, 0.66, hp.z + 0.92)
	_cam_look_to = hp + Vector3(0, 0.27, 0)
	if win:
		_dim_to = 0.3
		_reveal_light.light_color = tc.lerp(Color(1.0, 0.95, 0.88), 0.8)
		Kit.sfx("coin")
		var size := 84.0 if rank < 3 else 72.0
		_pop_title(TITLE[rank], PAPER, "%s 등급 당첨  ·  %s" % [Kit.tier(rank)["kor"], prize], size)
		_celebrate3d(hp)
		var dur: float = Kit.celebrate(rank, prize, false)
		await get_tree().create_timer(dur + 0.9).timeout
	else:
		_dim_to = 0.6
		_reveal_light.light_color = Color(0.75, 0.82, 1.0)
		Kit.sfx("groan")
		Kit.sfx("lose", -6.0)
		_pop_title(TITLE[0], Color(PAPER, 0.85), "메롱~  다음 기회에 만나요")
		await get_tree().create_timer(2.7).timeout
	_end(true)


func _celebrate3d(hp: Vector3) -> void:
	var ramp := _tier_ramp()
	var spark := StandardMaterial3D.new()
	spark.albedo_color = Color(2.6, 2.6, 2.6)  # 밝게(빛 번짐) + 알갱이마다 색
	spark.vertex_color_use_as_albedo = true
	spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 구멍에서 솟는 빛 알갱이
	_burst(hp + Vector3(0, RIM_Y + 0.05, 0), _dust_mesh, spark, 40 + 30 * rank, 1.4, 3.6, 1.1, 5.0, 0.008, 0.02, 38.0, ramp)
	_burst(hp + Vector3(0, 0.3, 0.05), _star_mesh, _star_mat, 8 + 5 * rank, 0.8, 2.2, 1.0, 2.0, 0.05, 0.12, 180.0, ramp if rank >= 4 else null)
	# 색종이 (등급이 높을수록 많이, 오래)
	var cm := QuadMesh.new()
	cm.size = Vector2(1.0, 0.6)
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.roughness = 0.5
	var conf := CPUParticles3D.new()
	conf.mesh = cm
	conf.material_override = cmat
	conf.position = hp + Vector3(0, 1.25, 0.2)
	conf.amount = 50 + 70 * rank
	conf.lifetime = 2.6
	conf.explosiveness = 0.0
	conf.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	conf.emission_box_extents = Vector3(0.75, 0.05, 0.5)
	conf.direction = Vector3.DOWN
	conf.spread = 40.0
	conf.initial_velocity_min = 0.1
	conf.initial_velocity_max = 0.7
	conf.gravity = Vector3(0, -1.6, 0)
	conf.scale_amount_min = 0.014
	conf.scale_amount_max = 0.026
	conf.angle_min = -180.0
	conf.angle_max = 180.0
	conf.angular_velocity_min = -400.0
	conf.angular_velocity_max = 400.0
	conf.particle_flag_rotate_y = true
	conf.color_initial_ramp = _rainbow() if rank >= 3 else _confetti_ramp()
	add_child(conf)
	conf.emitting = true
	# 공중 불꽃 (에픽 이상)
	if rank >= 2:
		var n := (rank - 1) * 3
		var dur := 2.4 + 0.8 * rank
		for i in n:
			get_tree().create_timer(0.3 + (dur - 1.0) * i / n + randf() * 0.2).timeout.connect(func():
				if _done:
					return
				var p := hp + Vector3(randf_range(-0.55, 0.55), randf_range(0.45, 0.75), randf_range(-0.9, -0.3))
				var g := Gradient.new()
				var c := Color.from_hsv(randf(), 0.8, 1.0) if rank >= 4 else (Kit.tier(rank)["color"] as Color)
				g.set_color(0, c)
				g.set_color(1, c.lerp(Color.WHITE, 0.6))
				_burst(p, _dust_mesh, spark, 70, 0.5, 1.5, 0.9, 1.2, 0.007, 0.016, 180.0, g)
				var fl := OmniLight3D.new()
				fl.position = p
				fl.light_color = c
				fl.omni_range = 1.4
				fl.light_energy = 2.5
				add_child(fl)
				var tw := create_tween()
				tw.tween_property(fl, "light_energy", 0.0, 0.6)
				tw.tween_callback(fl.queue_free))


func _reveal_update(_dt: float) -> void:
	var hp := _hole_pos(_picked)
	var k := _out_back(_t / 0.42)
	var y := RIM_Y - DOWN * (1.0 - k)
	if win:
		var hop := absf(sin(maxf(_t - 0.45, 0.0) * 6.5)) * 0.022 * (1.0 + 0.25 * rank)
		_special.position = hp + Vector3(0, y + hop, 0)
		_special.rotation.y = sin(_t * 4.2) * 0.3
		_special.rotation.z = sin(_t * 8.4) * 0.05
		var s := 1.0 + 0.05 * sin(_t * 13.0)
		_special.scale = Vector3(2.0 - s, s, 2.0 - s)
		_reveal_light.light_energy = (1.1 + rank * 0.15) * _smooth(_t / 0.3) + 3.0 * maxf(0.0, 1.0 - _t / 0.4)
		if rank >= 4:
			_reveal_light.light_color = Color.from_hsv(fmod(_t * 0.4, 1.0), 0.22, 1.0)
	else:
		_special.position = hp + Vector3(0, y - 0.012, 0)
		_special.rotation.y = sin(_t * 2.6) * 0.22
		_special.rotation.z = sin(_t * 1.3) * 0.07
		_reveal_light.light_energy = 1.5 * _smooth(_t / 0.4)
		_env.adjustment_saturation = lerpf(1.08, 0.7, _smooth(_t / 0.8))


func _update_look(dt: float) -> void:
	# 어두워지는 연출 (마지막 한 방)
	_dim = move_toward(_dim, _dim_to, dt * 1.6)
	_sun.light_energy = lerpf(_sun_base, 0.42, _dim)
	_sun.light_color = Color(1.0, 0.86, 0.68).lerp(Color(0.6, 0.7, 1.0), _dim)
	_env.ambient_light_energy = lerpf(0.85, 0.3, _dim)
	_env.background_energy_multiplier = lerpf(1.0, 0.25, _dim)
	# 카메라
	var f := 1.0 - exp(-dt * (2.4 if _phase < P.REVEAL else 4.5))
	_cam_pos = _cam_pos.lerp(_cam_pos_to, f)
	_cam_look = _cam_look.lerp(_cam_look_to, f)
	_shake = maxf(0.0, _shake - dt * 6.0)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.012 * _shake
	_cam.position = _cam_pos + Vector3(sin(_clock * 0.5) * 0.008, sin(_clock * 0.37) * 0.005, 0) + sh
	_cam.look_at(_cam_look + sh * 0.5)
	var focus := _cam_pos.distance_to(_cam_look)
	_cam_attr.dof_blur_far_distance = focus + (1.3 if _phase < P.SUSPENSE else 0.35)
	_cam_attr.dof_blur_far_transition = 2.5 if _phase < P.SUSPENSE else 1.2
	_cam_attr.dof_blur_near_distance = focus * 0.42


func _update_mallet(dt: float) -> void:
	if _ptr.x >= 0.0:  # 포인터가 가리키는 지점 (두더지 머리 높이쯤의 평면)
		var from := _cam.project_ray_origin(_ptr)
		var dir := _cam.project_ray_normal(_ptr)
		if dir.y < -0.01:
			var hit := from + dir * ((0.3 - from.y) / dir.y)
			_aim_to = Vector3(clampf(hit.x, -1.6, 1.6), 0.3, clampf(hit.z, -1.6, 1.1))
	_aim = _aim.lerp(_aim_to, 1.0 - exp(-dt * 26.0))
	_swing_t += dt
	var swing := 0.0
	if _swing_t < 0.05:
		swing = _swing_t / 0.05
	elif _swing_t < 0.3:
		swing = 1.0 - _smooth((_swing_t - 0.09) / 0.21)
	var rest := 0.72 + sin(_clock * 2.2) * 0.03
	var th := lerpf(rest, -0.14, swing)
	var yaw := Basis(Vector3.UP, MALLET_YAW)
	var strike := yaw * Basis(Vector3.RIGHT, -0.14)
	# 내리쳤을 때 망치 머리 밑면이 겨냥점보다 살짝 아래(두더지 머리)에 닿도록 손 위치를 정함
	var hand := _aim - strike * Vector3(0, -0.092, -MALLET_L) * _mallet_scale
	_mallet.transform = Transform3D((yaw * Basis(Vector3.RIGHT, th)).scaled(Vector3.ONE * _mallet_scale), hand)
	_mallet.visible = _phase != P.REVEAL or _t < 0.25
	if _phase == P.SUSPENSE:  # 고른 구멍 옆으로 비켜 둠
		_mallet.position += Vector3(0.34, 0.1, 0.12) * _smooth(_t / 0.4)
