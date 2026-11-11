extends Node3D
## 펀치머신 3D 장면. 전부 코드로 조립 (기본 도형 + PBR 재질 + 네온 발광 + 후처리).

const NEON := Color(0.25, 0.8, 1.0)

var score_label: Label
var bag_pivot: Node3D


func _ready() -> void:
	_build_env()
	_build_room()
	_build_machine()
	_build_camera()


# ---------- 도우미 ----------

func _mat(color: Color, metallic := 0.0, rough := 0.5, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _tube(parent: Node3D, length: float, pos: Vector3, rot: Vector3, color: Color, energy := 3.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.011
	mesh.bottom_radius = 0.011
	mesh.height = length
	mi.mesh = mesh
	mi.material_override = _mat(color, 0.0, 0.3, color, energy)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


# ---------- 장면 ----------

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.008, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.18, 0.3)
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.8, 0.85, 1.0)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := SpotLight3D.new()  # 위에서 기계를 비추는 주 조명
	key.position = Vector3(0.6, 4.6, 3.0)
	key.light_energy = 26.0
	key.spot_range = 12.0
	key.spot_angle = 30.0
	key.spot_attenuation = 0.6
	key.shadow_enabled = true
	key.light_color = Color(1.0, 0.95, 0.9)
	add_child(key)
	key.look_at(Vector3(0, 1.1, 0))
	var fill := OmniLight3D.new()  # 정면 보조광
	fill.position = Vector3(0.8, 1.8, 3.2)
	fill.light_energy = 1.6
	fill.omni_range = 6.0
	add_child(fill)
	for cfg in [[Vector3(-2.6, 1.6, 1.6), Color(1.0, 0.2, 0.55)], [Vector3(2.8, 2.2, 0.8), Color(0.2, 0.7, 1.0)]]:
		var o := OmniLight3D.new()  # 양옆 색 조명
		o.position = cfg[0]
		o.light_color = cfg[1]
		o.light_energy = 2.2
		o.omni_range = 7.0
		add_child(o)


func _build_room() -> void:
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mi.mesh = plane
	floor_mi.material_override = _mat(Color(0.03, 0.03, 0.045), 0.85, 0.16)  # 젖은 듯 반사되는 바닥
	add_child(floor_mi)
	_box(self, Vector3(18, 7, 0.3), Vector3(0, 3.5, -4.5), _mat(Color(0.05, 0.05, 0.08), 0.2, 0.7))
	# 뒤쪽 벽 네온 사인
	var signs := [
		[Vector3(-3.4, 3.2, -4.3), Vector3(2.2, 0.08, 0.05), Color(1.0, 0.15, 0.5)],
		[Vector3(-3.4, 2.5, -4.3), Vector3(1.4, 0.08, 0.05), Color(1.0, 0.15, 0.5)],
		[Vector3(3.3, 3.4, -4.3), Vector3(0.08, 1.6, 0.05), Color(0.2, 0.75, 1.0)],
		[Vector3(4.0, 3.4, -4.3), Vector3(0.08, 1.6, 0.05), Color(0.2, 0.75, 1.0)],
		[Vector3(3.65, 2.6, -4.3), Vector3(0.78, 0.08, 0.05), Color(0.2, 0.75, 1.0)],
		[Vector3(0.0, 4.6, -4.3), Vector3(3.0, 0.08, 0.05), Color(0.7, 0.35, 1.0)],
	]
	for s in signs:
		_box(self, s[1], s[0], _mat(s[2], 0.0, 0.3, s[2], 3.5))
	# 양옆의 다른 오락기 (배경용)
	for x in [-2.6, 2.7]:
		var cab := _box(self, Vector3(0.9, 1.9, 0.8), Vector3(x, 0.95, -1.6), _mat(Color(0.06, 0.06, 0.09), 0.7, 0.4))
		cab.rotation_degrees.y = 18.0 if x < 0 else -18.0
		var c := Color(1.0, 0.5, 0.15) if x < 0 else Color(0.4, 1.0, 0.6)
		_box(cab, Vector3(0.7, 0.5, 0.02), Vector3(0, 0.45, 0.41), _mat(c * 0.3, 0.0, 0.2, c, 1.2))


