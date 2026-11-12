extends RefCounted
## 룰렛 게임용 도형/그림 만들기 (game.gd 에서 preload 해서 씀).
## 선반 가공(회전체) 도형, 판에 인쇄할 그림(SubViewport), 칸 배치.


## 칸 배치 [{name, rank, start(도), width(도)}] — 경품별 넓이 합 = 실제 확률. 같은 경품은 서로 떨어뜨림.
## 최고 등급 칸이 맨 앞, 바로 뒤가 꽝 (아깝다 연출용).
static func build_slices() -> Array:
	var lose: Array = []
	var groups: Array = []
	for p in Store.PRIZES:
		var nm: String = p["name"]
		var pct: float = p["pct"]
		var is_lose := nm == Store.LOSE
		var n := maxi(1, roundi(pct / (10.0 if is_lose else 5.0)))
		var s := {"name": nm, "rank": Store.rank(nm), "width": pct * 3.6 / n}
		if is_lose:
			for i in n:
				lose.append(s)
		else:
			groups.append({"s": s, "left": n})
	groups.sort_custom(func(a, b): return a["s"]["rank"] > b["s"]["rank"])
	var other: Array = []
	var prev := ""
	while true:
		var best := -1
		for pass_i in 2:  # 1차: 직전과 다른 경품 중 가장 많이 남은 것, 2차: 아무거나
			for i in groups.size():
				if groups[i]["left"] <= 0 or (pass_i == 0 and groups[i]["s"]["name"] == prev):
					continue
				if best < 0 or groups[i]["left"] > groups[best]["left"]:
					best = i
			if best >= 0 or other.is_empty():
				break
		if other.is_empty():
			best = 0
		if best < 0:
			break
		groups[best]["left"] -= 1
		prev = groups[best]["s"]["name"]
		other.append(groups[best]["s"])
	var seq: Array = []
	var li := 0
	for i in other.size():
		seq.append(other[i])
		while li < lose.size() and li < float(i + 1) * lose.size() / other.size():
			seq.append(lose[li])
			li += 1
	while li < lose.size():
		seq.append(lose[li])
		li += 1
	var out: Array = []
	var a := 0.0
	for s in seq:
		out.append({"name": s["name"], "rank": s["rank"], "start": a, "width": s["width"]})
		a += s["width"]
	return out


# ---------- 3D 도형 ----------

static func _quad(v: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array,
		p: Array, n: Array, t: Array) -> void:
	# p: 네 꼭짓점(둘레 순서), n: 꼭짓점별 법선, t: uv.  앞면이 법선 쪽을 보도록 감는 방향을 맞춤
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = p[tri[0]]
		var b: Vector3 = p[tri[1]]
		var c: Vector3 = p[tri[2]]
		var cr := (b - a).cross(c - a)
		if cr.length_squared() < 1e-14:
			continue
		var order: Array = tri
		if cr.dot((n[tri[0]] as Vector3) + n[tri[1]] + n[tri[2]]) > 0.0:
			order = [tri[0], tri[2], tri[1]]
		for k in order:
			v.append(p[k])
			nrm.append(n[k])
			uv.append(t[k])


