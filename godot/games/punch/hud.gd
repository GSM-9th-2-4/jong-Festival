extends CanvasLayer
## 펀치머신 화면 글자/게이지 (2D). 기준 화면 1280x720.

const LINES := [0, 600, 750, 900, 999]
const W := 1280.0
const H := 720.0
const HOLD_Y := 552.0
const PAPER := Color(0.955, 0.94, 0.905)   # 따뜻한 흰색 (순백 대신)

var _root: Control
var _gauge: Control
var _marker: ColorRect
var _prompt: Control
var _hold: Control
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

	_label("펀치머신", 26, PAPER, Vector2(44, 38), 800)
	_label("한 방에 점수 폭발", 15, Color(PAPER, 0.6), Vector2(45, 74), 500)
	var bar := ColorRect.new()
	bar.color = Kit.GOLD
	bar.position = Vector2(44, 28)
	bar.size = Vector2(34, 3)
	_root.add_child(bar)

	_ladder()
	_gauge_build()

	_hold = Panel.new()  # 글자 뒤 어두운 판 (외곽선 대신)
	_hold.size = Vector2(300, 72)
	_hold.position = Vector2((W - 300) / 2, HOLD_Y)
	_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := _style(Color(0.03, 0.03, 0.04, 0.82), Color(1, 1, 1, 0.0), 36)
	hs.set_border_width_all(0)
	_hold.add_theme_stylebox_override("panel", hs)
	_root.add_child(_hold)
	var hl := _label("멈추나…?!", 40, PAPER, Vector2.ZERO, 800, _hold)
	hl.size = _hold.size
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hold.visible = false

	_flash = ColorRect.new()
	_flash.size = Vector2(W, H)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


## 글자: Pretendard 한 가지, 굵기와 크기로만 위계를 만든다 (외곽선·그림자·번짐 없음). num: 숫자 폭 고정.
func _label(text: String, size: int, color: Color, pos: Vector2, weight := 700, parent: Control = null, num := false) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = Kit.font(weight, num, -int(round(size * 0.02)) if size >= 40 else 0)
	ls.font_size = size
	ls.font_color = color
	l.label_settings = ls
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
	_label("등급", 14, Color(PAPER, 0.55), Vector2(1038, 166), 600)
	var row := 0
	for rk in [4, 3, 2, 1]:
		var t: Dictionary = Kit.tier(rk)
		var c: Color = t["color"]
		var p := Panel.new()
		p.position = Vector2(1036, 192 + row * 74)
		p.size = Vector2(204, 64)
		p.pivot_offset = p.size / 2
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := _style(Color(0.03, 0.03, 0.04, 0.66), Color(1, 1, 1, 0.1))
		st.border_width_left = 3
		p.add_theme_stylebox_override("panel", st)
		_root.add_child(p)
		var n := _label("%s" % t["kor"], 19, Color(PAPER, 0.5), Vector2(16, 8), 700, p)
		var sc := _label("%d+" % LINES[rk], 17, Color(PAPER, 0.38), Vector2(0, 10), 600, p, true)
		sc.size = Vector2(190, 26)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var pr := _label(Store.prize_of_rank(rk), 15, Color(PAPER, 0.45), Vector2(16, 36), 500, p)
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
	var cap := _label("파워", 13, Color(PAPER, 0.75), Vector2(-10, -34), 700, _gauge)
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
	var pl := _label("스페이스 · 클릭 · 터치로 펀치", 20, PAPER, Vector2.ZERO, 700, _prompt)
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
		_hold.position = Vector2((W - 300) / 2 + randf_range(-2, 2), HOLD_Y + randf_range(-2, 2))
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
	st.bg_color = Color(0.05, 0.05, 0.06, 0.92)
	st.border_color = c  # 등급 색은 테두리(왼쪽 굵은 선)에만
	st.border_width_left = 5
	(r["name"] as Label).label_settings.font_color = PAPER
	(r["name"] as Label).label_settings.font = Kit.font(800)
	(r["score"] as Label).label_settings.font_color = Color(PAPER, 0.8)
	(r["prize"] as Label).label_settings.font_color = Color(PAPER, 0.85)
	var p: Panel = r["panel"]
	p.scale = Vector2(1.12, 1.12)
	create_tween().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 등급 선을 뚫는 순간 잠깐 뜨는 판: 어두운 판 + 등급 색 표식 하나 + 굵은 글자
