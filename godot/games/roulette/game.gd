extends Node3D
## 레전드 룰렛 — 쇼 무대 위의 실물 경품 룰렛.
## 한 번 누르면 돌기 시작 → 멈출 듯하다가 등급이 터지며 다시 가속(RARE → EPIC → LEGENDARY → CRITICAL) → 정해진 경품 칸에 멈춤.
## 결과(prize/rank)는 런처가 정해 줌. 칸 넓이 = 실제 확률(Store.PRIZES). 장면은 전부 코드로 만듦 (build.gd).

const NAME := "레전드 룰렛"
const TAGLINE := "돌려라! 등급이 터진다!"

signal finished(completed: bool)

var win := false      ## 당첨 여부
var prize := ""       ## 경품 이름
var rank := 0         ## 등급 0(꽝)~4(크리티컬)

const B := preload("res://games/roulette/build.gd")

const R := 0.6                        # 룰렛 판 반지름(m)
const HUB := Vector3(0, 1.66, 0)      # 룰렛 중심
const SPIN_S := 1.7
const SLOW_S := 1.1
const BOOST_S := 1.05
const FINAL_MIN_S := 3.4
const N_BULBS := 30
const WARM := Color(1.0, 0.8, 0.52)
const KEY_E := 9.0
const CAM_WIDE := Vector3(0.72, 0.06, 3.95)
const TGT_WIDE := Vector3(0.40, -0.16, 0.0)
const CAM_CLOSE := Vector3(0.30, 0.50, 2.35)
const TGT_CLOSE := Vector3(0.07, 0.46, 0.0)

var _slices: Array = []        # {name, rank, start, width}
var _target := {}
var _landing := 0.0
var _near_miss := false
var _script: Array = []
var _state := "ready"
var _now := 0.0
var _el := 0.0
var _theta := 0.0
var _omega := 14.0
var _final: Array = []
var _level := 0
var _boom_at := -99.0
var _last_idx := -1
var _last_tick := -9.0
var _last_heart := -9.0
var _riser_for := -1
var _done := false
var _snap_dir := OS.get_environment("ROULETTE_SNAP")
var _snaps: Array = []
var _snapped := {}

# 연출 값
var _flap := 0.0
var _flash := 0.0
var _shake := 0.0
var _punch := 0.0
var _dim := 0.0
var _zoom := 0.0
var _land_zoom := 0.85
var _sad := false
var _lit := 0.0          # 멈춘 칸 강조
var _col := Color(0.32, 0.38, 0.75)
var _chase := 0.0
var _strobe_t := 0.0
var _strobe := 0.0

# 장면
var _env: Environment
var _cam: Camera3D
var _cam_attr: CameraAttributesPractical
var _wheel: Node3D
var _face_mat: ShaderMaterial
var _hl_mat: StandardMaterial3D
var _hl: MeshInstance3D
var _shade: MeshInstance3D
var _shade_mat: StandardMaterial3D
var _soft: GradientTexture2D
var _jewel_mat: StandardMaterial3D
var _flap_segs: Array = []
var _bulb_mats: Array = []
var _bulb_e: Array = []
var _fairy_mat: StandardMaterial3D
var _under_mat: StandardMaterial3D
var _key: SpotLight3D
var _fill: SpotLight3D
var _rim: SpotLight3D
var _pin: SpotLight3D
var _wash: Array = []
var _halo: OmniLight3D
var _front: OmniLight3D
var _bolt: OmniLight3D
var _beams: Array = []
var _sparks: CPUParticles3D

# HUD
var _hud: CanvasLayer
var _flash_rect: ColorRect
var _title_sb: StyleBoxFlat
var _title_lbl: Label
var _prompt: Control
var _tense: Control
var _banner: Control
var _banner_big: Label
var _banner_mark: ColorRect
var _result_mark: ColorRect
var _banner_sub: Label
var _result: Control
var _result_sb: StyleBoxFlat
var _result_big: Label
var _result_sub: Label
var _rows := {}


func _ready() -> void:
	_slices = B.build_slices()
	_plan()
	_build_stage()
	_build_wheel()
	_build_lights()
	_build_hud()
	_theta = randf() * 360.0
	_visuals(0.0, false)
	_snap("ready", 0.8)
	if Kit.auto:
		get_tree().create_timer(1.0).timeout.connect(_go)


# ---------- 결과 계획 ----------

func _plan() -> void:
	var mine: Array = _slices.filter(func(s): return s["rank"] == rank)
	_near_miss = rank == 0 and randf() < 0.45
	if _near_miss:  # 최고 등급 칸을 아슬아슬하게 지나쳐서 바로 다음 꽝 칸
		var top_i := 0
		for i in _slices.size():
			if _slices[i]["rank"] > _slices[top_i]["rank"]:
				top_i = i
		_target = _slices[(top_i + 1) % _slices.size()]
		if _target["rank"] != 0:
			_near_miss = false
	if _near_miss:
		_landing = _target["start"] + _target["width"] * randf_range(0.06, 0.13)
	else:
		_target = mine[randi() % mine.size()]
		_landing = _target["start"] + _target["width"] * randf_range(0.3, 0.7)
	_script = [["spin", SPIN_S, 560.0]]
	for lv in range(1, rank + 1):
		_script.append(["slow", SLOW_S, 40.0])
		_script.append(["boom", lv])
		_script.append(["spin", BOOST_S, 560.0 + 170.0 * lv])
	_script.append(["final"])


func _slice_at(theta: float) -> int:
	var a := fposmod(theta, 360.0)
	for i in _slices.size():
		if a >= _slices[i]["start"] and a < _slices[i]["start"] + _slices[i]["width"]:
			return i
	return _slices.size() - 1


# ---------- 장면 ----------

