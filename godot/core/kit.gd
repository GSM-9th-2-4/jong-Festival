extends Node
## 공용 도구 (어디서든 `Kit.` 으로 사용). 사실적인 재질/조명, 등급, 글꼴, 효과음, 당첨 축하 연출.
## 소재는 godot/assets/ 에서 실행 중에 직접 읽음 (먼저 `python3 godot/tools/fetch_assets.py`).

const TIERS := [  # 등급 0 = 꽝. 등급 번호는 Store.rank(경품이름)
	{"name": "", "kor": "", "color": Color(0.47, 0.52, 0.71)},
	{"name": "RARE", "kor": "레어", "color": Color(0.31, 0.71, 1.0)},
	{"name": "EPIC", "kor": "에픽", "color": Color(0.78, 0.44, 1.0)},
	{"name": "LEGENDARY", "kor": "전설", "color": Color(1.0, 0.78, 0.2)},
	{"name": "CRITICAL", "kor": "크리티컬", "color": Color(1.0, 0.28, 0.38)},
]
const TOP_TIER := 4
const GOLD := Color(0.94, 0.78, 0.43)

var auto := false  ## 자동 플레이(테스트용): 게임은 이 값이 true 면 약 1초 뒤 스스로 입력한 것처럼 진행해야 함

var _tex_cache := {}
var _sfx_cache := {}
var _font_kr: SystemFont
var _font_en: SystemFont


func assets_dir() -> String:
	return ProjectSettings.globalize_path("res://assets")


func tier(rank: int) -> Dictionary:
	return TIERS[clampi(rank, 0, TOP_TIER)]


# ---------- 글꼴 ----------

func font_kr() -> SystemFont:
	if _font_kr == null:
		_font_kr = SystemFont.new()
		_font_kr.font_names = PackedStringArray(["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", "NanumGothic"])
		_font_kr.font_weight = 700
	return _font_kr


func font_en() -> SystemFont:  ## 영문/숫자 전용 (좁고 각진 글꼴)
	if _font_en == null:
		_font_en = SystemFont.new()
		_font_en.font_names = PackedStringArray(["DIN Condensed", "Bahnschrift", "Avenir Next Condensed", "Impact", "Arial"])
	return _font_en


func label_settings(size: int, color := Color.WHITE, en := false, outline := 0, shadow := true) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font_en() if en else font_kr()
	ls.font_size = size
	ls.font_color = color
	if outline > 0:
		ls.outline_size = outline
		ls.outline_color = Color(0, 0, 0.03, 0.9)
	if shadow:
		ls.shadow_size = 6
		ls.shadow_color = Color(0, 0, 0, 0.55)
		ls.shadow_offset = Vector2(0, 3)
	return ls


# ---------- 재질 ----------

func texture(path: String) -> ImageTexture:
	if not _tex_cache.has(path):
		var img := Image.load_from_file(path)
		if img == null:
			push_warning("소재 없음: " + path + "  (python3 godot/tools/fetch_assets.py 실행했는지 확인)")
			_tex_cache[path] = null
		else:
			img.generate_mipmaps()
			_tex_cache[path] = ImageTexture.create_from_image(img)
	return _tex_cache[path]