func stamp(lv: int) -> void:
	var t: Dictionary = Kit.tier(lv)
	var plate := PanelContainer.new()
	var ps := _style(Color(0.03, 0.03, 0.04, 0.88), Color(1, 1, 1, 0.0), 14)
	ps.set_border_width_all(0)
	ps.content_margin_left = 30
	ps.content_margin_right = 34
	ps.content_margin_top = 14
	ps.content_margin_bottom = 14
	plate.add_theme_stylebox_override("panel", ps)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	plate.add_child(box)
	var mark := ColorRect.new()
	mark.color = t["color"]
	mark.custom_minimum_size = Vector2(8, 46)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)
	_label("%s 등급 돌파" % t["kor"], 50, PAPER, Vector2.ZERO, 900, box)
	_root.add_child(plate)
	_root.move_child(plate, _flash.get_index())
	plate.reset_size()
	plate.position = Vector2((W - plate.size.x) / 2, 246)
	plate.pivot_offset = plate.size / 2
	plate.scale = Vector2(1.3, 1.3)
	plate.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(plate, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(plate, "modulate:a", 1.0, 0.08)
	tw.tween_interval(0.45)
	tw.tween_property(plate, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(plate, "position:y", 226.0, 0.25)
	tw.tween_callback(plate.queue_free)


## 마지막 결과 카드 (아래 가운데)
func result(score: int, rank: int, prize: String, maxed: bool, gap: int) -> void:
	var c: Color = Kit.tier(rank)["color"] if rank > 0 else Color(0.6, 0.6, 0.6)
	var card := Panel.new()
	card.size = Vector2(620, 124)
	card.position = Vector2((W - 620) / 2, 566)
	card.pivot_offset = card.size / 2
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := _style(Color(0.03, 0.03, 0.04, 0.9), Color(1, 1, 1, 0.12), 14)
	card.add_theme_stylebox_override("panel", st)
	_root.add_child(card)
	_root.move_child(card, _flash.get_index())
	_label("점수", 15, Color(PAPER, 0.55), Vector2(34, 16), 600, card)
	var big := _label("MAX" if maxed else "%03d" % score, 72, PAPER, Vector2(30, 30), 900, card, true)
	big.size = Vector2(190, 84)
	var div := ColorRect.new()
	div.color = Color(1, 1, 1, 0.14)
	div.position = Vector2(226, 22)
	div.size = Vector2(1, 80)
	card.add_child(div)
	var head := ""
	var body := prize
	if rank > 0:
		head = "%s 등급 당첨" % Kit.tier(rank)["kor"]
	elif gap <= 14:
		head = "아깝다…  %d점 모자라요" % gap
		body = "꽝  ·  다음 기회에"
	else:
		head = "힘이 조금 부족했어요"
		body = "꽝  ·  다음 기회에"
	var mark := ColorRect.new()  # 등급 색 표식 (이 카드에서 색은 여기 하나)
	mark.color = c
	mark.position = Vector2(250, 27)
	mark.size = Vector2(10, 10)
	card.add_child(mark)
	_label(head, 18, Color(PAPER, 0.72), Vector2(270, 20), 600, card)
	var b := _label(body, 40 if rank > 0 else 32, PAPER, Vector2(249, 48), 800, card)
	b.size = Vector2(350, 56)
	card.modulate.a = 0.0
	card.scale = Vector2(0.94, 0.94)
	var tw := create_tween().set_parallel()
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
