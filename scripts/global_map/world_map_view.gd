extends Control
## Интерактивная глобальная карта Украины.
##
## Области — только географическая основа (границы, подписи). Игровые объекты — места сценариев
## (data/global_map/places.json): маркеры, фильтр по годам, выбор касанием.
## Контур областей получен из схемы автора проекта (tools/extract_regions.py); рельеф процедурный.
## Контроль территорий на карте показывается только если он задан сценарием/состоянием на дату
## (на этом этапе все области нейтральны, итоги вымышленных боёв области не перекрашивают).

signal place_selected(place_id: String)
signal camera_changed

const SEA_COLOR := Color("#1b4f7a")
const LAND_COLOR := Color("#5d6158")
const BASE_COLOR := Color("#4a6b4c")
const MIN_REL_ZOOM := 0.85
const MAX_REL_ZOOM := 9.0
const TAP_SLOP := 14.0
const ANIM_TIME := 0.35
const PICK_RADIUS := 34.0

const GROUP_COLORS := {
	"2014": Color("#f59e0b"), "2022": Color("#38bdf8"), "2023": Color("#c084fc"),
	"2024": Color("#34d399"), "test": Color("#cbd5e1"), "none": Color("#fda4af"),
}

var selected_place: String = ""
var filter_key: String = ""
## Масштаб: пикселей экрана на единицу карты.
var zoom: float = 1.0
## Точка карты в центре экрана.
var center: Vector2 = Vector2.ZERO

var _map_size: Vector2 = Vector2(1000, 680)
var _world: Node2D
var _overlay: Control
var _toolbar: VBoxContainer
var _ready_done: bool = false
var _initialized: bool = false
var _pending_focus: String = ""

var _region_polys: Dictionary = {}
var _region_lines: Dictionary = {}
var _line_nodes: Array = []
var _last_width_zoom: float = 0.0
var _ui_blockers: Array = []
var _hidden_cities: Dictionary = {}

var _touches: Dictionary = {}
var _press_pos: Vector2 = Vector2.ZERO
var _moved: bool = false
var _multi: bool = false
var _pinch_dist0: float = 1.0
var _pinch_zoom0: float = 1.0
var _pinch_map_pt: Vector2 = Vector2.ZERO
var _mouse_down: bool = false
var _mouse_moved: bool = false
var _mouse_press: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO

var _anim_t: float = -1.0
var _anim_c0: Vector2 = Vector2.ZERO
var _anim_c1: Vector2 = Vector2.ZERO
var _anim_z0: float = 1.0
var _anim_z1: float = 1.0


func _ready() -> void:
	clip_contents = true
	# Касания обрабатываются в _unhandled_input (так же, как в бою), поэтому сам вид события не перехватывает.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_size = DataLoader.territory_map_size
	filter_key = GameState.map_filter
	_build_world()
	_build_overlay()
	_build_toolbar()
	_compute_hidden_cities()
	for tid in DataLoader.territory_order:
		_refresh_region(str(tid))
	GameState.territory_changed.connect(_refresh_region)
	resized.connect(_on_resized)
	_ready_done = true
	_on_resized()
	set_process(false)


func _exit_tree() -> void:
	if _initialized:
		GameState.map_camera = {"center": [center.x, center.y], "rel_zoom": rel_zoom()}


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA_COLOR)


# ---------------------------------------------------------------- построение

func _to_pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


func _add_polygon(pts: PackedVector2Array, color: Color, tex: Texture2D = null, tex_scale: float = 1.0) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = color
	if tex != null:
		poly.texture = tex
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		poly.texture_scale = Vector2(tex_scale, tex_scale)
	_world.add_child(poly)
	return poly


func _add_line(pts: PackedVector2Array, color: Color, px: float, closed_loop: bool) -> Line2D:
	var line := Line2D.new()
	var arr: PackedVector2Array = pts.duplicate()
	if closed_loop and arr.size() > 0:
		arr.append(arr[0])
	line.points = arr
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.set_meta("px", px)
	_world.add_child(line)
	_line_nodes.append(line)
	return line


## Процедурная текстура рельефа (шум); генерируется движком, без файлов в проекте.
func _noise_texture(freq: float, c0: Color, c1: Color, cellular: bool) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if cellular else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	n.seed = 7
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	return t


