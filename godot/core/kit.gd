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
var _font_base: Font       # Pretendard (가변 글꼴). 파일이 없으면 시스템 글꼴
var _font_bundled := false
var _fonts := {}
var _shaders := {}


func assets_dir() -> String:
	return ProjectSettings.globalize_path("res://assets")


func tier(rank: int) -> Dictionary:
	return TIERS[clampi(rank, 0, TOP_TIER)]


# ---------- 글꼴 ----------
## 글꼴은 Pretendard 하나 (assets/fonts/PretendardVariable.ttf, SIL OFL 1.1). 위계는 굵기와 크기로만 만든다.
## 외곽선·네온 번짐·그라데이션 글자·자간 벌린 영문 대문자는 쓰지 않는다. 배경이 복잡하면 글자 뒤에 판/어두운 막을 깐다.

const INK := Color(0.085, 0.08, 0.075)       ## 종이 위 글자
const PAPER := Color(0.955, 0.94, 0.905)     ## 종이 / 어두운 바탕 위 글자 (따뜻한 흰색)
const FONT_SYSTEM := ["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", "NanumGothic"]


func _load_font() -> void:
	var path := assets_dir() + "/fonts/PretendardVariable.ttf"
	var sysf := SystemFont.new()
	sysf.font_names = PackedStringArray(FONT_SYSTEM)
	sysf.font_weight = 700
	_font_base = sysf
	if FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK:
			ff.fallbacks = [sysf]
			_font_base = ff
			_font_bundled = true
			return
	push_warning("글꼴 없음: " + path + " — 시스템 글꼴로 대신함")


## 굵기(100~900)를 정해서 쓰는 글꼴. tabular: 숫자 폭을 똑같이(점수/코드/표), spacing: 자간(px).
func font(weight := 700, tabular := false, spacing := 0) -> Font:
	var key := "%d/%s/%d" % [weight, tabular, spacing]
	if _fonts.has(key):
		return _fonts[key]
	if _font_base == null:
		_load_font()
	var ts := TextServerManager.get_primary_interface()
	var fv := FontVariation.new()
	if _font_bundled:
		fv.base_font = _font_base
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	else:
		var sysf := SystemFont.new()
		sysf.font_names = PackedStringArray(FONT_SYSTEM)
		sysf.font_weight = weight
		fv.base_font = sysf
	if tabular:
		fv.opentype_features = {ts.name_to_tag("tnum"): 1}
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


func font_kr() -> Font:  ## 본문/제목 (Bold)
	return font(700)


func font_en() -> Font:  ## 숫자/영문 (ExtraBold, 숫자 폭 고정)
	return font(800, true)


## 화면 글자 설정. en: 숫자/영문용(더 굵고 숫자 폭 고정). outline 은 예전 이름만 남은 것 — 외곽선 대신
## 아래로 살짝 떨어진 짙은 그림자를 준다 (3D 장면 위에서 읽히게). 큰 글자는 자간을 조금 좁힌다.
func label_settings(size: int, color := Color.WHITE, en := false, outline := 0, shadow := true) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font(800 if en else 700, en, -int(round(size * 0.02)) if size >= 40 else 0)
	ls.font_size = size
	ls.font_color = color
	if shadow or outline > 0:
		ls.shadow_size = 0
		ls.shadow_color = Color(0, 0, 0.01, 0.6 if outline > 0 else 0.4)
		ls.shadow_offset = Vector2(0, maxf(1.0, round(size * (0.045 if outline > 0 else 0.03))))
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


# ---------- 종이 / 박(foil) ----------

const PAPER_SHADER := "
shader_type canvas_item;
uniform vec2 size = vec2(100.0);
uniform float radius = 12.0;
uniform float notch_x = -1.0;
uniform float notch_r = 13.0;
uniform float grain = 0.03;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void fragment() {
	vec2 p = UV * size;
	vec2 q = abs(p - size * 0.5) - size * 0.5 + radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float a = 1.0 - smoothstep(-0.75, 0.75, d);
	if (notch_x >= 0.0) {
		float n = min(length(p - vec2(notch_x, 0.0)), length(p - vec2(notch_x, size.y))) - notch_r;
		a *= smoothstep(-0.75, 0.75, n);
		float hole = length(vec2(p.x - notch_x, mod(p.y, 13.0) - 6.5)) - 2.3;
		float mid = step(notch_r + 7.0, p.y) * step(p.y, size.y - notch_r - 7.0);
		a *= mix(1.0, smoothstep(-0.7, 0.7, hole), mid);
	}
	float g = h21(floor(p)) - 0.5;
	float fiber = h21(floor(p * vec2(0.16, 1.4))) - 0.5;
	vec3 c = COLOR.rgb + g * grain + fiber * grain * 0.6;
	c *= 1.0 - 0.07 * smoothstep(-16.0, 0.0, d);
	COLOR = vec4(c, COLOR.a * a);
}
"