func _build_machine() -> void:
	var m := Node3D.new()
	add_child(m)
	var metal := _mat(Color(0.2, 0.21, 0.28), 0.85, 0.3)
	var dark := _mat(Color(0.02, 0.02, 0.035), 0.5, 0.35)
	_box(m, Vector3(1.24, 0.12, 0.96), Vector3(0, 0.06, 0), metal)            # 받침
	_box(m, Vector3(1.1, 2.2, 0.8), Vector3(0, 1.22, 0), metal)                # 몸통
	_box(m, Vector3(1.18, 0.3, 0.88), Vector3(0, 2.47, 0), metal)              # 간판 박스
	_box(m, Vector3(0.9, 0.95, 0.04), Vector3(0, 1.02, 0.39), dark)            # 샌드백 홈
	_box(m, Vector3(0.94, 0.44, 0.03), Vector3(0, 1.95, 0.395), dark)          # 점수판 테두리
	for x in [-0.57, 0.57]:
		_tube(m, 2.2, Vector3(x, 1.22, 0.41), Vector3.ZERO, NEON)
	for y in [0.14, 2.3, 2.62]:
		_tube(m, 1.14, Vector3(0, y, 0.43), Vector3(0, 0, 90), NEON)

	# 점수판: 2D 글자를 그려서 빛나는 화면으로 붙임
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 260)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var back := ColorRect.new()
	back.color = Color(0.05, 0.0, 0.01)
	back.size = Vector2(640, 260)
	vp.add_child(back)
	score_label = Label.new()
	score_label.text = "000"
	score_label.size = Vector2(640, 260)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DIN Condensed", "Bahnschrift", "Impact", "Arial"])
	var ls := LabelSettings.new()
	ls.font = f
	ls.font_size = 230
	ls.font_color = Color(1.0, 0.25, 0.2)
	score_label.label_settings = ls
	vp.add_child(score_label)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.86, 0.36)
	screen.mesh = quad
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = vp.get_texture()
	sm.emission_enabled = true
	sm.emission_texture = vp.get_texture()
	sm.emission_energy_multiplier = 1.8
	sm.roughness = 0.1
	screen.material_override = sm
	screen.position = Vector3(0, 1.95, 0.415)
	m.add_child(screen)

	var title := Label3D.new()
	title.text = "POWER PUNCH"
	title.font = f
	title.font_size = 96
	title.pixel_size = 0.0022
	title.modulate = Color(1.5, 2.1, 2.5)
	title.outline_size = 0
	title.position = Vector3(0, 2.47, 0.45)
	m.add_child(title)

	# 샌드백
	bag_pivot = Node3D.new()
	bag_pivot.position = Vector3(0, 1.42, 0.44)
	m.add_child(bag_pivot)
	var arm := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 0.3
	arm.mesh = cyl
	arm.material_override = _mat(Color(0.6, 0.62, 0.7), 1.0, 0.25)
	arm.position = Vector3(0, -0.15, 0)
	bag_pivot.add_child(arm)
	var bag := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.2
	sph.height = 0.4
	bag.mesh = sph
	var leather := _mat(Color(0.75, 0.04, 0.07), 0.0, 0.42)
	leather.clearcoat_enabled = true
	leather.clearcoat = 0.6
	leather.rim_enabled = true
	leather.rim = 0.4
	bag.material_override = leather
	bag.position = Vector3(0, -0.46, 0.04)
	bag_pivot.add_child(bag)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(1.5, 1.7, 5.4)
	cam.fov = 38.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.32, 0))
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 8.0
	attr.dof_blur_far_transition = 3.0
	attr.dof_blur_amount = 0.08
	cam.attributes = attr