func _build_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	var geo: Dictionary = DataLoader.geo
	if geo.is_empty():
		push_error("WorldMapView: нет данных глобальной карты (global_geo)")

	_add_polygon(_to_pts(geo.get("land_frame", [])), LAND_COLOR, _noise_texture(0.008, Color("#4f544a"), Color("#6a6d62"), false), 1.0)
	for sea in geo.get("sea", []):
		_add_polygon(_to_pts(sea), SEA_COLOR, _noise_texture(0.012, Color("#1a4d77"), Color("#2a6a97"), false), 1.0)

	var land_tex := _noise_texture(0.010, Color("#3f5f3d"), Color("#7a8a52"), false)
	var field_tex := _noise_texture(0.035, Color("#58704a"), Color("#8c8a58"), true)
	for poly in geo.get("country", []):
		var pts := _to_pts(poly)
		_add_polygon(pts, BASE_COLOR, land_tex, 1.0)
		_add_polygon(pts, Color(1, 1, 1, 0.45), field_tex, 0.5)

	for tid in DataLoader.territory_order:
		var id := str(tid)
		var t := DataLoader.get_territory(id)
		var pts := _to_pts(t.get("polygon", []))
		if pts.size() < 3:
			continue
		_region_polys[id] = _add_polygon(pts, Color(1, 1, 1, 0.0))

	for a in geo.get("areas", []):
		var kind := str(a.get("kind", ""))
		var col := Color(0.10, 0.28, 0.12, 0.30) if kind == "forest" else Color(0.42, 0.36, 0.28, 0.45)
		_add_polygon(_to_pts(a.get("points", [])), col)

	for tid in DataLoader.territory_order:
		var id := str(tid)
		var t := DataLoader.get_territory(id)
		var pts := _to_pts(t.get("polygon", []))
		if pts.size() < 3:
			continue
		_region_lines[id] = _add_line(pts, Color(0.05, 0.08, 0.1, 0.55), 1.2, true)
		for extra in t.get("extra_polygons", []):
			_add_line(_to_pts(extra), Color(0.05, 0.08, 0.1, 0.55), 1.2, true)

	for rv in geo.get("rivers", []):
		_add_line(_to_pts(rv.get("points", [])), Color("#4aa3ff"), float(rv.get("width", 2.0)) * 0.8, false)
	for rd in geo.get("roads", []):
		_add_line(_to_pts(rd.get("points", [])), Color(0.9, 0.78, 0.45, 0.40), 1.0, false)
	for poly in geo.get("country", []):
		_add_line(_to_pts(poly), Color(0.02, 0.03, 0.06, 0.95), 2.4, true)


func _build_overlay() -> void:
	_overlay = Control.new()
	add_child(_overlay)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)


func _build_toolbar() -> void:
	_toolbar = VBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 8)
	add_child(_toolbar)
	_toolbar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toolbar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toolbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toolbar.offset_right = -14
	_toolbar.offset_bottom = -14
	for spec in [["+", 0], ["-", 1], ["Вся", 2]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.custom_minimum_size = Vector2(68, 68)
		b.add_theme_font_size_override("font_size", 26 if int(spec[1]) < 2 else 18)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_tool.bind(int(spec[1])))
		_toolbar.add_child(b)
	register_ui_blocker(_toolbar)


## Города, совпадающие с маркерами мест, не рисуем отдельно (чтобы не загромождать карту).
func _compute_hidden_cities() -> void:
	_hidden_cities.clear()
	for c in DataLoader.geo.get("cities", []):
		var cp := _v(c.get("pos", [0, 0]))
		for pl in DataLoader.places:
			var pp: Variant = pl.get("pos", null)
			if pp != null and cp.distance_to(_v(pp)) < 9.0:
				_hidden_cities[str(c.get("id", ""))] = true
				break


## Элементы интерфейса поверх карты: касания по ним не двигают карту.
func register_ui_blocker(c: Control) -> void:
	_ui_blockers.append(c)


func _on_tool(kind: int) -> void:
	match kind:
		0:
			_zoom_at(size * 0.5, zoom * 1.5, true)
		1:
			_zoom_at(size * 0.5, zoom / 1.5, true)
		2:
			show_all(true)


# ---------------------------------------------------------------- камера

func fit_zoom() -> float:
	if size.x <= 1.0 or size.y <= 1.0:
		return 1.0
	return minf(size.x / _map_size.x, size.y / _map_size.y)


func rel_zoom() -> float:
	return zoom / maxf(fit_zoom(), 0.0001)


func map_to_screen(p: Vector2) -> Vector2:
	return (p - center) * zoom + size * 0.5


