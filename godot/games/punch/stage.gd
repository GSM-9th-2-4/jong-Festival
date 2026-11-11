extends Node3D
## 펀치머신 무대: 밤의 오락실 구석 + 기계 + 샌드백 + 글러브 + 조명. (연출 흐름은 game.gd)
## 단위는 미터. 기계 정면이 +Z, 플레이어(카메라)는 +Z 쪽에 서 있음.

const Geo := preload("res://games/punch/geo.gd")

const PIVOT := Vector3(0, 1.72, 0.17)        # 샌드백 경첩
const DISPLAY := Vector3(0, 2.035, 0.392)     # 점수판 중심
const DISP_SIZE := Vector2(0.60, 0.284)
const GRID := Vector2i(38, 18)                # LED 도트 수 (5x7 글자를 2배로)
const METER_N := 48
const WALL_Z := -2.1
const KEY_E := 9.0
const DOWN_E := 2.6
const EXPO := 1.0

const FONT := {
	"0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}

const LED_SHADER := "
shader_type spatial;
uniform sampler2D tex : filter_nearest, repeat_disable;
uniform vec2 grid = vec2(38.0, 18.0);
uniform vec3 tint : source_color = vec3(1.0, 0.24, 0.1);
uniform float energy = 5.0;
uniform float flick = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = UV * grid;
	vec2 id = floor(g);
	float d = length(fract(g) - 0.5);
	vec4 s = texture(tex, (id + 0.5) / grid);
	float dotm = smoothstep(0.47, 0.36, d);
	float core = smoothstep(0.34, 0.0, d);
	float fl = 1.0 - flick * step(0.5, hash(id + floor(TIME * 22.0)));
	vec3 on = (tint + vec3(0.45) * core) * energy * s.r * fl;
	vec3 mark = vec3(1.0, 0.97, 0.9) * energy * 0.7 * s.g;
	vec3 off = tint * 0.045 * (1.0 - s.r);
	ALBEDO = vec3(0.01);
	ROUGHNESS = 0.4;
	EMISSION = (max(on, mark) + off) * dotm;
}
"

var cam: Camera3D
var _attr: CameraAttributesPractical
var _env: Environment
var _rng := RandomNumberGenerator.new()

var _m_body: StandardMaterial3D
var _m_chrome: StandardMaterial3D
var _m_steel: StandardMaterial3D
var _m_dark: StandardMaterial3D
var _m_accent: StandardMaterial3D
var _m_button: StandardMaterial3D
var _m_title: StandardMaterial3D
var _spark_tex: GradientTexture2D

var _bag: Node3D
var _bag_body: Node3D
var _glove: Node3D
var _disp_mat: ShaderMaterial
var _disp_img: Image
var _disp_tex: ImageTexture
var _disp_text := ""
var _disp_glitch := false
var _meter_mat: ShaderMaterial
var _meter_img: Image
var _meter_tex: ImageTexture
var _meter_n := -1
var _cracks: MeshInstance3D
var _disp_light: OmniLight3D

var _key: SpotLight3D
var _down: SpotLight3D
var _rim: SpotLight3D
var _fill: OmniLight3D
var _accent_light: OmniLight3D
var _floor_light: OmniLight3D
var _cam_pos := Vector3.ZERO
var _cam_basis := Basis.IDENTITY


func _ready() -> void:
	_rng.seed = 11
	_materials()
	_environment()
	_room()
	_machine()
	_bag_build()
	_glove_build()
	_lights()
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 60.0
	_attr = CameraAttributesPractical.new()
	_attr.dof_blur_far_enabled = true
	_attr.dof_blur_far_transition = 2.2
	_attr.dof_blur_near_enabled = true
	_attr.dof_blur_near_distance = 0.3
	_attr.dof_blur_near_transition = 0.3
	_attr.dof_blur_amount = 0.07
	cam.attributes = _attr
	add_child(cam)
	cam.make_current()


# ---------- 작은 도우미 ----------

func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	(parent if parent else self).add_child(m)
	return m