const FOIL_SHADER := "
shader_type canvas_item;
uniform vec2 size = vec2(100.0);
uniform float sweep = 1.0;
uniform float period = 3.4;
uniform vec3 notch = vec3(0.0);
float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = UV * size;
	float along = size.x >= size.y ? p.y : p.x;
	float streak = h11(floor(along * 1.6));
	vec3 base = COLOR.rgb * (0.88 + 0.12 * streak);
	float u = (p.x + p.y * 0.55) / (size.x + size.y * 0.55);
	base *= 0.9 + 0.16 * sin(u * 9.0 + 1.0);
	float ph = fract(TIME / period) * 1.7 - 0.35;
	float band = exp(-pow((u - ph) / 0.06, 2.0));
	base += sweep * band * vec3(0.5, 0.5, 0.46);
	float a = notch.z > 0.0 ? smoothstep(-0.75, 0.75, length(p - notch.xy) - notch.z) : 1.0;
	COLOR = vec4(base, COLOR.a * a);
}
"


const SHADOW_SHADER := "
shader_type canvas_item;
uniform vec2 size = vec2(100.0);
uniform float radius = 12.0;
uniform float blur = 30.0;
void fragment() {
	vec2 p = UV * size;
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - blur) + radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float a = 1.0 - smoothstep(-blur, blur, d);
	COLOR.a *= a * a;
}
"


## 부드러운 그림자 (종이가 바닥에 닿은 느낌). rect = 그림자를 드리우는 물체의 자리, offset 만큼 아래로 내려 깔림.
func soft_shadow(parent: Node, rect: Rect2, radius := 12.0, blur := 34.0, alpha := 0.5, offset := Vector2(0, 18)) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0.01, alpha)
	r.position = rect.position + offset - Vector2(blur, blur)
	r.size = rect.size + Vector2(blur, blur) * 2.0
	var m := ShaderMaterial.new()
	m.shader = _shader(SHADOW_SHADER)
	m.set_shader_parameter("size", r.size)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("blur", blur)
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var sh := Shader.new()
		sh.code = code
		_shaders[code] = sh
	return _shaders[code]