func screen_to_map(s: Vector2) -> Vector2:
	return (s - size * 0.5) / zoom + center


func show_all(animated: bool) -> void:
	_set_camera(_map_size * 0.5, fit_zoom() * 0.98, animated)


func focus_on(map_pos: Vector2, rel: float, animated: bool = true) -> void:
	_set_camera(map_pos, fit_zoom() * rel, animated)


func _on_resized() -> void:
	if not _ready_done or size.x <= 1.0 or size.y <= 1.0:
		return
	if not _initialized:
		_initialized = true
		var saved: Dictionary = GameState.map_camera
		if saved.is_empty():
			center = _map_size * 0.5
			zoom = fit_zoom() * 0.98
		else:
			var c: Array = saved.get("center", [_map_size.x * 0.5, _map_size.y * 0.5])
			center = Vector2(float(c[0]), float(c[1]))
			zoom = fit_zoom() * float(saved.get("rel_zoom", 1.0))
		if _pending_focus != "":
			var pp: Variant = _place_pos(DataLoader.get_place(_pending_focus))
			if pp != null:
				center = pp
				zoom = fit_zoom() * 1.7
			_pending_focus = ""
	_clamp_camera()
	_apply_camera()


func _set_camera(c: Vector2, z: float, animated: bool) -> void:
	var fz := fit_zoom()
	z = clampf(z, fz * MIN_REL_ZOOM, fz * MAX_REL_ZOOM)
	c = Vector2(clampf(c.x, 0.0, _map_size.x), clampf(c.y, 0.0, _map_size.y))
	if animated:
		_anim_c0 = center
		_anim_c1 = c
		_anim_z0 = zoom
		_anim_z1 = z
		_anim_t = 0.0
		_vel = Vector2.ZERO
		set_process(true)
	else:
		center = c
		zoom = z
		_apply_camera()


func _clamp_camera() -> void:
	var fz := fit_zoom()
	zoom = clampf(zoom, fz * MIN_REL_ZOOM, fz * MAX_REL_ZOOM)
	center.x = clampf(center.x, 0.0, _map_size.x)
	center.y = clampf(center.y, 0.0, _map_size.y)


func _apply_camera() -> void:
	if _world == null:
		return
	_world.scale = Vector2(zoom, zoom)
	_world.position = size * 0.5 - center * zoom
	_update_line_widths(false)
	_overlay.queue_redraw()
	camera_changed.emit()


func _update_line_widths(force: bool) -> void:
	if not force and _last_width_zoom > 0.0 and absf(zoom / _last_width_zoom - 1.0) < 0.02:
		return
	_last_width_zoom = zoom
	for n in _line_nodes:
		var line: Line2D = n
		line.width = float(line.get_meta("px", 2.0)) / zoom


func _pan_screen(rel: Vector2) -> void:
	center -= rel / zoom
	_clamp_camera()
	_apply_camera()


func _zoom_at(screen_pos: Vector2, new_zoom: float, animated: bool = false) -> void:
	var fz := fit_zoom()
	new_zoom = clampf(new_zoom, fz * MIN_REL_ZOOM, fz * MAX_REL_ZOOM)
	var pt := screen_to_map(screen_pos)
	var new_center := pt - (screen_pos - size * 0.5) / new_zoom
	_set_camera(new_center, new_zoom, animated)


func _process(delta: float) -> void:
	var active := false
	if _anim_t >= 0.0:
		_anim_t = minf(_anim_t + delta / ANIM_TIME, 1.0)
		var k := _anim_t * _anim_t * (3.0 - 2.0 * _anim_t)
		zoom = exp(lerpf(log(_anim_z0), log(_anim_z1), k))
		center = _anim_c0.lerp(_anim_c1, k)
		_apply_camera()
		if _anim_t >= 1.0:
			_anim_t = -1.0
		else:
			active = true
	elif _touches.is_empty() and not _mouse_down and _vel.length() > 25.0:
		_pan_screen(_vel * delta)
		_vel *= exp(-4.5 * delta)
		active = true
	else:
		_vel = Vector2.ZERO
	if not active:
		set_process(false)


# ---------------------------------------------------------------- ввод

func _over_ui(pos: Vector2) -> bool:
	for b in _ui_blockers:
		var c: Control = b
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