func _box(size: Vector3, r: float, mat: Material, pos: Vector3, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	return _mi(Geo.rbox(size, r), mat, pos, parent, rot)


func _cyl(radius: float, height: float, mat: Material, pos: Vector3, parent: Node3D = null, rot := Vector3.ZERO, top := -1.0) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = 28
	c.rings = 1
	return _mi(c, mat, pos, parent, rot)


func _ball(scl: Vector3, mat: Material, pos: Vector3, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 40
	s.rings = 20
	var m := _mi(s, mat, pos, parent, rot)
	m.scale = scl
	return m


func _quad(size: Vector2, mat: Material, pos: Vector3, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	return _mi(q, mat, pos, parent, rot)


func _text3d(text: String, height: float, color: Color, pos: Vector3, parent: Node3D = null, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Kit.font_en()
	l.font_size = 96
	l.pixel_size = height / 70.0
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.horizontal_alignment = align
	l.position = pos
	(parent if parent else self).add_child(l)
	return l


## 네온관: 점들을 잇는 빛나는 관
func _tube(points: Array, radius: float, mat: Material, parent: Node3D, closed := false) -> void:
	var n := points.size()
	for i in (n if closed else n - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % n]
		var c := _cyl(radius, a.distance_to(b), mat, (a + b) * 0.5, parent)
		c.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for p in points:
		_ball(Vector3.ONE * radius, mat, p, parent).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _aabb(node: Node, xf := Transform3D.IDENTITY) -> AABB:
	var out := AABB()
	var first := true
	for c in node.get_children():
		var t := xf
		if c is Node3D:
			t = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var b := t * (c as MeshInstance3D).mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		var sub := _aabb(c, t)
		if sub.size != Vector3.ZERO:
			out = sub if first else out.merge(sub)
			first = false
	return out


## Poly Haven 모델을 바닥(또는 천장 top_y)에 맞춰 놓기. height: 원하는 높이(m, 0 = 원래 크기)
func _prop(id: String, pos: Vector3, yaw := 0.0, height := 0.0, hang := false) -> Node3D:
	var m := Kit.model(id)
	add_child(m)
	var box := _aabb(m)
	if box.size == Vector3.ZERO:
		return m
	var s := height / box.size.y if height > 0.0 else 1.0
	m.scale = Vector3.ONE * s
	m.rotation_degrees.y = yaw
	var c := box.get_center() * s
	var off := Vector3(c.x, (box.end.y if hang else box.position.y) * s, c.z).rotated(Vector3.UP, deg_to_rad(yaw))
	m.position = pos - off
	return m


# ---------- 재질 / 환경 ----------

func _materials() -> void:
	_m_body = Kit.plain(Color(0.018, 0.02, 0.026), 0.0, 0.3)   # 검은 유광 도장
	_m_body.clearcoat_enabled = true
	_m_body.clearcoat = 0.9
	_m_body.clearcoat_roughness = 0.1
	_m_chrome = Kit.plain(Color(0.88, 0.89, 0.92), 1.0, 0.14)
	_m_steel = Kit.pbr("metal_plate_02", Vector3(1.6, 1.6, 1), Color(0.75, 0.77, 0.82))
	_m_dark = Kit.plain(Color(0.012, 0.012, 0.014), 0.0, 0.75)
	_m_accent = Kit.emissive(Color(0.5, 0.72, 1.0), 2.0)
	_m_button = Kit.emissive(Color(1.0, 0.12, 0.1), 2.0)
	_m_button.roughness = 0.15
	_m_title = Kit.emissive(Color(1.0, 0.86, 0.7), 1.6)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_spark_tex = GradientTexture2D.new()
	_spark_tex.gradient = g
	_spark_tex.fill = GradientTexture2D.FILL_RADIAL
	_spark_tex.fill_from = Vector2(0.5, 0.5)
	_spark_tex.fill_to = Vector2(1.0, 0.5)
	_spark_tex.width = 32
	_spark_tex.height = 32


func _environment() -> void:
	var we := Kit.environment("neon_photostudio", {"show_sky": false, "ambient": 0.22, "sky_energy": 0.55, "glow": 0.55, "fog": 0.018, "exposure": EXPO})
	_env = we.environment
	_env.volumetric_fog_albedo = Color(0.82, 0.86, 1.0)
	_env.volumetric_fog_length = 24.0
	_env.volumetric_fog_ambient_inject = 0.0
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.06
	_env.adjustment_saturation = 1.06
	_env.ssr_fade_in = 0.25
	_env.ssr_fade_out = 2.5
	add_child(we)


func _room() -> void:
	var floor_mat := Kit.pbr("floor_tiles_06", Vector3(13, 13, 1), Color(0.62, 0.62, 0.66))
	floor_mat.roughness = 0.42   # 왁스 칠한 바닥: 네온이 비침
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 16)
	_mi(plane, floor_mat, Vector3(0, 0, 2.0))

	var brick := Kit.pbr("dark_brick_wall", Vector3(8, 2.4, 1), Color(0.8, 0.78, 0.8))
	_quad(Vector2(16, 4.8), brick, Vector3(0, 2.4, WALL_Z))
	var side := Kit.pbr("dark_brick_wall", Vector3(6, 2.4, 1), Color(0.6, 0.6, 0.65))
	_quad(Vector2(12, 4.8), side, Vector3(-5.2, 2.4, 2.0), null, Vector3(0, 90, 0))
	_quad(Vector2(12, 4.8), side, Vector3(5.2, 2.4, 2.0), null, Vector3(0, -90, 0))
	_quad(Vector2(16, 12), _m_dark, Vector3(0, 4.8, 2.0), null, Vector3(90, 0, 0))  # 천장
	_box(Vector3(16, 0.12, 0.03), 0.008, _m_dark, Vector3(0, 0.06, WALL_Z + 0.015))  # 걸레받이

	# 고무 매트 (플레이어가 서는 자리)
	_box(Vector3(1.3, 0.014, 1.0), 0.006, Kit.pbr("rubber_tiles", Vector3(2, 2, 1)), Vector3(0, 0.007, 1.0))

	# 벽의 네온사인
	var neon := Node3D.new()
	neon.position = Vector3(0, 0, WALL_Z + 0.07)
	add_child(neon)
	var pink := Kit.emissive(Color(1.0, 0.12, 0.42), 5.0)
	var cyan := Kit.emissive(Color(0.1, 0.75, 1.0), 5.0)
	var amber := Kit.emissive(Color(1.0, 0.55, 0.1), 5.0)
	var bolt := []
	for p in [Vector2(0.14, 0.5), Vector2(-0.18, -0.02), Vector2(0.03, -0.02), Vector2(-0.12, -0.5), Vector2(0.22, 0.1), Vector2(0.02, 0.1)]:
		bolt.append(Vector3(-1.62 + p.x, 2.12 + p.y, 0))
	_tube(bolt, 0.013, amber, neon, true)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.66
	ring.outer_radius = 0.69
	ring.rings = 72
	_mi(ring, cyan, Vector3(-1.62, 2.12, 0), neon, Vector3(90, 0, 0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 오른쪽: "K.O." + 밑줄
	var x0 := 1.18
	var y0 := 1.9
	_tube([Vector3(x0, y0, 0), Vector3(x0, y0 + 0.62, 0)], 0.014, pink, neon)
	_tube([Vector3(x0 + 0.34, y0 + 0.62, 0), Vector3(x0 + 0.02, y0 + 0.3, 0), Vector3(x0 + 0.36, y0, 0)], 0.014, pink, neon)
	_ball(Vector3.ONE * 0.026, pink, Vector3(x0 + 0.5, y0 + 0.01, 0), neon)
	var o := []
	for i in 24:
		var a := TAU * i / 24.0
		o.append(Vector3(x0 + 0.86 + cos(a) * 0.2, y0 + 0.31 + sin(a) * 0.31, 0))
	_tube(o, 0.014, pink, neon, true)
	_ball(Vector3.ONE * 0.026, pink, Vector3(x0 + 1.2, y0 + 0.01, 0), neon)
	_tube([Vector3(x0 - 0.05, y0 - 0.2, 0), Vector3(x0 + 1.25, y0 - 0.2, 0)], 0.011, cyan, neon)
	_tube([Vector3(x0 + 0.15, y0 - 0.3, 0), Vector3(x0 + 1.05, y0 - 0.3, 0)], 0.011, cyan, neon)
	for d in [[Vector3(-1.62, 2.12, 0.45), Color(0.35, 0.8, 1.0), 1.6], [Vector3(-1.62, 2.1, 0.25), Color(1.0, 0.6, 0.15), 0.7],
			[Vector3(1.85, 2.15, 0.45), Color(1.0, 0.15, 0.45), 2.0]]:
		var l := OmniLight3D.new()
		l.position = d[0]
		l.light_color = d[1]
		l.light_energy = d[2]
		l.omni_range = 4.5
		l.light_volumetric_fog_energy = 0.6
		neon.add_child(l)

	# 뒤쪽의 다른 게임기들 (초점 밖)
	_bg_cab(Vector3(-1.95, 0, -1.25), 16, Color(0.03, 0.05, 0.12), Color(0.2, 0.6, 1.0), Color(1.0, 0.3, 0.6))
	_bg_cab(Vector3(-2.95, 0, -1.05), 30, Color(0.1, 0.02, 0.03), Color(1.0, 0.7, 0.15), Color(0.3, 1.0, 0.6))
	_bg_cab(Vector3(2.05, 0, -1.3), -14, Color(0.06, 0.02, 0.1), Color(0.75, 0.3, 1.0), Color(0.2, 0.9, 1.0))
	_bg_cab(Vector3(3.05, 0, -1.1), -28, Color(0.02, 0.07, 0.07), Color(0.2, 1.0, 0.7), Color(1.0, 0.5, 0.2))

	_prop("metal_trash_can", Vector3(1.12, 0, -0.95), 30)
	_prop("bar_chair_round_01", Vector3(-1.12, 0, -0.55), 20)
	_prop("WetFloorSign_01", Vector3(1.45, 0, 0.55), -35)


func _bg_cab(pos: Vector3, yaw: float, body: Color, c1: Color, c2: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = yaw
	add_child(n)
	var paint := Kit.plain(body, 0.0, 0.35)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.6
	_box(Vector3(0.68, 1.82, 0.78), 0.03, paint, Vector3(0, 0.91, 0), n)
	_box(Vector3(0.7, 0.07, 0.34), 0.02, _m_dark, Vector3(0, 0.98, 0.46), n, Vector3(8, 0, 0))
	_box(Vector3(0.6, 0.5, 0.03), 0.01, _m_dark, Vector3(0, 1.36, 0.385), n, Vector3(-8, 0, 0))
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2.darkened(0.5))
	g.add_point(0.55, c1.lerp(c2, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.2, 0.0)
	gt.fill_to = Vector2(0.8, 1.0)
	gt.width = 64
	gt.height = 64
	var scr := StandardMaterial3D.new()
	scr.albedo_color = Color.BLACK
	scr.emission_enabled = true
	scr.emission_texture = gt
	scr.emission = Color.BLACK
	scr.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	scr.emission_energy_multiplier = 2.2
	scr.roughness = 0.1
	_quad(Vector2(0.52, 0.42), scr, Vector3(0, 1.36, 0.405), n, Vector3(-8, 0, 0))
	_box(Vector3(0.6, 0.15, 0.02), 0.006, Kit.emissive(c2, 2.2), Vector3(0, 1.71, 0.392), n)
	for i in 3:
		_cyl(0.016, 0.014, Kit.emissive([c1, c2, Color.WHITE][i], 2.5), Vector3(-0.1 + 0.1 * i, 1.03, 0.5), n, Vector3(8, 0, 0))
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.4, 0.75)
	l.light_color = c1.lerp(c2, 0.4)
	l.light_energy = 0.7
	l.omni_range = 2.6
	n.add_child(l)


# ---------- 기계 ----------

func _machine() -> void:
	var m := Node3D.new()
	add_child(m)
	var tread := Kit.pbr("metal_plate", Vector3(3, 3, 1), Color(0.55, 0.56, 0.6))
	tread.metallic = 0.85
	var pad := Kit.pbr("rubber_tiles", Vector3(4, 4, 1), Color(0.9, 0.9, 1.0))
	var red := Kit.plain(Color(0.2, 0.006, 0.012), 0.0, 0.3)
	red.clearcoat_enabled = true
	red.clearcoat = 0.9
	red.clearcoat_roughness = 0.08

	# 받침 + 아래 몸통
	_box(Vector3(0.92, 0.10, 0.86), 0.012, tread, Vector3(0, 0.05, -0.06), m)
	_box(Vector3(0.80, 0.98, 0.70), 0.035, _m_body, Vector3(0, 0.59, -0.08), m)
	_box(Vector3(0.70, 0.86, 0.012), 0.004, red, Vector3(0, 0.60, 0.272), m)         # 정면 빨간 패널
	_box(Vector3(0.84, 0.035, 0.74), 0.012, _m_chrome, Vector3(0, 1.085, -0.08), m)  # 상판 테두리
	_box(Vector3(0.78, 0.02, 0.68), 0.006, tread, Vector3(0, 1.105, -0.08), m)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.014, 0.88, 0.008), 0.003, _m_accent, Vector3(sx * 0.372, 0.60, 0.276), m)
		_box(Vector3(0.03, 0.9, 0.03), 0.01, _m_chrome, Vector3(sx * 0.392, 0.60, 0.262), m)
	# 동전 투입구 문
	_box(Vector3(0.30, 0.34, 0.016), 0.006, _m_steel, Vector3(0, 0.47, 0.282), m)
	_box(Vector3(0.33, 0.37, 0.008), 0.004, _m_dark, Vector3(0, 0.47, 0.279), m)
	_cyl(0.013, 0.012, _m_chrome, Vector3(0.105, 0.47, 0.293), m, Vector3(90, 0, 0))
	_box(Vector3(0.003, 0.012, 0.004), 0.001, _m_dark, Vector3(0.105, 0.47, 0.3), m)
	var slot := Kit.emissive(Color(1.0, 0.5, 0.1), 2.6)
	for sx in [-0.085, -0.03]:
		_box(Vector3(0.036, 0.058, 0.01), 0.004, _m_chrome, Vector3(sx, 0.55, 0.291), m)
		_box(Vector3(0.022, 0.042, 0.004), 0.002, slot, Vector3(sx, 0.55, 0.297), m)
	_box(Vector3(0.12, 0.05, 0.012), 0.005, _m_dark, Vector3(-0.058, 0.385, 0.291), m)
	# 스피커 그릴
	_box(Vector3(0.52, 0.12, 0.008), 0.004, _m_dark, Vector3(0, 0.215, 0.279), m)
	for i in 7:
		_box(Vector3(0.5, 0.007, 0.012), 0.003, _m_steel, Vector3(0, 0.17 + i * 0.015, 0.284), m)
	# 시작 버튼 패널
	var deck := _box(Vector3(0.5, 0.15, 0.03), 0.012, _m_steel, Vector3(0, 0.86, 0.287), m, Vector3(-14, 0, 0))
	_cyl(0.052, 0.016, _m_chrome, Vector3(0, 0, 0.02), deck, Vector3(90, 0, 0))
	_ball(Vector3(0.042, 0.042, 0.02), _m_button, Vector3(0, 0, 0.028), deck)
	_text3d("START", 0.02, Color(0.85, 0.85, 0.85), Vector3(-0.13, 0, 0.0165), deck)
	_text3d("1 PLAY", 0.02, Color(0.85, 0.85, 0.85), Vector3(0.14, 0, 0.0165), deck)

	# 샌드백 뒤 기둥 (완충 패드) + 옆 날개
	_box(Vector3(0.80, 0.68, 0.14), 0.03, _m_body, Vector3(0, 1.44, -0.36), m)
	_box(Vector3(0.62, 0.56, 0.03), 0.014, pad, Vector3(0, 1.43, -0.283), m)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.68, 0.42), 0.02, _m_body, Vector3(sx * 0.37, 1.44, -0.16), m)
		_box(Vector3(0.014, 0.6, 0.008), 0.003, _m_accent, Vector3(sx * 0.37, 1.44, 0.052), m)
		_box(Vector3(0.008, 0.56, 0.014), 0.003, _m_accent, Vector3(sx * 0.338, 1.43, -0.27), m)

	# 머리 (점수판)
	_box(Vector3(0.88, 0.58, 0.82), 0.045, _m_body, Vector3(0, 2.07, -0.03), m)
	_box(Vector3(0.90, 0.03, 0.84), 0.012, _m_chrome, Vector3(0, 1.80, -0.03), m)
	_box(Vector3(0.82, 0.012, 0.006), 0.003, _m_accent, Vector3(0, 1.826, 0.383), m)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.012, 0.44, 0.006), 0.003, _m_accent, Vector3(sx * 0.405, 2.06, 0.38), m)
	_box(Vector3(0.70, 0.36, 0.02), 0.012, _m_steel, Vector3(0, 2.01, 0.378), m)     # 점수판 테
	_box(Vector3(0.64, 0.318, 0.012), 0.006, _m_dark, Vector3(0, DISPLAY.y, 0.384), m)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_cyl(0.008, 0.008, _m_chrome, Vector3(sx * 0.335, 2.01 + sy * 0.165, 0.39), m, Vector3(90, 0, 0))

	_disp_img = Image.create(GRID.x, GRID.y, false, Image.FORMAT_RGB8)
	_disp_tex = ImageTexture.create_from_image(_disp_img)
	_disp_mat = _led_material(_disp_tex, Vector2(GRID))
	_quad(DISP_SIZE, _disp_mat, DISPLAY, m)
	var glass := StandardMaterial3D.new()   # 점수판 앞 유리
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.5, 0.55, 0.6, 0.03)
	glass.roughness = 0.04
	glass.metallic = 0.0
	glass.metallic_specular = 0.8
	_quad(Vector2(0.63, 0.31), glass, DISPLAY + Vector3(0, 0, 0.006), m)

	_meter_img = Image.create(METER_N, 2, false, Image.FORMAT_RGB8)
	_meter_tex = ImageTexture.create_from_image(_meter_img)
	_meter_mat = _led_material(_meter_tex, Vector2(METER_N, 2))
	_quad(Vector2(0.60, 0.025), _meter_mat, Vector3(0, 1.862, 0.39), m)
	for lv in range(1, 5):
		var v: int = [0, 600, 750, 900, 999][lv]
		var c: Color = Kit.tier(lv)["color"]
		var l := _text3d(str(v), 0.017, c.lerp(Color.WHITE, 0.25), Vector3(-0.30 + 0.60 * v / 999.0, 1.842, 0.3895), m,
				HORIZONTAL_ALIGNMENT_RIGHT if lv == 4 else HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		if lv == 4:
			l.position.x = 0.30
			l.offset.x = -l.font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x * 0.5

	# 제목 간판 (뒤에서 빛나는 띠)
	_box(Vector3(0.70, 0.085, 0.01), 0.004, _m_title, Vector3(0, 2.265, 0.382), m)
	_text3d("POWER  PUNCH", 0.06, Color(0.16, 0.0, 0.01), Vector3(0, 2.262, 0.3885), m)
	var art := _text3d("PUNCH", 0.15, Color(0.9, 0.88, 0.84), Vector3(0, 0.69, 0.2795), m)   # 정면 패널 글자 (도장)
	art.shaded = true
	art.rotation_degrees.z = 0
	_box(Vector3(0.56, 0.008, 0.004), 0.002, _m_chrome, Vector3(0, 0.765, 0.279), m)
	_box(Vector3(0.56, 0.008, 0.004), 0.002, _m_chrome, Vector3(0, 0.615, 0.279), m)

	# 경첩 + 아래를 비추는 등
	_box(Vector3(0.12, 0.06, 0.09), 0.012, _m_chrome, PIVOT + Vector3(0, 0.04, 0), m)
	_cyl(0.016, 0.17, _m_chrome, PIVOT, m, Vector3(0, 0, 90))
	for sx in [-1.0, 1.0]:
		_cyl(0.03, 0.012, _m_chrome, Vector3(sx * 0.2, 1.782, 0.2), m)
		_cyl(0.022, 0.004, Kit.emissive(Color(1.0, 0.9, 0.75), 6.0), Vector3(sx * 0.2, 1.775, 0.2), m)

	_cracks = _mi(_crack_mesh(), null, DISPLAY + Vector3(0, 0, 0.009), m)
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.5, 1.6, 1.8)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cracks.material_override = cm
	_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cracks.visible = false