func _mi(mesh: Mesh, mat: Material, parent: Node, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	parent.add_child(m)
	return m


func _brass(rough := 0.26) -> StandardMaterial3D:
	return Kit.plain(Color(0.9, 0.72, 0.36), 1.0, rough)


func _lacquer(c: Color) -> StandardMaterial3D:
	var m := Kit.plain(c, 0.0, 0.3)
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	m.clearcoat_roughness = 0.08
	return m


func _wood(scale := 2.0) -> StandardMaterial3D:
	var m := Kit.pbr("walnut_veneer", Vector3(scale, scale, scale), Color(0.5, 0.32, 0.23), true)
	m.roughness = 0.55
	m.clearcoat_enabled = true
	m.clearcoat = 0.7
	m.clearcoat_roughness = 0.12
	return m


func _build_stage() -> void:
	var we := Kit.environment("studio_small_03", {"show_sky": false, "sky_energy": 0.4, "ambient": 0.22, "fog": 0.006, "glow": 0.4})
	_env = we.environment
	_env.volumetric_fog_albedo = Color(0.85, 0.88, 1.0)
	_env.volumetric_fog_length = 24.0
	_env.glow_hdr_threshold = 1.35
	_env.ssil_enabled = false
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.08
	add_child(we)

	# 바닥: 광택 낸 어두운 마루
	var plane := PlaneMesh.new()
	plane.size = Vector2(26, 18)
	var fm := Kit.pbr("dark_wooden_planks", Vector3(9, 6, 1), Color(0.62, 0.56, 0.52))
	fm.roughness = 0.5
	_mi(plane, fm, self, Vector3(0, 0, -1.0))

	# 뒤 장막 (주름진 벨벳)
	var cm := Kit.pbr("velour_velvet", Vector3(1.5, 1.5, 1.5), Color(0.05, 0.048, 0.062), true)
	cm.albedo_texture = null
	cm.roughness = 0.95
	cm.metallic = 0.0
	cm.metallic_texture = null
	_mi(B.curtain(22.0, 8.0), cm, self, Vector3(0, 0, -3.6))

	# 둥근 단상
	var wood := Kit.pbr("dark_wooden_planks", Vector3(0.55, 0.55, 0.55), Color(0.5, 0.36, 0.28), true)
	wood.roughness = 0.6
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.6
	wood.clearcoat_roughness = 0.15
	_mi(B.lathe([Vector2(1.42, 0.0), Vector2(1.42, 0.115), Vector2(1.45, 0.125), Vector2(1.45, 0.15), Vector2(1.44, 0.16), Vector2(0, 0.16)], 96), wood, self)
	_mi(B.lathe([Vector2(1.452, 0.128), Vector2(1.458, 0.134), Vector2(1.458, 0.146), Vector2(1.452, 0.152)], 96), _brass(), self)
	_mi(B.lathe([Vector2(1.3, 0.0), Vector2(1.425, 0.0), Vector2(1.425, 0.03)], 96), _lacquer(Color(0.02, 0.02, 0.025)), self)
	_under_mat = Kit.emissive(WARM, 2.0)
	_mi(B.lathe([Vector2(1.427, 0.045), Vector2(1.427, 0.06)], 96), _under_mat, self)

	# 받침 기둥
	var brass := _brass()
	var dark := _lacquer(Color(0.025, 0.028, 0.045))
	var post := Node3D.new()
	post.position = Vector3(0, 0.16, -0.2)
	add_child(post)
	_mi(B.lathe([Vector2(0, 0), Vector2(0.4, 0.0), Vector2(0.4, 0.022), Vector2(0.385, 0.04), Vector2(0.3, 0.055), Vector2(0.18, 0.07),
		Vector2(0.11, 0.095), Vector2(0.075, 0.14), Vector2(0.06, 0.2), Vector2(0.052, 0.3), Vector2(0.052, 1.52), Vector2(0.03, 1.56), Vector2(0, 1.57)], 48), dark, post)
	for y in [0.022, 0.2, 0.34, 0.62]:
		var rr: float = 0.402 if y < 0.1 else (0.062 if y < 0.25 else 0.054)
		_mi(B.lathe([Vector2(rr, y), Vector2(rr + 0.008, y + 0.004), Vector2(rr + 0.008, y + 0.016), Vector2(rr, y + 0.02)], 48), brass, post)
	# 축 (기둥 → 판)
	_mi(B.lathe([Vector2(0.07, 0.0), Vector2(0.07, 0.1), Vector2(0.03, 0.11), Vector2(0.03, 0.2)], 32), brass, self, HUB + Vector3(0, 0, -0.26), Vector3(90, 0, 0))

	# 뒤판 (전구 테)
	var back := Node3D.new()
	back.position = HUB + Vector3(0, 0, -0.06)
	add_child(back)
	_mi(B.lathe([Vector2(0, -0.04), Vector2(0.80, -0.04), Vector2(0.812, -0.03), Vector2(0.812, -0.008), Vector2(0.80, 0.0), Vector2(0, 0.0)], 96),
		_lacquer(Color(0.03, 0.035, 0.07)), back, Vector3.ZERO, Vector3(90, 0, 0))
	_mi(B.lathe([Vector2(0.813, -0.03), Vector2(0.819, -0.026), Vector2(0.819, -0.012), Vector2(0.813, -0.008)], 96), brass, back, Vector3.ZERO, Vector3(90, 0, 0))
	_mi(B.lathe([Vector2(0.692, 0.0), Vector2(0.692, 0.004), Vector2(0.686, 0.004), Vector2(0.686, 0.0)], 96), brass, back, Vector3.ZERO, Vector3(90, 0, 0))
	var socket := B.lathe([Vector2(0.03, 0.0), Vector2(0.03, 0.006), Vector2(0.024, 0.012), Vector2(0.017, 0.012), Vector2(0.015, 0.004)], 16)
	var bulb := SphereMesh.new()
	bulb.radius = 0.02
	bulb.height = 0.04
	bulb.radial_segments = 16
	bulb.rings = 8
	for i in N_BULBS:
		var a := deg_to_rad((i + 0.5) * 360.0 / N_BULBS)
		var p := Vector3(sin(a), cos(a), 0) * 0.745
		_mi(socket, brass, back, p, Vector3(90, 0, 0))
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.9, 0.86, 0.8)
		bm.roughness = 0.15
		bm.emission_enabled = true
		bm.emission = WARM
		_bulb_mats.append(bm)
		_bulb_e.append(0.0)
		_mi(bulb, bm, back, p + Vector3(0, 0, 0.022))

	# 포인터: 뒤판 꼭대기에서 앞으로 나온 받침 + 휘는 가죽 날
	var mount := Node3D.new()
	mount.position = HUB + Vector3(0, 0.745, 0)
	add_child(mount)
	_mi(B.lathe([Vector2(0.04, 0.0), Vector2(0.04, 0.012), Vector2(0.026, 0.02), Vector2(0.02, 0.075), Vector2(0.02, 0.102)], 24), brass, mount, Vector3(0, 0, -0.06), Vector3(90, 0, 0))
	_mi(B.lathe([Vector2(0.03, 0.0), Vector2(0.03, 0.006), Vector2(0.024, 0.014), Vector2(0.012, 0.02), Vector2(0, 0.021)], 24), brass, mount, Vector3(0, 0, 0.042), Vector3(90, 0, 0))
	var leather := _lacquer(Color(0.62, 0.02, 0.035))
	var widths := [0.07, 0.06, 0.045, 0.028, 0.008]
	var parent: Node3D = mount
	for i in 4:
		var seg := Node3D.new()
		seg.position = Vector3(0, 0.0 if i == 0 else -0.052, 0.0)
		parent.add_child(seg)
		_mi(B.taper(widths[i], widths[i + 1], 0.052, 0.007), leather, seg, Vector3(0, 0, 0.036))
		_flap_segs.append(seg)
		parent = seg

	# 뒤쪽 꼬마전구 줄 (초점 밖 빛망울)
	_fairy_mat = Kit.emissive(WARM, 5.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.014
	dot.height = 0.028
	dot.radial_segments = 8
	dot.rings = 4
	mm.mesh = dot
	var pts: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for s in 6:
		var y0 := 2.3 + s * 0.52
		var n := 26
		for k in n:
			var u := float(k) / (n - 1)
			var sag := 0.35 * (1.0 - pow(2.0 * fposmod(u * 3.0 + s * 0.37, 1.0) - 1.0, 2.0))
			pts.append(Vector3(lerpf(-6.5, 6.5, u) + rng.randf_range(-0.05, 0.05), y0 - sag, -3.0 - 0.06 * s))
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _fairy_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	_cam = Camera3D.new()
	_cam.fov = 34
	_cam_attr = CameraAttributesPractical.new()
	_cam_attr.dof_blur_far_enabled = true
	_cam_attr.dof_blur_far_distance = 5.6
	_cam_attr.dof_blur_far_transition = 2.5
	_cam_attr.dof_blur_amount = 0.09
	_cam.attributes = _cam_attr
	add_child(_cam)


func _build_wheel() -> void:
	_wheel = Node3D.new()
	_wheel.position = HUB
	add_child(_wheel)
	var brass := _brass()
	# 테두리(호두나무) + 몸통
	_mi(B.lathe([Vector2(0, -0.03), Vector2(0.656, -0.03), Vector2(0.668, -0.02), Vector2(0.668, 0.01), Vector2(0.664, 0.02), Vector2(0.654, 0.026),
		Vector2(0.62, 0.026), Vector2(0.61, 0.02), Vector2(0.606, 0.0)], 128), _wood(3.0), _wheel, Vector3.ZERO, Vector3(90, 0, 0))
	_mi(B.lathe([Vector2(0.669, -0.012), Vector2(0.674, -0.008), Vector2(0.674, 0.002), Vector2(0.669, 0.006)], 128), brass, _wheel, Vector3.ZERO, Vector3(90, 0, 0))
	_mi(B.lathe([Vector2(0.609, 0.0), Vector2(0.609, 0.006), Vector2(0.6, 0.006), Vector2(0.598, 0.0)], 128), brass, _wheel, Vector3.ZERO, Vector3(90, 0, 0))

	# 판 (인쇄면): SubViewport 로 한 번 그려서 텍스처로
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D sharp : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D blurred : source_color, filter_linear_mipmap;
uniform float blur_mix = 0.0;
void fragment() {
	vec3 a = texture(sharp, UV).rgb;
	vec3 b = texture(blurred, UV).rgb;
	ALBEDO = mix(a, b, blur_mix);
	ROUGHNESS = 0.42;
	SPECULAR = 0.45;
	CLEARCOAT = 0.5;
	CLEARCOAT_ROUGHNESS = 0.07;
}"""
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = sh
	_mi(B.disc(0.607, 96), _face_mat, _wheel, Vector3(0, 0, 0.001))
	_bake_face()

	# 칸막이(황동 띠)와 핀
	var strip := BoxMesh.new()
	strip.size = Vector3(0.004, 0.485, 0.004)
	var peg := B.lathe([Vector2(0.013, 0.0), Vector2(0.013, 0.004), Vector2(0.009, 0.008), Vector2(0.009, 0.044), Vector2(0.006, 0.05), Vector2(0, 0.052)], 16)
	for s in _slices:
		var a := deg_to_rad(s["start"])
		var dir := Vector3(sin(a), cos(a), 0)
		_mi(strip, brass, _wheel, dir * 0.3575 + Vector3(0, 0, 0.002), Vector3(0, 0, -s["start"]))
		_mi(peg, brass, _wheel, dir * 0.565, Vector3(90, 0, 0))

	# 중심 허브
	_mi(B.lathe([Vector2(0.118, 0.0), Vector2(0.118, 0.01), Vector2(0.108, 0.02), Vector2(0.085, 0.026), Vector2(0.075, 0.04), Vector2(0.06, 0.052),
		Vector2(0.04, 0.06), Vector2(0.03, 0.062)], 64), brass, _wheel, Vector3.ZERO, Vector3(90, 0, 0))
	for i in 6:
		var a := TAU * i / 6.0
		_mi(B.lathe([Vector2(0.008, 0.0), Vector2(0.008, 0.004), Vector2(0.004, 0.007), Vector2(0, 0.007)], 12), _brass(0.4), _wheel,
			Vector3(sin(a), cos(a), 0) * 0.097 + Vector3(0, 0, 0.022), Vector3(90, 0, 0))
	_jewel_mat = StandardMaterial3D.new()
	_jewel_mat.albedo_color = Color(0.9, 0.9, 0.95)
	_jewel_mat.roughness = 0.05
	_jewel_mat.emission_enabled = true
	_jewel_mat.clearcoat_enabled = true
	var gem := SphereMesh.new()
	gem.radius = 0.03
	gem.height = 0.042
	_mi(gem, _jewel_mat, _wheel, Vector3(0, 0, 0.062))

	# 멈춘 칸 강조 (빛나는 덮개)
	_hl_mat = StandardMaterial3D.new()
	_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hl_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hl_mat.albedo_color = Color(1, 1, 1, 0)
	_hl = _mi(B.sector(0.125, 0.598, _target["start"], _target["start"] + _target["width"]), _hl_mat, _wheel, Vector3(0, 0, 0.003))
	_hl.visible = false
	_shade_mat = StandardMaterial3D.new()
	_shade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shade_mat.albedo_color = Color(0, 0, 0.02, 0)
	_shade = _mi(B.sector(0.125, 0.598, _target["start"] + _target["width"], _target["start"] + 360.0), _shade_mat, _wheel, Vector3(0, 0, 0.003))
	_shade.visible = false

	# 크리티컬 불꽃 (포인터 끝)
	_sparks = CPUParticles3D.new()
	_sparks.position = HUB + Vector3(0, 0.56, 0.05)
	_sparks.emitting = false
	_sparks.amount = 90
	_sparks.lifetime = 0.55
	_sparks.direction = Vector3(-1, 0.5, 0.4)
	_sparks.spread = 35.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 4.5
	_sparks.gravity = Vector3(0, -6.0, 0)
	_sparks.scale_amount_min = 0.4
	_sparks.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.014)
	q.size = Vector2(0.03, 0.03)
	q.material = _spark_material(Color(1.0, 0.75, 0.4), 10.0)
	_sparks.mesh = q
	add_child(_sparks)


func _bake_face() -> void:
	var size := 2048
	var vp := B.face_viewport(_slices, size)
	add_child(vp)
	_face_mat.set_shader_parameter("sharp", vp.get_texture())
	_face_mat.set_shader_parameter("blurred", vp.get_texture())
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_face_mat.set_shader_parameter("sharp", tex)
	_face_mat.set_shader_parameter("blurred", tex)
	vp.queue_free()
	# 회전 잔상용: 같은 그림을 각도만 조금씩 달리해 평균
	var vp2 := B.blur_viewport(tex, 1024, 30, 15.0)
	add_child(vp2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img2 := vp2.get_texture().get_image()
	img2.generate_mipmaps()
	_face_mat.set_shader_parameter("blurred", ImageTexture.create_from_image(img2))
	vp2.queue_free()


func _spot(pos: Vector3, look: Vector3, color: Color, energy: float, angle: float, shadow := false, fog := 0.4) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = 16.0
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.7
	l.spot_attenuation = 0.6
	l.shadow_enabled = shadow
	l.shadow_blur = 1.6
	l.light_volumetric_fog_energy = fog
	add_child(l)
	l.look_at_from_position(pos, look, Vector3.UP)
	return l


func _build_lights() -> void:
	_key = _spot(Vector3(-2.0, 6.2, 3.7), HUB + Vector3(0, -0.1, 0), Color(1.0, 0.93, 0.82), KEY_E, 17.0, true, 0.2)
	_fill = _spot(Vector3(3.6, 2.6, 4.0), HUB + Vector3(0, -0.3, 0), Color(0.72, 0.82, 1.0), 2.2, 22.0, false, 0.0)
	_rim = _spot(Vector3(1.6, 4.8, -2.4), HUB + Vector3(0, 0.1, 0), Color(1.0, 0.9, 0.8), 14.0, 24.0, false, 1.2)
	_pin = _spot(Vector3(0.3, 4.6, 3.2), HUB + Vector3(0, 0.45, 0), Color(1.0, 0.97, 0.92), 0.0, 6.5, false, 1.5)
	for sx in [-1.0, 1.0]:
		_wash.append(_spot(Vector3(sx * 3.2, 0.25, -1.9), Vector3(sx * 1.6, 3.4, -3.6), _col, 6.0, 48.0, false, 0.5))
	_halo = OmniLight3D.new()
	_halo.position = HUB + Vector3(0, 0.1, -1.7)
	_halo.omni_range = 6.5
	_halo.omni_attenuation = 1.2
	_halo.light_volumetric_fog_energy = 0.6
	add_child(_halo)
	_front = OmniLight3D.new()   # 전구 불빛이 판에 비치는 느낌
	_front.position = HUB + Vector3(0, 0, 0.45)
	_front.omni_range = 2.4
	_front.light_specular = 0.2
	_front.light_volumetric_fog_energy = 0.0
	add_child(_front)
	_bolt = OmniLight3D.new()
	_bolt.position = HUB + Vector3(0.4, 2.2, 0.8)
	_bolt.omni_range = 12.0
	_bolt.light_color = Color(0.82, 0.88, 1.0)
	_bolt.light_energy = 0.0
	_bolt.light_volumetric_fog_energy = 2.0
	add_child(_bolt)
	for i in 4:  # 크리티컬 무빙 라이트
		var x := -3.3 + 2.2 * i
		var b := _spot(Vector3(x, 5.4, -2.9), Vector3(x * 0.3, 1.0, 1.0), Color.WHITE, 0.0, 5.5, false, 9.0)
		b.visible = false
		_beams.append(b)


# ---------- HUD ----------

func _glass(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.025, 0.028, 0.05, 0.74)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 14
	sb.anti_aliasing_size = 1.2
	return sb


const PAPER := Color(0.955, 0.94, 0.905)   # 따뜻한 흰색 (순백 대신)


## 글자: Pretendard 한 가지, 굵기와 크기로만 위계를 만든다 (외곽선·그림자·번짐 없음). num: 숫자 폭 고정.
func _label(text: String, size: int, color: Color, weight := 700, parent: Node = null, num := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = Kit.font(weight, num, -int(round(size * 0.02)) if size >= 40 else 0)
	ls.font_size = size
	ls.font_color = color
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(l)
	return l


func _panel(rect: Rect2, sb: StyleBoxFlat, parent: Node) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.pivot_offset = rect.size / 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var vig := TextureRect.new()   # 화면 가장자리 어둡게
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.62)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 256
	gt.height = 256
	vig.texture = gt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.size = Vector2(1280, 720)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(vig)

	_title_sb = _glass(Color(1, 1, 1, 0.25))
	var tp := _panel(Rect2(28, 24, 248, 52), _title_sb, _hud)
	_title_lbl = _label("레전드 룰렛", 24, PAPER, 800, tp)
	_title_lbl.size = Vector2(248, 52)

	# 등급 사다리
	var head := _label("등급", 15, Color(PAPER, 0.6), 600, _hud)
	head.position = Vector2(1040, 150)
	head.size = Vector2(212, 24)
	for i in 4:
		var r := 4 - i
		var t: Dictionary = Kit.tier(r)
		var c: Color = t["color"]
		var sb := _glass(Color(c.r, c.g, c.b, 0.4))
		sb.set_border_width_all(1)
		sb.border_width_left = 4
		var p := _panel(Rect2(1040, 182 + i * 76, 212, 66), sb, _hud)
		var nm := _label(t["kor"], 21, Color(PAPER, 0.55), 700, p)
		nm.position = Vector2(0, 7)
		nm.size = Vector2(212, 30)
		var pz := _label(Store.prize_of_rank(r), 15, Color(PAPER, 0.45), 500, p)
		pz.position = Vector2(0, 36)
		pz.size = Vector2(212, 24)
		_rows[r] = {"panel": p, "sb": sb, "name": nm, "prize": pz}

	# 안내
	_prompt = _panel(Rect2(340, 632, 440, 56), _glass(Color(1, 1, 1, 0.35)), _hud)
	var pl := _label("스페이스 또는 터치로 룰렛 돌리기", 22, PAPER, 700, _prompt)
	pl.size = Vector2(440, 56)
	var tsb := _glass(Color(1, 1, 1, 0.0))  # 글자 뒤 어두운 판 (외곽선 대신)
	tsb.bg_color = Color(0.03, 0.03, 0.04, 0.84)
	tsb.set_border_width_all(0)
	tsb.set_corner_radius_all(40)
	_tense = _panel(Rect2(390, 610, 340, 80), tsb, _hud)
	var tl := _label("멈추나…?!", 46, PAPER, 800, _tense)
	tl.size = Vector2(340, 80)
	_tense.visible = false

	# 등급 배너
	_banner = Control.new()
	_banner.position = Vector2(60, 400)
	_banner.size = Vector2(1000, 220)
	_banner.pivot_offset = Vector2(500, 110)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	_hud.add_child(_banner)
	var bsb := _glass(Color(1, 1, 1, 0.0))  # 어두운 판 + 등급 색 선 하나 + 굵은 글자
	bsb.bg_color = Color(0.03, 0.03, 0.04, 0.88)
	bsb.set_border_width_all(0)
	bsb.set_corner_radius_all(16)
	var plate := _panel(Rect2(200, 22, 600, 176), bsb, _banner)
	_banner_mark = ColorRect.new()
	_banner_mark.position = Vector2(270, 26)
	_banner_mark.size = Vector2(60, 5)
	_banner_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(_banner_mark)
	_banner_big = _label("", 74, PAPER, 900, plate)
	_banner_big.position = Vector2(0, 36)
	_banner_big.size = Vector2(600, 90)
	_banner_sub = _label("", 26, Color(PAPER, 0.8), 600, plate)
	_banner_sub.position = Vector2(0, 124)
	_banner_sub.size = Vector2(600, 36)

	# 결과
	_result_sb = _glass(Color(1, 1, 1, 0.5))
	_result_sb.bg_color = Color(0.02, 0.022, 0.04, 0.86)
	_result_sb.bg_color = Color(0.03, 0.03, 0.04, 0.9)
	_result_sb.set_border_width_all(0)
	_result_sb.set_corner_radius_all(16)
	_result = _panel(Rect2(190, 560, 740, 128), _result_sb, _hud)
	_result_mark = ColorRect.new()   # 등급 색은 이 짧은 선 하나에만
	_result_mark.position = Vector2(340, 0)
	_result_mark.size = Vector2(60, 4)
	_result_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_child(_result_mark)
	_result_big = _label("", 56, PAPER, 900, _result)
	_result_big.position = Vector2(0, 10)
	_result_big.size = Vector2(740, 74)
	_result_sub = _label("", 22, Color(PAPER, 0.75), 600, _result)
	_result_sub.position = Vector2(0, 84)
	_result_sub.size = Vector2(740, 32)
	_result.visible = false

	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.size = Vector2(1280, 720)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_flash_rect)


func _light_row(r: int) -> void:
	var row: Dictionary = _rows[r]
	var c: Color = Kit.tier(r)["color"]
	var sb: StyleBoxFlat = row["sb"]
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.94)  # 달성한 등급: 짙은 판 + 밝은 글자, 등급 색은 테두리에만 (빛 번짐 없음)
	sb.border_color = c
	sb.border_width_left = 7
	(row["name"] as Label).label_settings.font_color = PAPER
	(row["name"] as Label).label_settings.font = Kit.font(800)
	(row["prize"] as Label).label_settings.font_color = Color(PAPER, 0.85)
	var p: Panel = row["panel"]
	p.scale = Vector2(1.12, 1.12)
	create_tween().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_banner(lv: int) -> void:
	var t: Dictionary = Kit.tier(lv)
	var c: Color = t["color"]
	_banner_big.text = "%s 등급" % t["kor"]
	_banner_mark.color = c
	_banner_sub.text = "%s 확보" % Store.prize_of_rank(lv)
	_banner.scale = Vector2(1.35, 1.35)
	_banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_banner, "modulate:a", 1.0, 0.1)
	tw.tween_interval(0.75)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.25)


# ---------- 입력 ----------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not _done:
			_done = true
			finished.emit(false)
	elif event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_go()


func _go() -> void:
	if _state != "ready" or _now < 0.4 or _done:
		return
	_snap("spin", 1.2)
	_state = "run"
	_el = 0.0
	_prompt.visible = false
	_punch = 0.5
	Kit.sfx("go")
	Kit.sfx("swing", -4.0)


# ---------- 진행 ----------

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	_now += dt
	_el += dt
	var slowing := false
	match _state:
		"ready":
			_theta += _omega * dt
		"run":
			var step: Array = _script[0]
			if step[0] == "boom":
				_script.pop_front()
				_el = 0.0
				_boom(step[1])
			elif step[0] == "final":
				var dist := fposmod(_landing - _theta, 360.0)
				var w := maxf(_omega, 60.0)
				while 3.0 * dist / w < FINAL_MIN_S:
					dist += 360.0
				_final = [_theta, dist, 3.0 * dist / w]
				_state = "final"
				_el = 0.0
			else:
				slowing = step[0] == "slow"
				_omega += (float(step[2]) - _omega) * minf(1.0, dt * (3.4 if slowing else 7.0))
				_theta += _omega * dt
				if slowing:
					if _riser_for != _script.size():
						_riser_for = _script.size()
						Kit.sfx("riser", -3.0)
					if _now - _last_heart > 0.43:
						_last_heart = _now
						Kit.sfx("heart")
				if _el >= float(step[1]):
					_script.pop_front()
					_el = 0.0
		"final":
			var t := clampf(_el / float(_final[2]), 0.0, 1.0)
			_theta = float(_final[0]) + float(_final[1]) * (1.0 - pow(1.0 - t, 3.0))
			_omega = 3.0 * float(_final[1]) / float(_final[2]) * pow(1.0 - t, 2.0)
			if _omega < 90.0 and t < 1.0 and _now - _last_heart > 0.52:
				_last_heart = _now
				Kit.sfx("heart")
			if t >= 1.0:
				_omega = 0.0
				_land()

	# 핀이 포인터를 튕김
	var idx := _slice_at(_theta)
	if idx != _last_idx:
		if _last_idx != -1:
			_flap = -(16.0 + minf(_omega, 700.0) / 30.0)
			if _state != "ready" and _now - _last_tick > 0.045:
				_last_tick = _now
				Kit.sfx("tick", -5.0)
		_last_idx = idx
	_flap += (0.0 - _flap) * minf(1.0, dt * 13.0)
	_visuals(dt, slowing)
	if _snap_dir != "":
		if slowing and _el > 0.8 and not _snapped.has("slow%d" % _level):
			_snapped["slow%d" % _level] = true
			_snap("slow%d" % _level)
		if _state == "final" and _omega < 45.0 and not _snapped.has("creep"):
			_snapped["creep"] = true
			_snap("creep")
		for sn in _snaps.duplicate():
			if _now >= float(sn[0]):
				_snaps.erase(sn)
				_save_snap(sn[1])


## 개발용: 환경변수 ROULETTE_SNAP=<폴더> 가 있으면 연출 주요 순간(게임 시간 기준)을 PNG 로 저장
func _snap(tag: String, delay := 0.0) -> void:
	if _snap_dir != "":
		_snaps.append([_now + delay, tag])


func _boom(lv: int) -> void:
	_snap("boom%d" % lv, 0.1)
	_snap("boost%d" % lv, 0.75)
	_level = lv
	_boom_at = _now
	_shake = 1.0
	_flash = 1.0
	_punch = 1.0
	Kit.sfx("boom")
	Kit.sfx("tier%d" % lv)
	if lv == Kit.TOP_TIER:
		Kit.sfx("zap")
		for b in _beams:
			b.visible = true
		_sparks.emitting = true
	_light_row(lv)
	_show_banner(lv)
	var c: Color = Kit.tier(lv)["color"]
	_title_sb.border_color = c
	_burst(HUB + Vector3(0, 0, 0.15), c, 70 + 30 * lv, 3.0 + 0.6 * lv, 0.9)


func _save_snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_snap_dir.path_join("%s_r%d.png" % [tag, rank]))


func _land() -> void:
	_snap("land", 0.7)
	_snap("party1", 2.3)
	_snap("party2", 3.6)
	_state = "land"
	_el = 0.0
	_sparks.emitting = false
	var got: Dictionary = _slices[_slice_at(_theta)]
	print("roulette: rank=%d prize=%s landed=%s(rank %d) near_miss=%s -> %s" % [rank, prize, got["name"], got["rank"], _near_miss,
		"OK" if got["name"] == prize else "MISMATCH"])
	_hl.visible = true
	_shade.visible = true
	var c: Color = Kit.tier(rank)["color"]
	_result.visible = true
	_result.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(_result, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if rank > 0:
		_result_mark.color = c
		_result_big.text = prize
		_result_sub.text = "%s 등급 당첨" % Kit.tier(rank)["kor"]
		_shake = 0.6
		_flash = 0.5
		Kit.sfx("coin")
		_burst(HUB + Vector3(0, 0.45, 0.15), c, 60 + 20 * rank, 2.5, 1.0)
		await get_tree().create_timer(1.0).timeout
		if _done:
			return
		_land_zoom = 0.12
		var d := Kit.celebrate(rank, prize, false)
		_party(d)
		await get_tree().create_timer(d).timeout
	else:
		_sad = true
		_result_mark.color = Color(PAPER, 0.4)
		_result_big.text = "아깝다… 꽝" if _near_miss else "꽝"
		_result_big.label_settings.font_color = Color(PAPER, 0.82)
		_result_sub.text = "다음엔 등급이 터질지도 몰라요"
		Kit.sfx("groan")
		await get_tree().create_timer(1.3).timeout
		_land_zoom = 0.45
		await get_tree().create_timer(1.3).timeout
	if not _done:
		_done = true
		print("roulette: duration %.1fs (game time)" % _now)
		finished.emit(true)


# ---------- 매 프레임 연출 ----------

func _visuals(dt: float, slowing: bool) -> void:
	_wheel.rotation.z = deg_to_rad(_theta)
	_face_mat.set_shader_parameter("blur_mix", clampf((_omega - 170.0) / 380.0, 0.0, 1.0))
	var w := [0.14, 0.24, 0.3, 0.32]
	for i in 4:
		(_flap_segs[i] as Node3D).rotation.z = deg_to_rad(_flap * w[i] * 1.0)

	var spinning := _state == "run" or _state == "final"
	var crit := _level == Kit.TOP_TIER and spinning
	var tier_c: Color = Kit.tier(_level)["color"]
	_col = _col.lerp(tier_c if _level > 0 else Color(0.3, 0.36, 0.78), minf(1.0, dt * 6.0))
	var dim_t := 0.0
	if slowing:
		dim_t = clampf(_el / 0.45, 0.0, 1.0)
	elif _state == "final" and _omega < 150.0:
		dim_t = 0.75 * clampf((150.0 - _omega) / 150.0, 0.0, 1.0)
	elif _state == "land":
		dim_t = 0.7 if _sad else 0.25
	_dim = lerpf(_dim, dim_t, minf(1.0, dt * 5.0))
	_flash = maxf(0.0, _flash - dt * 3.0)
	_shake = maxf(0.0, _shake - dt * 3.0)
	_punch = maxf(0.0, _punch - dt * 3.5)
	var beat := 0.5 + 0.5 * sin(_now * TAU / 0.43)
	var lit := 1.0 - 0.86 * _dim

	# 번쩍임 (크리티컬: 번개처럼 불규칙)
	if crit:
		_strobe_t -= dt
		if _strobe_t <= 0.0:
			_strobe_t = randf_range(0.05, 0.16)
			_strobe = randf_range(0.5, 1.0) if randf() < 0.45 else 0.0
			if _strobe > 0.0 and randf() < 0.3:
				Kit.sfx("zap", -10.0)
	else:
		_strobe = 0.0
	_bolt.light_energy = _strobe * 9.0 + _flash * 6.0

	_key.light_energy = KEY_E * lit + _flash * KEY_E * 0.5
	_key.light_color = Color(1.0, 0.93, 0.82).lerp(Color(0.6, 0.7, 1.0), 0.7 if _sad else 0.0)
	_fill.light_energy = 2.2 * lit
	_rim.light_energy = 10.0 * lit
	_rim.light_color = Color(1.0, 0.9, 0.8).lerp(_col, 0.6 if _level > 0 else 0.0)
	_pin.light_energy = 26.0 * _dim * (0.85 + 0.15 * beat) * (0.5 if _sad else 1.0)
	var wash_e := (5.0 + 1.6 * _level) * (1.0 - 0.95 * _dim) + _flash * 14.0
	for l in _wash:
		l.light_energy = wash_e
		l.light_color = _col
	_halo.light_color = _col
	_halo.light_energy = (1.2 + 0.6 * _level) * (1.0 - 0.9 * _dim) + _flash * 5.0
	_env.ambient_light_energy = 0.22 * (1.0 - 0.6 * _dim)
	_fairy_mat.emission = WARM.lerp(_col, 0.75 if _level > 0 else 0.0)
	_fairy_mat.emission_energy_multiplier = 5.0 * (1.0 - 0.8 * _dim)
	_under_mat.emission = WARM.lerp(_col, 0.9 if _level > 0 else 0.0)
	_under_mat.emission_energy_multiplier = (2.0 + _level) * (1.0 - 0.8 * _dim)
	_jewel_mat.emission = _col if _level > 0 else WARM
	_jewel_mat.emission_energy_multiplier = 1.5 + 2.0 * _level + 3.0 * _flash

	# 전구 달리기
	_chase += dt / maxf(0.04, 0.22 - _omega / 5000.0)
	var step := int(_chase)
	var since := _now - _boom_at
	var all_blink := (since < 0.55 and int(since / 0.07) % 2 == 0) or (_state == "land" and rank > 0 and int(_el / 0.16) % 2 == 0)
	var bulb_c := WARM.lerp(tier_c, 0.8) if _level > 0 else WARM
	var avg := 0.0
	for i in N_BULBS:
		var on := all_blink or (i + step) % 4 == 0 or (_level >= 2 and posmod(i - step, 7) == 0)
		if _level >= 3 and spinning:
			on = on or (i + step) % 2 == 0
		var e := 6.5 if on else 0.25
		if _state == "ready":
			e = 3.0 + 2.5 * sin(_now * 2.4 + i * TAU * 3.0 / N_BULBS)
		if slowing:
			e = 0.3 + (2.2 * beat if (i + step) % 2 == 0 else 0.0)
		if _sad:
			e = 0.12 if _el * 14.0 > float(i) else e
		if crit and _strobe > 0.0 and randf() < 0.3:
			e = 12.0
		_bulb_e[i] = lerpf(_bulb_e[i], e, minf(1.0, dt * 20.0))
		avg += _bulb_e[i]
		var bm: StandardMaterial3D = _bulb_mats[i]
		bm.emission = bulb_c
		bm.emission_energy_multiplier = _bulb_e[i]
	_front.light_color = bulb_c
	_front.light_energy = avg / N_BULBS * 0.22

	# 무빙 라이트 (크리티컬)
	for i in _beams.size():
		var b: SpotLight3D = _beams[i]
		if not b.visible:
			continue
		var ph := _now * 2.3 + i * 1.7
		var tgt := Vector3(sin(ph) * 3.2 + (i - 1.5) * 0.6, 1.2 + 0.8 * sin(ph * 0.7 + i), 1.5 + cos(ph * 1.3) * 1.5)
		b.look_at(tgt, Vector3.UP)
		b.light_color = tier_c.lerp(Color.WHITE, 0.5 + 0.5 * sin(ph * 2.0))
		b.light_energy = (40.0 if _state != "land" else 14.0) * (1.0 - 0.8 * _dim)

	# 멈춘 칸 강조
	if _state == "land":
		_lit = minf(1.0, _lit + dt * 4.0)
		var hc: Color = tier_c.lerp(Color.WHITE, 0.3) if rank > 0 else Color(0.6, 0.66, 0.9)
		_hl_mat.albedo_color = Color(hc.r, hc.g, hc.b, _lit * (0.1 + 0.09 * sin(_now * 9.0)) * (0.5 if _sad else 1.0))
		_shade_mat.albedo_color.a = _lit * 0.55

	# 카메라
	var zt := 0.0
	if _state == "run":
		zt = 0.55 if slowing else 0.06
	elif _state == "final":
		zt = lerpf(0.15, 1.0, clampf(1.0 - _omega / 420.0, 0.0, 1.0))
	elif _state == "land":
		zt = _land_zoom
	_zoom = lerpf(_zoom, zt, minf(1.0, dt * (2.4 if zt > _zoom else 1.5)))
	var z := smoothstep(0.0, 1.0, _zoom)
	var pos := HUB + CAM_WIDE.lerp(CAM_CLOSE, z)
	var tgt := HUB + TGT_WIDE.lerp(TGT_CLOSE, z)
	pos += Vector3(sin(_now * 0.5) * 0.035, sin(_now * 0.37) * 0.02, cos(_now * 0.31) * 0.03)
	var amp := 0.03 * (1.0 + 0.35 * _level) * _shake * _shake
	if crit:
		amp += 0.004
	pos += Vector3(randf_range(-amp, amp), randf_range(-amp, amp), 0)
	pos += (tgt - pos).normalized() * 0.35 * _punch
	_cam.look_at_from_position(pos, tgt, Vector3.UP)
	_cam.fov = lerpf(34.0, 30.0, z) - 3.0 * _punch + 0.6 * _dim * beat
	_cam_attr.dof_blur_far_distance = pos.distance_to(tgt) + 0.9
	_env.tonemap_exposure = 1.0 + 0.2 * _flash

	# HUD
	_flash_rect.color.a = _flash * _flash * 0.38
	_tense.visible = slowing
	if slowing:
		var s := 1.0 + 0.07 * sin(_now * 20.0)
		_tense.scale = Vector2(s, s)
	if _state == "ready":
		_prompt.modulate.a = 0.78 + 0.22 * sin(_now * 4.0)


# ---------- 입자 ----------

func _spark_material(c: Color, energy: float) -> StandardMaterial3D:
	var m := Kit.emissive(c, energy)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if _soft == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	m.albedo_texture = _soft
	m.emission_texture = _soft
	return m


## 빛 입자가 사방으로 터짐 (등급 터질 때 / 불꽃놀이)
func _burst(pos: Vector3, c: Color, amount: int, speed: float, life: float, light := false) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.3
	p.damping_max = speed * 0.5
	p.gravity = Vector3(0, -1.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(0.7, 0.7))
	cv.add_point(Vector2(1, 0))
	p.scale_amount_curve = cv
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.75), Color(c.r, c.g, c.b, 0.7), Color(c.r, c.g, c.b, 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.022, 0.022)
	q.material = _spark_material(Color.WHITE, 8.0)
	p.mesh = q
	add_child(p)
	p.emitting = true
	if light:
		var l := OmniLight3D.new()
		l.position = pos
		l.light_color = c
		l.omni_range = 5.0
		l.light_energy = 5.0
		l.light_volumetric_fog_energy = 2.0
		add_child(l)
		var tw := create_tween()
		tw.tween_property(l, "light_energy", 0.0, life * 0.8)
		tw.tween_callback(l.queue_free)
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


## 당첨 축하: 색종이 대포 + 뒤쪽 불꽃 (등급 높을수록 많이)
func _party(dur: float) -> void:
	var c: Color = Kit.tier(rank)["color"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	var cs := Color.from_hsv(c.h, 0.95, 0.75)
	g.colors = PackedColorArray([cs, Color(0.85, 0.55, 0.05), Color(0.8, 0.8, 0.8), cs.darkened(0.3), Color(0.9, 0.7, 0.1), Color.from_hsv(fposmod(c.h + 0.08, 1.0), 0.9, 0.7)])
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.roughness = 0.45
	var waves := 1 + (rank + 1) / 2
	for wv in waves:
		for sx in [-1.0, 1.0]:
			var p := CPUParticles3D.new()
			p.position = Vector3(sx * 2.3, 0.3, 1.2)
			p.one_shot = true
			p.explosiveness = 0.92
			p.amount = 90 + 45 * rank
			p.lifetime = 4.2
			p.direction = Vector3(-sx * 0.42, 1.0, -0.12)
			p.spread = 20.0
			p.initial_velocity_min = 4.5
			p.initial_velocity_max = 9.5
			p.damping_min = 1.6
			p.damping_max = 2.6
			p.gravity = Vector3(0, -3.0, 0)
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.angular_velocity_min = -420.0
			p.angular_velocity_max = 420.0
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.3
			p.color_initial_ramp = g
			var q := QuadMesh.new()
			q.size = Vector2(0.06, 0.035)
			q.material = cm
			p.mesh = q
			add_child(p)
			p.emitting = false
			get_tree().create_timer(wv * 1.3 + 0.02).timeout.connect(func():
				p.emitting = true
				Kit.sfx("pop", -4.0))
	var shots := 2 + rank * 3
	for i in shots:
		var delay := 0.15 + (dur - 1.0) * i / shots + randf() * 0.15
		get_tree().create_timer(delay).timeout.connect(func():
			var fc := c if rank < Kit.TOP_TIER else Color.from_hsv(randf(), 0.75, 1.0)
			_burst(Vector3(randf_range(-3.4, 3.6), randf_range(2.6, 4.3), randf_range(-2.4, -1.0)), fc, 110, 4.2, 1.5, true))