func _inside(pos: Vector2) -> bool:
	return get_global_rect().has_point(pos) and not _over_ui(pos)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event as InputEventMouseMotion)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if not _inside(e.position):
			return
		_anim_t = -1.0
		_touches[e.index] = e.position
		_vel = Vector2.ZERO
		if _touches.size() == 1:
			_press_pos = e.position
			_moved = false
			_multi = false
		else:
			_multi = true
			_begin_pinch()
	else:
		if not _touches.has(e.index):
			return
		var was_single := _touches.size() == 1
		_touches.erase(e.index)
		if was_single and not _moved and not _multi:
			_tap(make_canvas_position_local(e.position))
		elif _touches.size() == 1:
			_moved = true
		if _touches.is_empty() and _vel.length() > 25.0:
			set_process(true)


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _touches.size() == 1:
		if not _moved and e.position.distance_to(_press_pos) > TAP_SLOP:
			_moved = true
		if _moved:
			_pan_screen(e.relative)
			_vel = _vel.lerp(e.velocity, 0.5)
	elif _touches.size() >= 2:
		_update_pinch()


func _two_points() -> Array:
	var vals: Array = _touches.values()
	var a: Vector2 = vals[0]
	var b: Vector2 = vals[1]
	return [a, b]


func _begin_pinch() -> void:
	var pts := _two_points()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	_pinch_dist0 = maxf(a.distance_to(b), 1.0)
	_pinch_zoom0 = zoom
	_pinch_map_pt = screen_to_map(make_canvas_position_local((a + b) * 0.5))


func _update_pinch() -> void:
	var pts := _two_points()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var fz := fit_zoom()
	zoom = clampf(_pinch_zoom0 * a.distance_to(b) / _pinch_dist0, fz * MIN_REL_ZOOM, fz * MAX_REL_ZOOM)
	var mid := make_canvas_position_local((a + b) * 0.5)
	center = _pinch_map_pt - (mid - size * 0.5) / zoom
	_clamp_camera()
	_apply_camera()


func _is_emulated(e: InputEvent) -> bool:
	return e.device == InputEvent.DEVICE_ID_EMULATION or not _touches.is_empty()


func _on_mouse_button(e: InputEventMouseButton) -> void:
	if _is_emulated(e):
		return
	if e.pressed:
		if not _inside(e.position):
			return
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(make_canvas_position_local(e.position), zoom * 1.2)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(make_canvas_position_local(e.position), zoom / 1.2)
		elif e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_MIDDLE or e.button_index == MOUSE_BUTTON_RIGHT:
			_anim_t = -1.0
			_mouse_down = true
			_mouse_moved = false
			_mouse_press = e.position
	else:
		if _mouse_down and not _mouse_moved and e.button_index == MOUSE_BUTTON_LEFT:
			_tap(make_canvas_position_local(e.position))
		if e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_MIDDLE or e.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_down = false


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if not _mouse_down or _is_emulated(e):
		return
	if not _mouse_moved and e.position.distance_to(_mouse_press) > TAP_SLOP:
		_mouse_moved = true
	if _mouse_moved:
		_pan_screen(e.relative)


# ---------------------------------------------------------------- места сценариев

static func event_group(ev: Dictionary) -> String:
	if str(ev.get("date_status", "")) == "fictional":
		return "test"
	var years: Array = ev.get("years", [])
	if years.is_empty():
		return "none"
	var y := int(years[0])
	if y <= 2014:
		return "2014"
	if y == 2022:
		return "2022"
	if y == 2023:
		return "2023"
	return "2024"


static func place_matches(pl: Dictionary, key: String) -> bool:
	if key == "":
		return true
	for ev in pl.get("events", []):
		var g := event_group(ev)
		if key == g:
			return true
	return false


func set_filter(key: String) -> void:
	filter_key = key
	GameState.map_filter = key
	if selected_place != "" and not place_matches(DataLoader.get_place(selected_place), key):
		select_place("")
	_overlay.queue_redraw()


func _place_pos(pl: Dictionary) -> Variant:
	var p: Variant = pl.get("pos", null)
	if p == null:
		return null
	return _v(p)


func place_at(local_pos: Vector2) -> String:
	var best := PICK_RADIUS
	var best_id := ""
	for pl in DataLoader.places:
		var p: Variant = _place_pos(pl)
		if p == null or not place_matches(pl, filter_key):
			continue
		var d := map_to_screen(p).distance_to(local_pos)
		if d < best:
			best = d
			best_id = str(pl.get("id", ""))
	return best_id


