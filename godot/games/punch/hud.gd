extends CanvasLayer
## 펀치머신 화면 글자/게이지 (2D). 기준 화면 1280x720.

const LINES := [0, 600, 750, 900, 999]
const W := 1280.0
const H := 720.0

var _root: Control
var _gauge: Control
var _marker: ColorRect
var _prompt: Control
var _hold: Label
var _flash: ColorRect
var _rows := {}          # 등급 → {panel, style, name, prize}
var _gauge_h := 300.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.size = Vector2(W, H)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 가장자리를 살짝 어둡게 (사진 느낌)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0.02, 0.62))
	g.add_point(0.55, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 0.5)
	var vig := TextureRect.new()
	vig.texture = gt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.size = Vector2(W, H)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vig)

	_label("POWER PUNCH", 30, Color(1, 1, 1, 0.92), Vector2(44, 34), true)
	_label("한 방에 점수 폭발", 16, Color(1, 1, 1, 0.55), Vector2(46, 70))
	var bar := ColorRect.new()
	bar.color = Kit.GOLD
	bar.position = Vector2(44, 28)
	bar.size = Vector2(34, 3)
	_root.add_child(bar)

	_ladder()
	_gauge_build()

	_hold = _label("멈추나…?!", 46, Color.WHITE, Vector2(0, 560), false, 10)
	_hold.size = Vector2(W, 60)
	_hold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold.visible = false

	_flash = ColorRect.new()
	_flash.size = Vector2(W, H)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


func _label(text: String, size: int, color: Color, pos: Vector2, en := false, outline := 0, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = Kit.label_settings(size, color, en, outline)
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else _root).add_child(l)
	return l


func _style(bg: Color, border: Color, radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _ladder() -> void:
	_label("TIER", 15, Color(1, 1, 1, 0.5), Vector2(1036, 168), true)
	var row := 0
	for rk in [4, 3, 2, 1]:
		var t: Dictionary = Kit.tier(rk)
		var c: Color = t["color"]
		var p := Panel.new()
		p.position = Vector2(1036, 192 + row * 74)
		p.size = Vector2(204, 64)
		p.pivot_offset = p.size / 2
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := _style(Color(0.02, 0.025, 0.045, 0.62), Color(c.r, c.g, c.b, 0.28))
		st.border_width_left = 3
		p.add_theme_stylebox_override("panel", st)
		_root.add_child(p)
		var n := _label("%s" % t["name"], 21, c.darkened(0.25), Vector2(16, 7), true, 0, p)
		var sc := _label("%d+" % LINES[rk], 21, Color(1, 1, 1, 0.38), Vector2(0, 7), true, 0, p)
		sc.size = Vector2(190, 26)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var pr := _label(Store.prize_of_rank(rk), 16, Color(1, 1, 1, 0.5), Vector2(16, 35), false, 0, p)
		_rows[rk] = {"panel": p, "style": st, "name": n, "score": sc, "prize": pr, "color": c}
		row += 1


func _gauge_build() -> void:
	_gauge = Control.new()
	_gauge.position = Vector2(70, 196)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_gauge)
	var back := Panel.new()
	back.position = Vector2(-10, -40)
	back.size = Vector2(44, _gauge_h + 56)
	back.add_theme_stylebox_override("panel", _style(Color(0.02, 0.025, 0.045, 0.6), Color(1, 1, 1, 0.14), 10))
	_gauge.add_child(back)
	var cap := _label("POWER", 14, Color(1, 1, 1, 0.75), Vector2(-10, -34), true, 0, _gauge)
	cap.size = Vector2(44, 20)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.25, 0.3))
	g.set_color(1, Color(0.25, 0.75, 1.0))
	g.add_point(0.5, Color(1.0, 0.8, 0.3))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var fill := TextureRect.new()
	fill.texture = gt
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.position = Vector2(6, 0)
	fill.size = Vector2(12, _gauge_h)
	_gauge.add_child(fill)
	for i in 11:
		var tick := ColorRect.new()
		tick.color = Color(1, 1, 1, 0.35 if i % 5 else 0.8)
		tick.position = Vector2(22, _gauge_h * i / 10.0 - 0.5)
		tick.size = Vector2(4 if i % 5 else 8, 1)
		_gauge.add_child(tick)
	_marker = ColorRect.new()
	_marker.color = Color.WHITE
	_marker.size = Vector2(28, 3)
	_gauge.add_child(_marker)

	_prompt = Panel.new()
	_prompt.size = Vector2(380, 50)
	_prompt.position = Vector2((W - 380) / 2, 636)
	_prompt.pivot_offset = _prompt.size / 2
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_stylebox_override("panel", _style(Color(0.02, 0.025, 0.045, 0.72), Color(1, 1, 1, 0.3), 25))
	_root.add_child(_prompt)
	var pl := _label("SPACE · 클릭 · 터치   —   펀치!", 21, Color.WHITE, Vector2.ZERO, false, 0, _prompt)
	pl.size = _prompt.size
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func set_power(p: float) -> void:
	_marker.position = Vector2(-2, _gauge_h * (1.0 - p) - 1.5)
	_prompt.modulate.a = 0.75 + 0.25 * p


