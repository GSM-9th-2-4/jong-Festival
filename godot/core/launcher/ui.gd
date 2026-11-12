extends RefCounted
## 런처 화면 부품 (글자, 유리 패널, 버튼). launcher.gd 에서만 사용.

const INK := Color(0.085, 0.08, 0.075)
const LINE := Color(1, 1, 1, 0.14)
const GRAY := Color(0.68, 0.675, 0.66)
const WHITE := Color(0.955, 0.94, 0.905)   # 따뜻한 흰색 (순백은 쓰지 않음)
const RED := Color(0.93, 0.3, 0.28)
const MINT := Color(0.45, 0.86, 0.66)

const GLASS_SHADER := "
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float lod = 3.0;
uniform float strength = 0.62;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * 10.0;
	vec3 bg = textureLod(screen, SCREEN_UV, lod).rgb * 0.4;
	bg += textureLod(screen, SCREEN_UV + vec2(px.x, px.y), lod).rgb * 0.15;
	bg += textureLod(screen, SCREEN_UV + vec2(-px.x, px.y), lod).rgb * 0.15;
	bg += textureLod(screen, SCREEN_UV + vec2(px.x, -px.y), lod).rgb * 0.15;
	bg += textureLod(screen, SCREEN_UV + vec2(-px.x, -px.y), lod).rgb * 0.15;
	COLOR.rgb = mix(bg, COLOR.rgb, strength);
}
"

static var _shader: Shader


## 글꼴은 Kit.font (Pretendard) 하나. num: 숫자 폭 고정(표/코드/점수), light: 본문 굵기(500), weight: 직접 지정.
static func font(num: bool, spacing := 0, light := false, weight := 0) -> Font:
	return Kit.font(weight if weight > 0 else (500 if light else 700), num, spacing)


## 그림자·외곽선 없음 — 글자 뒤 어두운 막/판으로 읽히게 한다. 큰 글자는 자간을 조금 좁힘.
static func settings(size: int, color := WHITE, num := false, spacing := 0, light := false, weight := 0) -> LabelSettings:
	var ls := LabelSettings.new()
	if spacing == 0 and size >= 40:
		spacing = -int(round(size * 0.02))
	ls.font = font(num, spacing, light, weight)
	ls.font_size = size
	ls.font_color = color
	return ls


## 글자. align: -1 왼쪽(x 가 왼쪽 끝) / 0 가운데(x 가 중심) / 1 오른쪽(x 가 오른쪽 끝). y 는 글자 상자의 위쪽.
static func text(parent: Node, s: String, size: int, pos: Vector2, color := WHITE, num := false, spacing := 0, align := -1, light := false, weight := 0) -> Label:
	var l := Label.new()
	l.text = s
	l.label_settings = settings(size, color, num, spacing, light, weight)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 1400.0
	l.size = Vector2(w, 0)
	if align == 0:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = pos - Vector2(w / 2, 0)
	elif align > 0:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.position = pos - Vector2(w, 0)
	else:
		l.position = pos
	parent.add_child(l)
	return l


static func flat(color: Color, radius := 0, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 12
	sb.anti_aliasing_size = 1.2
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	return sb


static func outline(color: Color, radius := 0, bw := 1) -> StyleBoxFlat:
	var sb := flat(Color(0, 0, 0, 0), radius, color, bw)
	sb.draw_center = false
	return sb


static func panel(parent: Node, rect: Rect2, sb: StyleBox) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


## 뒤가 비쳐 흐려지는 유리 패널. 테두리 패널은 get_meta("border").
static func glass(parent: Node, rect: Rect2, radius := 16, border := LINE, strength := 0.62, tint := Color(0.035, 0.045, 0.085)) -> Panel:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = GLASS_SHADER
	var p := panel(parent, rect, flat(Color(tint, 1.0), radius))
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("strength", strength)
	p.material = m
	var b := panel(p, Rect2(Vector2.ZERO, rect.size), outline(border, radius, 1))
	p.set_meta("border", b)
	return p


static func rect(parent: Node, r: Rect2, color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## 세로/가로 그라데이션 그림. stops: [[위치, 색], ...]
static func gradient(parent: Node, r: Rect2, stops: Array, from := Vector2(0, 0), to := Vector2(0, 1)) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = from
	gt.fill_to = to
	gt.width = 128
	gt.height = 128
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.position = r.position
	t.size = r.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


## 누를 수 있는 버튼 (마우스/터치). 키보드 포커스는 받지 않음.
static func button(parent: Node, r: Rect2, label: String, size: int, en := true, on_press := Callable(), accent := Color(1, 1, 1, 0.16)) -> Button:
	var b := Button.new()
	b.text = label
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(en))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_color_override("font_hover_color", WHITE)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_stylebox_override("normal", flat(Color(1, 1, 1, 0.05), 8, accent, 1))
	b.add_theme_stylebox_override("hover", flat(Color(1, 1, 1, 0.13), 8, Color(1, 1, 1, 0.4), 1))
	b.add_theme_stylebox_override("pressed", flat(Kit.GOLD, 8))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	parent.add_child(b)
	return b