func _led_material(tex: Texture2D, grid: Vector2) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = LED_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("grid", grid)
	return m


func _crack_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var lines := []
	var hx := DISP_SIZE.x * 0.5
	var hy := DISP_SIZE.y * 0.5
	for c in [Vector2(-0.06, 0.02), Vector2(0.17, -0.05)]:
		for i in 9:
			var a := TAU * i / 9.0 + rng.randf_range(-0.25, 0.25)
			var p: Vector2 = c
			var line := [p]
			for k in 7:
				a += rng.randf_range(-0.45, 0.45)
				p += Vector2(cos(a), sin(a)) * rng.randf_range(0.02, 0.06)
				p = Vector2(clampf(p.x, -hx, hx), clampf(p.y, -hy, hy))
				line.append(p)
				if k == 2 and rng.randf() < 0.6:  # 가지
					var q := p
					var b := a + rng.randf_range(0.6, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
					var br := [q]
					for j in 3:
						q += Vector2(cos(b), sin(b)) * rng.randf_range(0.015, 0.04)
						q = Vector2(clampf(q.x, -hx, hx), clampf(q.y, -hy, hy))
						br.append(q)
					lines.append(br)
			lines.append(line)
	return Geo.strips(lines, 0.0016)


# ---------- 샌드백 / 글러브 ----------

func _bag_build() -> void:
	_bag = Node3D.new()
	_bag.position = PIVOT
	add_child(_bag)
	_cyl(0.013, 0.13, _m_chrome, Vector3(0, -0.065, 0), _bag)
	_cyl(0.024, 0.03, _m_chrome, Vector3(0, -0.012, 0), _bag, Vector3(0, 0, 90))
	_bag_body = Node3D.new()
	_bag.add_child(_bag_body)
	var prof := Geo.smooth([Vector2(0.0, -0.475), Vector2(0.04, -0.47), Vector2(0.078, -0.452), Vector2(0.104, -0.42),
			Vector2(0.117, -0.378), Vector2(0.119, -0.335), Vector2(0.111, -0.29), Vector2(0.095, -0.245),
			Vector2(0.074, -0.2), Vector2(0.056, -0.165), Vector2(0.045, -0.14), Vector2(0.041, -0.118)], 4)
	var leather := Kit.pbr("leather_red_02", Vector3(7, 7, 1), Color(1.5, 0.13, 0.11))
	leather.roughness = 0.8
	_mi(Geo.lathe(prof, 48), leather, Vector3.ZERO, _bag_body)
	var black := Kit.pbr("leather_red_02", Vector3(6, 6, 1), Color(0.2, 0.17, 0.17))
	for i in 6:  # 박음질 띠
		var a := TAU * i / 6.0 + 0.26
		_mi(Geo.lathe(prof, 2, a - 0.045, a + 0.045, 0.0022), black, Vector3.ZERO, _bag_body)
	_cyl(0.047, 0.035, black, Vector3(0, -0.122, 0), _bag_body, Vector3.ZERO, 0.04)
	_cyl(0.03, 0.02, _m_chrome, Vector3(0, -0.1, 0), _bag_body)
	# 과녁 패치 (흰 가죽 원)
	var patch := Kit.plain(Color(0.86, 0.84, 0.8), 0.0, 0.55)
	var disc := _cyl(0.05, 0.004, patch, Vector3(0, -0.345, 0.1175), _bag_body, Vector3(84, 0, 0))
	disc.scale = Vector3(1, 1, 1)
	_cyl(0.032, 0.005, black, Vector3(0, -0.345, 0.1185), _bag_body, Vector3(84, 0, 0))
	_cyl(0.016, 0.006, patch, Vector3(0, -0.345, 0.1195), _bag_body, Vector3(84, 0, 0))


func _glove_build() -> void:
	_glove = Node3D.new()
	add_child(_glove)
	var red := Kit.pbr("leather_red_02", Vector3(5, 3, 1), Color(1.6, 0.14, 0.12))
	red.roughness = 0.72
	var white := Kit.plain(Color(0.86, 0.84, 0.8), 0.0, 0.5)
	var sleeve := Kit.plain(Color(0.006, 0.006, 0.008), 0.0, 1.0)
	sleeve.metallic_specular = 0.1
	_ball(Vector3(0.1, 0.09, 0.15), red, Vector3(0, 0, -0.12), _glove)
	_ball(Vector3(0.092, 0.082, 0.08), red, Vector3(0, 0.008, -0.185), _glove)
	_ball(Vector3(0.036, 0.04, 0.085), red, Vector3(-0.078, -0.03, -0.115), _glove, Vector3(0, 10, 0))
	_box(Vector3(0.05, 0.004, 0.11), 0.0015, Kit.plain(Color(0.015, 0.015, 0.018), 0.0, 0.6), Vector3(0, 0.0735, 0.05), _glove, Vector3(-3.3, 0, 0))
	_cyl(0.066, 0.14, red, Vector3(0, 0, 0.05), _glove, Vector3(90, 0, 0), 0.074)
	_cyl(0.076, 0.03, white, Vector3(0, 0, 0.118), _glove, Vector3(90, 0, 0), 0.077)
	_cyl(0.071, 0.012, red, Vector3(0, 0, 0.139), _glove, Vector3(90, 0, 0))
	_cyl(0.05, 0.8, sleeve, Vector3(0, 0, 0.54), _glove, Vector3(90, 0, 0), 0.066)


# ---------- 조명 ----------

func _lights() -> void:
	_key = SpotLight3D.new()   # 주 조명: 오른쪽 위 앞
	_key.position = Vector3(1.7, 3.3, 2.4)
	_key.light_color = Color(1.0, 0.9, 0.78)
	_key.light_energy = KEY_E
	_key.spot_range = 9.0
	_key.spot_angle = 26.0
	_key.spot_angle_attenuation = 0.8
	_key.shadow_enabled = true
	_key.shadow_blur = 1.6
	_key.light_volumetric_fog_energy = 0.5
	add_child(_key)
	_key.look_at(Vector3(0, 1.3, 0))

	_rim = SpotLight3D.new()   # 뒤에서 윤곽을 따는 빛
	_rim.position = Vector3(-1.5, 3.2, -1.5)
	_rim.light_color = Color(0.45, 0.65, 1.0)
	_rim.light_energy = 7.0
	_rim.spot_range = 8.0
	_rim.spot_angle = 34.0
	_rim.shadow_enabled = true
	_rim.light_volumetric_fog_energy = 1.2
	add_child(_rim)
	_rim.look_at(Vector3(0.1, 1.6, 0.1))

	_fill = OmniLight3D.new()
	_fill.position = Vector3(-2.2, 1.7, 2.2)
	_fill.light_color = Color(0.45, 0.55, 1.0)
	_fill.light_energy = 0.7
	_fill.omni_range = 6.0
	_fill.light_volumetric_fog_energy = 0.0
	add_child(_fill)

	_down = SpotLight3D.new()  # 머리 밑에서 샌드백을 비추는 등
	_down.position = Vector3(0, 1.765, 0.24)
	_down.rotation_degrees = Vector3(-90, 0, 0)
	_down.light_color = Color(1.0, 0.9, 0.76)
	_down.light_energy = DOWN_E
	_down.spot_range = 2.2
	_down.spot_angle = 52.0
	_down.shadow_enabled = true
	_down.light_volumetric_fog_energy = 0.4
	add_child(_down)

	_accent_light = OmniLight3D.new()   # 기계 LED 색
	_accent_light.position = Vector3(0, 1.5, 0.75)
	_accent_light.omni_range = 3.2
	_accent_light.light_volumetric_fog_energy = 1.5
	add_child(_accent_light)
	_floor_light = OmniLight3D.new()
	_floor_light.position = Vector3(0, 0.25, 0.7)
	_floor_light.omni_range = 2.4
	add_child(_floor_light)

	_disp_light = OmniLight3D.new()     # 점수판 빛
	_disp_light.position = DISPLAY + Vector3(0, 0, 0.3)
	_disp_light.omni_range = 1.6
	_disp_light.light_energy = 0.5
	add_child(_disp_light)


# ---------- game.gd 가 부르는 것들 ----------

func set_camera(pos: Vector3, tgt: Vector3, fov: float, off: Vector3, roll: float) -> void:
	_cam_pos = pos
	_cam_basis = Basis.looking_at(tgt - pos, Vector3.UP)
	cam.transform = Transform3D(_cam_basis, pos + _cam_basis * off)
	cam.rotate_object_local(Vector3.FORWARD, roll)
	cam.fov = fov
	var focus := pos.distance_to(Vector3(0, 1.8, 0.3))
	_attr.dof_blur_far_distance = focus + 0.9


func set_bag(theta: float, squash: float) -> void:
	_bag.rotation.x = theta
	_bag_body.scale = Vector3(1.0 + 0.1 * squash, 1.0 - 0.06 * squash, 1.0 - 0.22 * squash)


func hit_point() -> Vector3:
	return PIVOT + Vector3(0.0, -0.345, 0.125)


func display_point(x: float, y: float) -> Vector3:
	return DISPLAY + Vector3(x, y, 0.03)


func set_glove(k: float, out: float, t: float, ready: bool) -> void:
	_glove.visible = out < 0.99
	if not _glove.visible:
		return
	var b := _cam_basis
	var bob := Vector3(0.006 * sin(t * 2.6), 0.009 * sin(t * 3.4), 0.012 * sin(t * 5.9)) if ready else Vector3.ZERO
	var rest := _cam_pos + b * (Vector3(0.27, -0.235 - 0.6 * out, -0.8) + bob)
	var elbow := _cam_pos + b * Vector3(0.62, -0.85, 0.25)
	var dir_rest := (b * Vector3(-0.2, 0.3, -1.0)).normalized()
	var dir_hit := (hit_point() - elbow).normalized()
	var dir := dir_rest.slerp(dir_hit, k)
	var pos := rest.lerp(hit_point() - dir_hit * 0.235, k)
	_glove.transform = Transform3D(Basis.looking_at(dir, b.y).rotated(dir, deg_to_rad(lerpf(-22.0, -50.0, k))), pos)


func button_pulse(k: float) -> void:
	_m_button.emission_energy_multiplier = 1.0 + 3.0 * k


func set_lighting(accent: Color, level: int, dim: float, boost: float, flicker: float) -> void:
	var d := lerpf(1.0, 0.22, dim)
	_key.light_energy = KEY_E * d * flicker
	_rim.light_energy = 7.0 * lerpf(1.0, 0.5, dim)
	_rim.light_color = Color(0.45, 0.65, 1.0).lerp(accent, 0.75 if level > 0 else 0.0)
	_fill.light_energy = 0.7 * d
	_down.light_energy = DOWN_E * lerpf(1.0, 0.35, dim) * flicker
	_env.tonemap_exposure = EXPO * lerpf(1.0, 0.82, dim) * (1.0 + 0.3 * boost)
	var e := (1.0 + 0.45 * level + 6.0 * boost) * lerpf(1.0, 0.3, dim) * flicker
	_m_accent.emission = accent
	_m_accent.albedo_color = accent
	_m_accent.emission_energy_multiplier = 2.2 * e
	_accent_light.light_color = accent
	_accent_light.light_energy = (0.35 + 0.3 * level + 3.5 * boost) * lerpf(1.0, 0.4, dim) * flicker
	_floor_light.light_color = accent
	_floor_light.light_energy = (0.3 + 0.25 * level + 2.0 * boost) * lerpf(1.0, 0.4, dim)
	_m_title.emission = Color(1.0, 0.86, 0.7).lerp(accent.lerp(Color.WHITE, 0.35), 0.8 if level > 0 else 0.0)
	_m_title.emission_energy_multiplier = (1.5 + 0.25 * level + 2.0 * boost) * lerpf(1.0, 0.4, dim) * flicker


func set_display(text: String, color: Color, flick: float, glitch := false) -> void:
	_disp_mat.set_shader_parameter("tint", color)
	_disp_mat.set_shader_parameter("flick", flick)
	_meter_mat.set_shader_parameter("tint", color)
	_disp_light.light_color = color
	if text == _disp_text and not glitch and not _disp_glitch:
		return
	_disp_text = text
	_disp_glitch = glitch
	_disp_img.fill(Color.BLACK)
	var shift := _rng.randi_range(-2, 2) if glitch and _rng.randf() < 0.25 else 0
	for i in mini(3, text.length()):
		var rows: Array = FONT.get(text[i], FONT[" "])
		for y in 7:
			var row: String = rows[y]
			var sx := shift if glitch and _rng.randf() < 0.15 else 0
			for x in 5:
				if row[x] == "1":
					_disp_img.fill_rect(Rect2i(2 + i * 12 + x * 2 + sx, 2 + y * 2, 2, 2), Color.WHITE)
	if glitch:
		for n in 14:
			_disp_img.set_pixel(_rng.randi() % GRID.x, _rng.randi() % GRID.y, Color.WHITE if _rng.randf() < 0.5 else Color.BLACK)
		if _rng.randf() < 0.3:
			_disp_img.fill_rect(Rect2i(0, _rng.randi() % GRID.y, GRID.x, 1), Color.WHITE if _rng.randf() < 0.4 else Color.BLACK)
	_disp_tex.update(_disp_img)


func set_meter(frac: float) -> void:
	var n := int(round(clampf(frac, 0.0, 1.0) * METER_N))
	if n == _meter_n:
		return
	_meter_n = n
	_meter_img.fill(Color.BLACK)
	if n > 0:
		_meter_img.fill_rect(Rect2i(0, 0, n, 2), Color(1, 0, 0))
	for v in [600, 750, 900, 999]:
		var x := mini(METER_N - 1, int(METER_N * v / 999.0))
		_meter_img.fill_rect(Rect2i(x, 0, 1, 2), Color(1.0 if x < n else 0.0, 1, 0))
	_meter_tex.update(_meter_img)


func crack() -> void:
	_cracks.visible = true


## 불꽃 튀기기
func sparks(pos: Vector3, col: Color, amount: int, speed: float, life: float, size := 0.014, grav := -5.5) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3(0, 0.4, 1)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.25
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, grav, 0)
	p.damping_min = 0.8
	p.damping_max = 2.4
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.3, col)
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(5, 5, 5)
	m.albedo_texture = _spark_tex
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


## 순간 번쩍이는 빛
func flash_light(pos: Vector3, col: Color, energy: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 4.0
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)