func hide_ready(_power: float) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(_gauge, "modulate:a", 0.0, 0.5).set_delay(0.5)
	tw.tween_property(_prompt, "modulate:a", 0.0, 0.15)
	_marker.color = Kit.GOLD
	_marker.size = Vector2(34, 5)


func set_hold(on: bool, t: float) -> void:
	_hold.visible = on
	if on:
		_hold.position = Vector2(randf_range(-2, 2), 560 + randf_range(-2, 2))
		_hold.modulate.a = 0.75 + 0.25 * sin(t * 14.0)


func flash(alpha: float, dur: float, color := Color.WHITE) -> void:
	_flash.color = Color(color.r, color.g, color.b, alpha)
	create_tween().tween_property(_flash, "color:a", 0.0, dur)


func light_tier(lv: int) -> void:
	if not _rows.has(lv):
		return
	var r: Dictionary = _rows[lv]
	var c: Color = r["color"]
	var st: StyleBoxFlat = r["style"]
	st.bg_color = Color(c.r * 0.28, c.g * 0.28, c.b * 0.28, 0.85)
	st.border_color = c
	(r["name"] as Label).label_settings.font_color = c.lerp(Color.WHITE, 0.35)
	(r["score"] as Label).label_settings.font_color = Color.WHITE
	(r["prize"] as Label).label_settings.font_color = Color.WHITE
	var p: Panel = r["panel"]
	p.scale = Vector2(1.18, 1.18)
	create_tween().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 등급 선을 뚫는 순간 잠깐 뜨는 글자
func stamp(text: String, color: Color) -> void:
	var l := _label(text, 96, color.lerp(Color.WHITE, 0.3), Vector2(0, 250), true, 12)
	l.size = Vector2(W, 110)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.pivot_offset = l.size / 2
	l.scale = Vector2(2.2, 2.2)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.08)
	tw.tween_interval(0.45)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "position:y", 225.0, 0.25)
	tw.tween_callback(l.queue_free)


## 마지막 결과 카드 (아래 가운데)
func result(score: int, rank: int, prize: String, maxed: bool, gap: int) -> void:
	var c: Color = Kit.tier(rank)["color"] if rank > 0 else Color(0.62, 0.68, 0.85)
	var card := Panel.new()
	card.size = Vector2(620, 124)
	card.position = Vector2((W - 620) / 2, 566)
	card.pivot_offset = card.size / 2
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := _style(Color(0.02, 0.025, 0.045, 0.82), Color(c.r, c.g, c.b, 0.85), 14)
	st.border_width_top = 3
	card.add_theme_stylebox_override("panel", st)
	_root.add_child(card)
	_root.move_child(card, _flash.get_index())
	_label("SCORE", 15, Color(1, 1, 1, 0.55), Vector2(34, 16), true, 0, card)
	var big := _label("MAX" if maxed else "%03d" % score, 84, c.lerp(Color.WHITE, 0.3), Vector2(30, 28), true, 0, card)
	big.size = Vector2(190, 90)
	var div := ColorRect.new()
	div.color = Color(1, 1, 1, 0.16)
	div.position = Vector2(226, 22)
	div.size = Vector2(1, 80)
	card.add_child(div)
	var head := ""
	var body := prize
	if rank > 0:
		head = "%s  ·  %s 등급" % [Kit.tier(rank)["name"], Kit.tier(rank)["kor"]]
	elif gap <= 14:
		head = "아깝다…!  %d점 모자라요" % gap
		body = "꽝  ·  다음 기회에"
	else:
		head = "힘이 조금 부족했어요"
		body = "꽝  ·  다음 기회에"
	_label(head, 19, c.lerp(Color.WHITE, 0.25), Vector2(250, 22), false, 0, card)
	var b := _label(body, 40 if rank > 0 else 34, Color.WHITE, Vector2(250, 50), false, 0, card)
	b.size = Vector2(350, 56)
	card.modulate.a = 0.0
	card.scale = Vector2(0.9, 0.9)
	var tw := create_tween().set_parallel()
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