static func _mesh(v: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## 회전체: pts = [Vector2(반지름, 높이)…] 를 Y축 둘레로 돌림. 진행 방향의 오른쪽이 바깥면.
## (아래 → 바깥쪽을 타고 위로 → 안쪽으로 순서로 적으면 됨). 꺾임이 완만한 곳은 자동으로 부드럽게.
static func lathe(pts: Array, segs := 48) -> ArrayMesh:
	var n := pts.size()
	var sn: Array = []
	for i in n - 1:
		var d: Vector2 = ((pts[i + 1] as Vector2) - (pts[i] as Vector2)).normalized()
		sn.append(Vector2(d.y, -d.x))
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for i in n - 1:
		var na: Vector2 = sn[i]
		var nb: Vector2 = sn[i]
		if i > 0 and (sn[i - 1] as Vector2).dot(sn[i]) > 0.6:
			na = ((sn[i - 1] as Vector2) + sn[i]).normalized()
		if i < n - 2 and (sn[i + 1] as Vector2).dot(sn[i]) > 0.6:
			nb = ((sn[i + 1] as Vector2) + sn[i]).normalized()
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			var c0 := Vector2(cos(a0), sin(a0))
			var c1 := Vector2(cos(a1), sin(a1))
			_quad(v, nrm, uv,
				[Vector3(p0.x * c0.x, p0.y, p0.x * c0.y), Vector3(p1.x * c0.x, p1.y, p1.x * c0.y),
					Vector3(p1.x * c1.x, p1.y, p1.x * c1.y), Vector3(p0.x * c1.x, p0.y, p0.x * c1.y)],
				[Vector3(na.x * c0.x, na.y, na.x * c0.y), Vector3(nb.x * c0.x, nb.y, nb.x * c0.y),
					Vector3(nb.x * c1.x, nb.y, nb.x * c1.y), Vector3(na.x * c1.x, na.y, na.x * c1.y)],
				[Vector2(float(j) / segs, float(i) / (n - 1)), Vector2(float(j) / segs, float(i + 1) / (n - 1)),
					Vector2(float(j + 1) / segs, float(i + 1) / (n - 1)), Vector2(float(j + 1) / segs, float(i) / (n - 1))])
	return _mesh(v, nrm, uv)


## +Z 를 보는 원판 (UV: 그림 한 장이 판 전체)
static func disc(r: float, segs := 96) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for j in segs:
		var a0 := TAU * j / segs
		var a1 := TAU * (j + 1) / segs
		for p in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:
			v.append(Vector3(p.x * r, p.y * r, 0))
			nrm.append(Vector3(0, 0, 1))
			uv.append(Vector2(0.5 + p.x * 0.5, 0.5 - p.y * 0.5))
	return _mesh(v, nrm, uv)


## +Z 를 보는 부채꼴 고리 (각도는 위쪽에서 시계방향, 도)
static func sector(r0: float, r1: float, a0: float, a1: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var steps := maxi(2, int((a1 - a0) / 2.0))
	for k in steps:
		var x0 := deg_to_rad(lerpf(a0, a1, float(k) / steps))
		var x1 := deg_to_rad(lerpf(a0, a1, float(k + 1) / steps))
		var d0 := Vector3(sin(x0), cos(x0), 0)
		var d1 := Vector3(sin(x1), cos(x1), 0)
		var z := Vector3(0, 0, 1)
		_quad(v, nrm, uv, [d0 * r0, d0 * r1, d1 * r1, d1 * r0], [z, z, z, z], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	return _mesh(v, nrm, uv)


## 아래로 갈수록 좁아지는 납작한 조각 (위 가운데가 원점, -Y 로 length 만큼). 포인터 날 한 마디.
static func taper(w0: float, w1: float, length: float, thick: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var h := thick / 2.0
	var a := [Vector3(-w0 / 2, 0, h), Vector3(w0 / 2, 0, h), Vector3(w1 / 2, -length, h), Vector3(-w1 / 2, -length, h)]
	var b := [Vector3(-w0 / 2, 0, -h), Vector3(w0 / 2, 0, -h), Vector3(w1 / 2, -length, -h), Vector3(-w1 / 2, -length, -h)]
	var t := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var f := Vector3(0, 0, 1)
	_quad(v, nrm, uv, a, [f, f, f, f], t)
	_quad(v, nrm, uv, b, [-f, -f, -f, -f], t)
	var slope := (w0 - w1) / 2.0
	var nr := Vector3(length, -slope, 0).normalized()
	var nl := Vector3(-length, -slope, 0).normalized()
	_quad(v, nrm, uv, [a[1], b[1], b[2], a[2]], [nr, nr, nr, nr], t)
	_quad(v, nrm, uv, [a[0], b[0], b[3], a[3]], [nl, nl, nl, nl], t)
	var d := Vector3(0, -1, 0)
	_quad(v, nrm, uv, [a[3], a[2], b[2], b[3]], [d, d, d, d], t)
	_quad(v, nrm, uv, [a[0], a[1], b[1], b[0]], [-d, -d, -d, -d], t)
	return _mesh(v, nrm, uv)


## 주름진 장막 (+Z 를 봄, 가운데가 x=0, 바닥이 y=0)
static func curtain(width: float, height: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var cols := int(width / 0.03)
	var px: Array = []
	var pn: Array = []
	for i in cols + 1:
		var x := -width / 2 + width * i / cols
		var z := 0.13 * sin(x * 7.0) + 0.05 * sin(x * 17.0 + 1.3) + 0.03 * sin(x * 31.0)
		var dz := 0.13 * 7.0 * cos(x * 7.0) + 0.05 * 17.0 * cos(x * 17.0 + 1.3) + 0.03 * 31.0 * cos(x * 31.0)
		px.append(Vector3(x, 0, z))
		pn.append(Vector3(-dz, 0, 1).normalized())
	var up := Vector3(0, height, 0)
	for i in cols:
		_quad(v, nrm, uv, [px[i], px[i] + up, px[i + 1] + up, px[i + 1]], [pn[i], pn[i], pn[i + 1], pn[i + 1]],
			[Vector2(i, 0), Vector2(i, 1), Vector2(i + 1, 1), Vector2(i + 1, 0)])
	return _mesh(v, nrm, uv)


# ---------- 판 그림 (2D) ----------

static func _pt(c: float, phi: float, r: float) -> Vector2:
	var a := deg_to_rad(phi)
	return Vector2(c + r * sin(a), c - r * cos(a))


static func _ring(c: float, r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := maxi(2, int((a1 - a0) / 1.0))
	for k in steps + 1:
		pts.append(_pt(c, lerpf(a0, a1, float(k) / steps), r1))
	if r0 <= 0.0:
		pts.append(Vector2(c, c))
	else:
		for k in range(steps, -1, -1):
			pts.append(_pt(c, lerpf(a0, a1, float(k) / steps), r0))
	return pts


static func _poly(parent: Node, pts: PackedVector2Array, color: Color) -> void:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = color
	p.antialiased = true
	parent.add_child(p)


static func _star(parent: Node, center: Vector2, r: float, rot: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := rot + TAU * i / 10.0
		var rr := r if i % 2 == 0 else r * 0.42
		pts.append(center + Vector2(sin(a), -cos(a)) * rr)
	_poly(parent, pts, color)


static func _text(parent: Node, text: String, size: int, color: Color, outline: Color, en: bool, pos: Vector2, rot_deg: float) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.rotation = deg_to_rad(rot_deg)
	parent.add_child(holder)
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()  # 판에 인쇄된 글자: 외곽선 없이 굵기로만, 아래로 살짝 떨어진 짙은 그림자 하나
	ls.font = Kit.font(900 if en else 800, en, -int(round(size * 0.02)))
	ls.font_size = size
	ls.font_color = color
	ls.shadow_size = 0
	ls.shadow_color = Color(outline, 0.55)
	ls.shadow_offset = Vector2(0, maxf(2.0, size * 0.04))
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sz := Vector2(size * 6.0, size * 1.6)
	l.size = sz
	l.position = -sz / 2
	holder.add_child(l)


static func paint(tier_rank: int, alt: bool) -> Color:
	if tier_rank == 0:
		return Color(0.06, 0.063, 0.08) if alt else Color(0.035, 0.037, 0.048)
	var c: Color = Kit.TIERS[tier_rank]["color"]
	var out := Color.from_hsv(c.h, minf(1.0, c.s * 1.2 + 0.25), c.v * (0.5 if alt else 0.62))
	return out


## 판에 인쇄할 그림을 그리는 SubViewport (한 번만 그림). 위쪽이 0도, 시계방향.
static func face_viewport(slices: Array, size: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := Node2D.new()
	vp.add_child(root)
	var c := size / 2.0
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.size = Vector2(size, size)
	root.add_child(bg)
	var gold := Color(0.86, 0.68, 0.32)
	var seen := {}
	for s in slices:
		var a0: float = s["start"]
		var a1: float = a0 + float(s["width"])
		var rk: int = s["rank"]
		var alt: bool = int(seen.get(s["name"], 0)) % 2 == 1
		seen[s["name"]] = int(seen.get(s["name"], 0)) + 1
		var col := paint(rk, alt)
		_poly(root, _ring(c, 0.0, c * 1.01, a0, a1), col)
		_poly(root, _ring(c, c * 0.885, c * 1.01, a0, a1), col.darkened(0.42))          # 바깥 띠 (핀 자리)
		_poly(root, _ring(c, c * 0.215, c * 0.33, a0, a1), col.lightened(0.1) if rk > 0 else col.lightened(0.04))
	# 금색 줄
	for rr in [0.885, 0.33]:
		_poly(root, _ring(c, c * (rr - 0.004), c * (rr + 0.004), 0.0, 360.0), gold)
	_poly(root, _ring(c, 0.0, c * 0.215, 0.0, 360.0), Color(0.04, 0.04, 0.05))
	# 가운데는 밝게, 가장자리는 살짝 어둡게
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.13), Color(1, 1, 1, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.3)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 512
	gt.height = 512
	var shade := TextureRect.new()
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.size = Vector2(size, size)
	root.add_child(shade)
	# 글자
	for s in slices:
		var w: float = s["width"]
		var mid: float = float(s["start"]) + w / 2.0
		var rk: int = s["rank"]
		var nm: String = s["name"]
		_poly(root, _ring(c, c * 0.935, c * 0.95, mid - 0.45, mid + 0.45), gold.darkened(0.1))   # 띠 장식
		var digits := ""
		for ch in nm:
			if ch >= "0" and ch <= "9":
				digits += ch
		var arc := deg_to_rad(w) * c * 0.76
		if nm == Store.LOSE:
			_text(root, "꽝", int(c * 0.2), Color(0.6, 0.63, 0.74), Color(0.02, 0.02, 0.03), false, _pt(c, mid, c * 0.68), mid)
			_text(root, "다음 기회에", int(c * 0.034), Color(0.42, 0.45, 0.56), Color(0.02, 0.02, 0.03), true, _pt(c, mid, c * 0.47), mid)
		elif digits == "":
			var star_c := Color(1.0, 0.9, 0.5)
			_star(root, _pt(c, mid, c * 0.775), arc * 0.47, deg_to_rad(mid), star_c)
			_star(root, _pt(c, mid, c * 0.64), arc * 0.33, deg_to_rad(mid), star_c)
			_star(root, _pt(c, mid, c * 0.535), arc * 0.25, deg_to_rad(mid), star_c)
			_star(root, _pt(c, mid, c * 0.445), arc * 0.18, deg_to_rad(mid), star_c)
		else:
			var fs := int(minf(c * 0.17, arc * 0.84 / (digits.length() * 0.66)))
			var dark := paint(rk, false).darkened(0.72)
			_text(root, digits, fs, Color(1.0, 0.98, 0.93), dark, true, _pt(c, mid, c * 0.745), mid)
			_text(root, "원 할인" if w > 16.0 else "원", int(c * 0.052), Color(1.0, 0.97, 0.9, 0.92), dark, false, _pt(c, mid, c * 0.6), mid)
	return vp


## 회전 잔상용: tex 를 spread(도) 범위에서 n 번 돌려 평균낸 그림
static func blur_viewport(tex: Texture2D, size: int, n: int, spread: float) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for k in n:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = Vector2(size / 2.0, size / 2.0)
		s.scale = Vector2.ONE * (float(size) / tex.get_width())
		s.rotation = deg_to_rad(lerpf(-spread / 2, spread / 2, float(k) / (n - 1)))
		s.modulate.a = 1.0 / (k + 1)
		vp.add_child(s)
	return vp