## Poly Haven 재질(색/노멀/거칠기/AO)을 붙인 사실적인 재질. id 는 assets/textures/<id>.
## uv: 무늬 반복 횟수, tint: 색 곱하기, triplanar: UV 없는 도형에도 무늬가 늘어지지 않게.
func pbr(id: String, uv := Vector3(1, 1, 1), tint := Color.WHITE, triplanar := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.uv1_scale = uv
	m.uv1_triplanar = triplanar
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var dir := assets_dir() + "/textures/" + id + "/textures"
	if not DirAccess.dir_exists_absolute(dir):
		push_warning("재질 없음: " + id)
		return m
	for f in DirAccess.get_files_at(dir):
		var p := dir + "/" + f
		if "_nor_gl" in f:
			m.normal_enabled = true
			m.normal_texture = texture(p)
		elif "_arm" in f:  # R=AO, G=거칠기, B=금속
			var t := texture(p)
			m.ao_enabled = true
			m.ao_texture = t
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			m.roughness_texture = t
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			m.metallic = 1.0
			m.metallic_texture = t
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		elif "_rough" in f:
			m.roughness_texture = texture(p)
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		elif "_diff" in f or "_coll1" in f or "_col_" in f:
			m.albedo_texture = texture(p)
	return m


func plain(color: Color, metallic := 0.0, roughness := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func emissive(color: Color, energy := 3.0) -> StandardMaterial3D:  ## 스스로 빛나는 재질 (네온, 화면)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Poly Haven 3D 모델 (assets/models/<id>). 실패하면 빈 노드.
func model(id: String) -> Node3D:
	var dir := assets_dir() + "/models/" + id
	var path := dir + "/" + id + ".gltf"
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("모델 없음: " + id)
		return Node3D.new()
	return doc.generate_scene(state) as Node3D


# ---------- 조명/환경 ----------

## 실사 환경 조명(HDRI) + 후처리가 켜진 WorldEnvironment 를 만들어 돌려줌 (add_child 는 직접).
## opts: sky_energy, bg_energy, rotation(도), ambient, glow, fog(농도), sdfgi(bool), exposure, show_sky(bool)
func environment(hdri := "studio_small_03", opts := {}) -> WorldEnvironment:
	var env := Environment.new()
	var img := Image.load_from_file(assets_dir() + "/hdris/" + hdri + ".hdr") if hdri != "" else null
	if img != null:
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = ImageTexture.create_from_image(img)
		pm.energy_multiplier = opts.get("sky_energy", 1.0)
		var sky := Sky.new()
		sky.sky_material = pm
		env.sky = sky
		env.sky_rotation = Vector3(0, deg_to_rad(opts.get("rotation", 0.0)), 0)
		env.background_mode = Environment.BG_SKY if opts.get("show_sky", true) else Environment.BG_COLOR
		env.background_energy_multiplier = opts.get("bg_energy", 1.0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = opts.get("ambient", 1.0)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.2, 0.22, 0.3)
	env.background_color = Color(0.01, 0.01, 0.02)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = opts.get("exposure", 1.0)
	env.glow_enabled = true
	env.glow_intensity = opts.get("glow", 0.45)
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.2
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssao_enabled = true
	env.ssao_intensity = 2.5
	env.ssil_enabled = true
	env.sdfgi_enabled = opts.get("sdfgi", false)
	var fog: float = opts.get("fog", 0.0)
	if fog > 0.0:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = fog
	var we := WorldEnvironment.new()
	we.environment = env
	return we


# ---------- 효과음 ----------

## 이름: move click tick go pop swing hit kick whistle net cheer groan coin drum win jackpot lose error
##       boom riser heart zap firework tier1~tier4   (assets/sfx/<이름>.wav)
func sfx(sound: String, volume_db := 0.0) -> void:
	if not _sfx_cache.has(sound):
		_sfx_cache[sound] = AudioStreamWAV.load_from_file(assets_dir() + "/sfx/" + sound + ".wav")
	if _sfx_cache[sound] == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sfx_cache[sound]
	p.volume_db = volume_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ---------- 당첨 축하 연출 (모든 게임 공용) ----------

## 등급 배너 + 폭죽을 화면 위에 띄움. 꽝(0)이면 아무것도 안 함. 연출 길이(초)를 돌려줌 — 게임은 그만큼 기다린 뒤 끝내면 됨.
func celebrate(rank: int, prize: String, banner := true) -> float:
	rank = clampi(rank, 0, TOP_TIER)
	if rank == 0:
		return 0.0
	var t: Dictionary = TIERS[rank]
	var dur := 2.4 + 0.8 * rank
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var size := get_viewport().get_visible_rect().size
	sfx("boom")
	sfx("tier%d" % rank)
	if rank >= 3:
		sfx("cheer", -3.0)

	var flash := ColorRect.new()  # 번쩍
	flash.color = Color(1, 1, 1, 0.8)
	flash.size = size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	create_tween().tween_property(flash, "color:a", 0.0, 0.35)

	if banner:
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.size = Vector2(size.x, 260)
		box.position = Vector2(0, size.y * 0.5 - 150)
		box.pivot_offset = box.size / 2
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(box)
		var big := Label.new()
		big.text = t["name"] + "!".repeat(rank)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.label_settings = label_settings(150, (t["color"] as Color).lerp(Color.WHITE, 0.35), true, 14)
		box.add_child(big)
		var sub := Label.new()
		sub.text = "%s 등급   ·   %s" % [t["kor"], prize]
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.label_settings = label_settings(40, Color.WHITE, false, 8)
		box.add_child(sub)
		box.scale = Vector2(2.6, 2.6)
		box.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(box, "modulate:a", 1.0, 0.1)
		tw.tween_interval(1.1)
		tw.tween_property(box, "modulate:a", 0.0, 0.3)

	var shots := 2 + rank * 4  # 폭죽: 등급이 높을수록 많이
	for i in shots:
		var delay := 0.1 + (dur - 1.2) * i / shots + randf() * 0.15
		get_tree().create_timer(delay).timeout.connect(_firework.bind(layer, size, t["color"], rank))
	get_tree().create_timer(dur + 1.6).timeout.connect(layer.queue_free)
	return dur


func _firework(layer: CanvasLayer, size: Vector2, color: Color, rank: int) -> void:
	if not is_instance_valid(layer):
		return
	var c := color if rank < TOP_TIER else Color.from_hsv(randf(), 0.8, 1.0)
	var p := CPUParticles2D.new()
	p.position = Vector2(randf_range(size.x * 0.1, size.x * 0.9), randf_range(size.y * 0.1, size.y * 0.45))
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 90
	p.lifetime = 1.3
	p.spread = 180.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 420.0
	p.damping_min = 160.0
	p.damping_max = 260.0
	p.gravity = Vector2(0, 260)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.add_point(0.25, c)
	g.set_color(g.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	p.color_ramp = g
	layer.add_child(p)
	p.emitting = true
	sfx("firework", -6.0)