func _tap(local_pos: Vector2) -> void:
	var id := place_at(local_pos)
	if id == "":
		return
	select_place(id)
	var p: Variant = _place_pos(DataLoader.get_place(id))
	if p != null and rel_zoom() < 1.4:
		focus_on(p, 1.7)
	place_selected.emit(id)


func select_place(id: String) -> void:
	selected_place = id
	if _overlay != null:
		_overlay.queue_redraw()


## Показать место: сразу (если карта ещё не построена по размеру) или плавным перелётом.
func focus_place(id: String) -> void:
	var p: Variant = _place_pos(DataLoader.get_place(id))
	if p == null:
		return
	if _initialized:
		focus_on(p, 1.7, true)
	else:
		_pending_focus = id


func _region_label_pos(id: String) -> Vector2:
	var lp: Array = DataLoader.get_territory(id).get("label_pos", [_map_size.x * 0.5, _map_size.y * 0.5])
	return Vector2(float(lp[0]), float(lp[1]))


func _refresh_region(id: String) -> void:
	if not _region_polys.has(id):
		return
	var poly: Polygon2D = _region_polys[id]
	var line: Line2D = _region_lines[id]
	var st := GameState.get_territory_state(id)
	var control := str(st.get("control", "neutral"))
	var col := DataLoader.get_faction_color(str(st.get("owner", "neutral")))
	# Контроль рисуется только если он задан состоянием карты на дату; нейтральные области — без заливки.
	match control:
		"controlled":
			col.a = 0.55
		"contested":
			col.a = 0.35
		_:
			col.a = 0.0
	poly.color = col
	if control == "contested":
		line.default_color = Color("#facc15")
		line.set_meta("px", 2.2)
	else:
		line.default_color = Color(0.05, 0.08, 0.1, 0.55)
		line.set_meta("px", 1.2)
	_update_line_widths(true)


# ---------------------------------------------------------------- подписи (экранное пространство)