## 종이 재질 (ColorRect 에 붙임. 색은 ColorRect.color). 둥근 모서리 + 종이결.
## notch_x >= 0 이면 그 x 위치에 절취선(위아래 반달 홈 + 점선 구멍)을 뚫음.
func paper_material(size: Vector2, radius := 12.0, notch_x := -1.0, notch_r := 13.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(PAPER_SHADER)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("notch_x", notch_x)
	m.set_shader_parameter("notch_r", notch_r)
	return m


## 금속 박 재질 (ColorRect 에 붙임. 색은 ColorRect.color). sweep: 빛이 주기적으로 훑고 지나감.
## notch: (x, y, 반지름) 자리를 동그랗게 파냄 (절취선 홈과 맞출 때).
func foil_material(size: Vector2, sweep := true, period := 3.4, notch := Vector3.ZERO) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(FOIL_SHADER)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("sweep", 1.0 if sweep else 0.0)
	m.set_shader_parameter("period", period)
	m.set_shader_parameter("notch", notch)
	return m


## 모서리가 둥근 틀: 안에 넣은 것들이 그 모양대로 잘림 (종이 카드/쿠폰의 바깥 모양).
func round_clip(parent: Node, size: Vector2, radius: float) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 12
	sb.anti_aliasing_size = 1.0
	p.add_theme_stylebox_override("panel", sb)
	p.size = size
	p.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


# ---------- 당첨 축하 연출 (모든 게임 공용) ----------

## 종이 꽃가루. 조각마다 회전·뒤집힘·크기(거리감)·공기저항이 다름. Kit.confetti() 로 만듦.
class Confetti extends Node2D:
	var life := 4.0   # 이 시각(초)부터 0.9초 동안 사라짐
	var floor_y := 760.0
	var pieces: Array = []
	var _t := 0.0

	func _process(dt: float) -> void:
		dt = minf(dt, 0.05)
		_t += dt
		for d in pieces:
			if _t < d["t0"]:
				continue
			var v: Vector2 = d["v"]
			v.y += d["g"] * dt
			v.x += sin(_t * d["sf"] + d["ph"]) * d["sa"] * dt
			v *= maxf(0.0, 1.0 - d["drag"] * dt)
			d["v"] = v
			d["pos"] += v * dt
			d["rot"] += d["spin"] * dt
			d["flip"] += d["fs"] * dt
		modulate.a = clampf(1.0 - (_t - life) / 0.9, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		for d in pieces:
			var pos: Vector2 = d["pos"]
			if _t < d["t0"] or pos.y > floor_y:
				continue
			var f := cos(d["flip"])
			var c: Color = d["col"]
			var kind: int = d["kind"]
			if kind == 1:  # 금박: 정면을 볼 때만 번쩍
				c = c.darkened(0.4).lerp(Color(1.0, 0.96, 0.8), pow(absf(f), 5.0))
			else:  # 종이: 뒷면은 조금 어둡게
				c = c.darkened(0.2 if f < 0.0 else 0.0).darkened(0.16 * (1.0 - absf(f)))
			if kind == 2:  # 긴 리본
				draw_set_transform(pos, d["rot"], Vector2.ONE)
				var pts := PackedVector2Array()
				var seg: float = d["w"] / 9.0
				for i in 10:
					pts.append(Vector2((i - 4.5) * seg, sin(i * 0.85 + _t * d["fs"] + d["ph"]) * d["h"]))
				draw_polyline(pts, c, maxf(2.0, d["h"] * 0.42), true)
			else:
				draw_set_transform(pos, d["rot"], Vector2(1.0, maxf(absf(f), 0.1)))
				draw_rect(Rect2(-d["w"] * 0.5, -d["h"] * 0.5, d["w"], d["h"]), c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _confetti_piece(pos: Vector2, vel: Vector2, t0: float, col: Color, k: float, depth: float, kind := 0) -> Dictionary:
	var w := randf_range(9.0, 16.0)
	var h := w * randf_range(0.5, 0.85)
	if kind == 2:
		w = randf_range(70.0, 120.0)
		h = randf_range(5.0, 8.0)
	elif randf() < 0.3:  # 길쭉한 조각
		w = randf_range(16.0, 24.0)
		h = randf_range(4.0, 6.0)
	if kind == 0:  # 멀리 있는 조각은 살짝 가라앉은 색
		col = col.lerp(Color(0.05, 0.05, 0.07), clampf((1.05 - depth) * 0.5, 0.0, 0.3))
	return {"pos": pos, "v": vel * depth, "t0": t0, "col": col, "kind": kind, "depth": depth,
		"w": w * k * depth, "h": h * k * depth, "rot": randf() * TAU, "spin": randf_range(-6.0, 6.0) * (0.25 if kind == 2 else 1.0),
		"flip": randf() * TAU, "fs": randf_range(5.0, 13.0), "g": randf_range(430.0, 560.0) * k * depth * (0.7 if kind == 2 else 1.0),
		"drag": randf_range(1.9, 2.9), "sa": randf_range(120.0, 360.0) * k, "sf": randf_range(2.4, 5.0), "ph": randf() * TAU}


## 종이 꽃가루 노드를 만들어 돌려줌 (add_child 는 직접. 화면 좌표 기준, size = 화면 크기).
## mode 0: 양쪽 아래에서 쏘아 올림(등급이 높을수록 많이, 여러 번, 리본 추가)  1: 같은 발사의 '가까운' 큰 조각 몇 개만  2: 위에서 천천히 내리기만
func confetti(size: Vector2, color: Color, rank: int, dur: float, mode := 0) -> Node2D:
	var cf := Confetti.new()
	var k := size.y / 720.0
	cf.life = dur + 0.5
	cf.floor_y = size.y + 60.0 * k
	var paper := Color(0.96, 0.94, 0.9)
	var pal := [color, color, color.lightened(0.38), color.darkened(0.32), paper, paper, Color(0.8, 0.78, 0.74), Color(0.15, 0.15, 0.18)]
	var gold := Color(0.93, 0.76, 0.36)
	var pick := func() -> Array:  # [색, 종류]
		return [gold, 1] if randf() < 0.09 else [pal[randi() % pal.size()], 0]
	if mode != 2:
		var bursts := [0.0]
		if rank >= 3:
			bursts.append(1.15)
		if rank >= TOP_TIER:
			bursts.append(dur * 0.56)
		for bi in bursts.size():
			var n := (40 + 30 * rank) if mode == 0 else (4 + 3 * rank)
			if bi > 0:
				n = int(n * 0.6)
			for side in [-1.0, 1.0]:
				var origin := Vector2(size.x * 0.5 + side * (size.x * 0.5 + 24.0 * k), size.y * 0.97)
				for i in n:
					var depth := (0.6 + 0.85 * pow(randf(), 1.7)) if mode == 0 else randf_range(1.7, 2.4)
					var ang := deg_to_rad(randf_range(28.0, 84.0))
					var sp := randf_range(800.0, 3100.0) * k
					var pc: Array = pick.call()
					cf.pieces.append(_confetti_piece(origin + Vector2(randf_range(-10, 10), randf_range(-10, 10)) * k,
						Vector2(-side * cos(ang), -sin(ang)) * sp, bursts[bi] + randf() * 0.12, pc[0], k, depth, pc[1]))
				if mode == 0 and rank >= 3 and bi == 0:
					for i in 5 * (rank - 2):
						var ang := deg_to_rad(randf_range(48.0, 78.0))
						cf.pieces.append(_confetti_piece(origin, Vector2(-side * cos(ang), -sin(ang)) * randf_range(1300.0, 2300.0) * k,
							randf() * 0.1, [color, paper, gold][randi() % 3], k, randf_range(0.8, 1.2), 2))
	if mode != 1:
		var n := 22 * rank if mode == 0 else 16 + 12 * rank
		for i in n:  # 위에서 팔랑팔랑
			var pc: Array = pick.call()
			cf.pieces.append(_confetti_piece(Vector2(randf() * size.x, -randf_range(20.0, 80.0) * k), Vector2(randf_range(-40, 40), randf_range(0, 80)) * k,
				randf_range(0.25, maxf(0.6, dur - 1.6)), pc[0], k, 0.6 + 0.85 * pow(randf(), 1.7), pc[1]))
	cf.pieces.sort_custom(func(a, b): return a["depth"] < b["depth"])
	return cf


func _ink(parent: Node, text: String, size: float, weight: int, color: Color, pos: Vector2, tabular := false, spacing := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font(weight, tabular, int(round(spacing)))
	ls.font_size = int(round(size))
	ls.font_color = color
	l.label_settings = ls
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 당첨 순간: 장면이 살짝 어두워지고, 종이 카드(등급 + 경품)가 떨어져 자리 잡고, 종이 꽃가루가 터짐.
## 꽝(0)이면 아무것도 안 함. 연출 길이(초)를 돌려줌 — 게임은 그만큼 기다린 뒤 끝내면 됨.
## banner = false: 카드/어두운 막 없이 꽃가루만 (게임이 자기 결과 글자를 따로 보여줄 때).
func celebrate(rank: int, prize: String, banner := true) -> float:
	rank = clampi(rank, 0, TOP_TIER)
	if rank == 0:
		return 0.0
	var t: Dictionary = TIERS[rank]
	var col: Color = t["color"]
	var dur := 2.4 + 0.8 * rank
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var size := get_viewport().get_visible_rect().size
	var k := size.y / 720.0
	sfx("boom")
	sfx("tier%d" % rank)
	sfx("firework", -6.0)
	if rank >= 3:
		sfx("cheer", -3.0)
		get_tree().create_timer(1.15).timeout.connect(sfx.bind("firework", -6.0))
	if rank >= TOP_TIER:
		get_tree().create_timer(dur * 0.56).timeout.connect(sfx.bind("firework", -6.0))

	if banner:
		var scrim := ColorRect.new()
		scrim.color = Color(0.012, 0.012, 0.02, 0.0)
		scrim.size = size
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(scrim)
		var st := scrim.create_tween()
		st.tween_property(scrim, "color:a", 0.68, 0.3)
		st.tween_interval(maxf(0.5, dur - 0.75))
		st.tween_property(scrim, "color:a", 0.0, 0.45)
	layer.add_child(confetti(size, col, rank, dur, 0))
	if banner:
		_celebrate_card(layer, size, k, rank, prize, dur)
	layer.add_child(confetti(size, col, rank, dur, 1))
	get_tree().create_timer(dur + 1.6).timeout.connect(layer.queue_free)
	return dur


func _celebrate_card(layer: CanvasLayer, size: Vector2, k: float, rank: int, prize: String, dur: float) -> void:
	var t: Dictionary = TIERS[rank]
	var col: Color = t["color"]
	var cs := Vector2(700, 316) * k
	var card := Control.new()
	card.size = cs
	card.pivot_offset = cs * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rest := Vector2((size.x - cs.x) * 0.5, size.y * 0.47 - cs.y * 0.5)
	card.position = rest
	layer.add_child(card)

	soft_shadow(card, Rect2(Vector2(8, 4) * k, cs - Vector2(16, 8) * k), 14.0 * k, 36.0 * k, 0.6, Vector2(0, 20 * k))

	var paper := ColorRect.new()
	paper.color = PAPER
	paper.size = cs
	paper.material = paper_material(cs, 14.0 * k)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_clip(card, cs, 14.0 * k).add_child(paper)

	var foil_w := 22.0 * k
	var foil := ColorRect.new()  # 왼쪽 가장자리의 등급 색 박
	foil.color = col
	foil.size = Vector2(foil_w, cs.y)
	foil.material = foil_material(foil.size, rank >= 3, 2.2)
	foil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(foil)

	var x0 := foil_w + 42.0 * k
	var inner := cs.x - x0 - 44.0 * k
	var chip := PanelContainer.new()  # 등급 칩 — 이 화면에서 등급 색을 쓰는 곳은 박과 이 칩뿐
	var csb := StyleBoxFlat.new()
	csb.bg_color = col
	csb.set_corner_radius_all(int(6 * k))
	csb.content_margin_left = 12 * k
	csb.content_margin_right = 12 * k
	csb.content_margin_top = 5 * k
	csb.content_margin_bottom = 5 * k
	chip.add_theme_stylebox_override("panel", csb)
	chip.position = Vector2(x0, 38 * k)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(chip)
	_ink(chip, str(t["name"]), 15 * k, 800, INK, Vector2.ZERO, false, 1.0 * k)
	var note := _ink(paper, "잠시 후 쿠폰이 나와요", 17 * k, 500, Color(INK, 0.5), Vector2(x0, 40 * k))
	note.size = Vector2(inner, 24 * k)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_ink(paper, "%s 등급 당첨" % t["kor"], 32 * k, 700, Color(INK, 0.72), Vector2(x0, 92 * k))
	var ps := 100.0 * k
	while ps > 44.0 * k and font(900, false, -int(round(ps * 0.025))).get_string_size(prize, HORIZONTAL_ALIGNMENT_LEFT, -1, int(ps)).x > inner:
		ps -= 2.0
	var pl := _ink(paper, prize, ps, 900, INK, Vector2(x0 - 3 * k, 0), false, -round(ps * 0.025))
	pl.size = Vector2(inner + 6 * k, 150 * k)
	pl.position.y = 134 * k
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if rank >= 3:  # 높은 등급: 카드 위로 빛이 한 번씩 훑고 지나감
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 64
		gt.height = 4
		var sheen := TextureRect.new()
		sheen.texture = gt
		sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sheen.stretch_mode = TextureRect.STRETCH_SCALE
		sheen.size = Vector2(210 * k, cs.y * 1.8)
		sheen.rotation = deg_to_rad(22.0)
		sheen.position = Vector2(-320 * k, -cs.y * 0.3)
		sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(sheen)
		var sw := sheen.create_tween()
		sw.tween_interval(0.55)
		for i in rank - 1:
			sw.tween_property(sheen, "position:x", cs.x + 160 * k, 0.75).from(-320 * k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			sw.tween_interval(0.7)

	# 등장: 위에서 묵직하게 떨어져 살짝 넘쳤다가 자리 잡음. 끝까지 아주 천천히 기울기가 풀림.
	card.position = rest + Vector2(0, -90 * k)
	card.scale = Vector2(0.8, 0.8)
	card.rotation = deg_to_rad(-8.0)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel()
	tw.tween_property(card, "modulate:a", 1.0, 0.14)
	tw.tween_property(card, "position", rest, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation", deg_to_rad(-2.2), 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(card, "rotation", deg_to_rad(-1.2), maxf(0.3, dur - 1.25)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(card, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(card, "position:y", rest.y + 26 * k, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