func _v(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	_overlay.draw_string(font, pos + Vector2(-110.0 + 1.0, 1.0), text, HORIZONTAL_ALIGNMENT_CENTER, 220.0, font_size, Color(0, 0, 0, 0.75 * color.a))
	_overlay.draw_string(font, pos + Vector2(-110.0, 0.0), text, HORIZONTAL_ALIGNMENT_CENTER, 220.0, font_size, color)


func _label_rect(pos: Vector2, text: String, font_size: int) -> Rect2:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	return Rect2(pos.x - w * 0.5 - 2.0, pos.y - float(font_size), w + 4.0, float(font_size) + 4.0)


func _draw_overlay() -> void:
	if size.x <= 1.0:
		return
	var rz := rel_zoom()
	var view_rect := Rect2(Vector2(-60, -40), size + Vector2(120, 80))

	for l in DataLoader.geo.get("labels", []):
		var sp := map_to_screen(_v(l.get("pos", [0, 0])))
		if not view_rect.has_point(sp):
			continue
		if str(l.get("kind", "")) == "sea":
			_text(sp, str(l.get("text", "")), 15, Color(0.72, 0.87, 1.0, 0.7))
		else:
			_text(sp, str(l.get("text", "")), 13, Color(1, 1, 1, 0.38))

	# области — только географическая подпись, слабее и мельче подписей мест
	var region_alpha := 0.55 if rz < 2.2 else clampf(0.55 - (rz - 2.2) * 0.3, 0.0, 0.55)
	if region_alpha > 0.02:
		var rsize := int(clampf(9.0 + rz * 1.2, 10.0, 15.0))
		for tid in DataLoader.territory_order:
			var id := str(tid)
			var t := DataLoader.get_territory(id)
			var sp := map_to_screen(_region_label_pos(id))
			if view_rect.has_point(sp):
				_text(sp, str(t.get("short", t.get("name", id))), rsize, Color(1, 1, 1, region_alpha))

	for c in DataLoader.geo.get("cities", []):
		var tier := int(c.get("tier", 4))
		if _hidden_cities.has(str(c.get("id", ""))):
			continue
		if tier >= 3 and rz < 2.2:
			continue
		if tier == 2 and rz < 1.3:
			continue
		var sp := map_to_screen(_v(c.get("pos", [0, 0])))
		if not view_rect.has_point(sp):
			continue
		var radius := 4.4 if tier == 1 else (3.0 if tier == 2 else 2.4)
		_overlay.draw_circle(sp, radius + 1.2, Color(0, 0, 0, 0.7))
		_overlay.draw_circle(sp, radius, Color(0.92, 0.92, 0.92))
		if tier == 1 or rz >= 2.0:
			_text(sp + Vector2(0, -radius - 4.0), str(c.get("name", "")), 12, Color(1, 1, 1, 0.8))

	_draw_places(rz, view_rect)
	_draw_legend()


func _draw_places(rz: float, view_rect: Rect2) -> void:
	var items: Array = []
	for pl in DataLoader.places:
		var p: Variant = _place_pos(pl)
		if p == null or not place_matches(pl, filter_key):
			continue
		var sp := map_to_screen(p)
		if view_rect.has_point(sp):
			items.append({"pl": pl, "sp": sp})
	items.sort_custom(func(a, b): return int(a["pl"].get("priority", 3)) < int(b["pl"].get("priority", 3)))

	var used: Array = []
	for it in items:
		var pl: Dictionary = it["pl"]
		var sp: Vector2 = it["sp"]
		var prio := int(pl.get("priority", 3))
		var evs: Array = pl.get("events", [])
		var ev: Dictionary = evs[0] if not evs.is_empty() else {}
		var grp := event_group(ev)
		var col: Color = GROUP_COLORS.get(grp, Color.WHITE)
		var status := str(ev.get("date_status", ""))
		var verified := status == "verified" or status == "partial"
		var r := 9.0 if prio == 1 else (7.5 if prio == 2 else 6.5)
		var pts := PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r, 0), sp + Vector2(0, r), sp + Vector2(-r, 0)])
		var fill := col
		fill.a = 1.0 if (verified or status == "fictional") else 0.6
		_overlay.draw_colored_polygon(pts, fill)
		var outline: PackedVector2Array = pts.duplicate()
		outline.append(pts[0])
		_overlay.draw_polyline(outline, Color(0, 0, 0, 0.9), 1.6)
		if verified:
			_overlay.draw_circle(sp, 2.0, Color(0, 0, 0, 0.85))
		# итог игрока по сценарию места
		for e in evs:
			var res := GameState.get_result(str(e.get("scenario_id", "")))
			if not res.is_empty():
				var oc := str(res.get("outcome", ""))
				var bc := Color("#22c55e") if oc == "victory" else (Color("#ef4444") if oc == "defeat" else Color("#9ca3af"))
				_overlay.draw_circle(sp + Vector2(r, -r), 4.5, bc)
				_overlay.draw_arc(sp + Vector2(r, -r), 4.5, 0.0, TAU, 12, Color.BLACK, 1.2)
				break
		if str(pl.get("id", "")) == selected_place:
			_overlay.draw_arc(sp, r + 6.0, 0.0, TAU, 28, Color.WHITE, 2.4)
		it["r"] = r

	# подписи: по убыванию приоритета, без наложений
	for it in items:
		var pl: Dictionary = it["pl"]
		var sp: Vector2 = it["sp"]
		var prio := int(pl.get("priority", 3))
		var sel := str(pl.get("id", "")) == selected_place
		var show_label := sel or (prio == 1 and rz >= 1.0) or (prio == 2 and rz >= 1.7) or (prio >= 3 and rz >= 2.8)
		if not show_label:
			continue
		var pname := str(pl.get("name", ""))
		var pos := sp + Vector2(0, -float(it.get("r", 7.0)) - 5.0)
		var rect := _label_rect(pos, pname, 13)
		var clash := false
		for u in used:
			if (u as Rect2).intersects(rect):
				clash = true
				break
		if clash and not sel:
			continue
		used.append(rect)
		_text(pos, pname, 13, Color(1, 1, 1, 1.0))


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var x := 12.0
	var y := size.y - 14.0
	_overlay.draw_rect(Rect2(6, y - 24, 520, 34), Color(0, 0, 0, 0.5))
	var items := [["2014", "2014"], ["2022", "2022"], ["2023", "2023"], ["2024", "2024+"], ["test", "Тест"]]
	for it in items:
		var col: Color = GROUP_COLORS[str(it[0])]
		var c := Vector2(x + 7.0, y - 7.0)
		_overlay.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)]), col)
		_overlay.draw_string(font, Vector2(x + 18, y - 2), str(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1, 1, 1, 0.9))
		x += 78.0 if str(it[0]) != "2024" else 88.0
	_overlay.draw_string(font, Vector2(x + 4, y - 2), "тусклый маркер — даты не сверены", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(1, 1, 1, 0.7))
