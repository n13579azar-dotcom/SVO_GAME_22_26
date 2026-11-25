extends Camera2D
## Камера: плавное перемещение, зум колесом/щипком, границы карты.
## Перетаскивание одним пальцем вызывает pan_by() из input_controller.gd.

@export var max_zoom: float = 2.5
@export var zoom_step: float = 1.12
@export var smooth_speed: float = 14.0
@export var key_pan_speed: float = 900.0

var map_rect: Rect2 = Rect2(0, 0, 3200, 2000)
var min_zoom: float = 0.3
var target_pos: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0

var _touches: Dictionary = {}
var _pinch_prev_dist: float = 0.0
var _pinch_prev_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	make_current()
	position_smoothing_enabled = false
	target_pos = position
	target_zoom = zoom.x
	get_viewport().size_changed.connect(_on_viewport_resized)


func set_bounds(rect: Rect2) -> void:
	map_rect = rect
	_recalc_limits()
	target_zoom = clampf(target_zoom, min_zoom, max_zoom)
	target_pos = _clamp_pos(target_pos, target_zoom)
	zoom = Vector2.ONE * target_zoom
	position = target_pos


func focus_on(world_pos: Vector2, new_zoom: float = -1.0) -> void:
	if new_zoom > 0.0:
		target_zoom = clampf(new_zoom, min_zoom, max_zoom)
	target_pos = _clamp_pos(world_pos, target_zoom)


func is_pinching() -> bool:
	return _touches.size() >= 2


func pan_by(screen_delta: Vector2) -> void:
	target_pos = _clamp_pos(target_pos - screen_delta / target_zoom, target_zoom)
	position = target_pos


func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var half := get_viewport_rect().size * 0.5
	var world_before := target_pos + (screen_pos - half) / target_zoom
	target_zoom = clampf(target_zoom * factor, min_zoom, max_zoom)
	target_pos = _clamp_pos(world_before - (screen_pos - half) / target_zoom, target_zoom)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		target_pos = _clamp_pos(target_pos + dir.normalized() * key_pan_speed * delta / target_zoom, target_zoom)

	var w := 1.0 - exp(-smooth_speed * delta)
	var z := lerpf(zoom.x, target_zoom, w)
	if absf(z - target_zoom) < 0.0005:
		z = target_zoom
	zoom = Vector2.ONE * z
	position = _clamp_pos(position.lerp(target_pos, w), z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, zoom_step)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 1.0 / zoom_step)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)) != 0:
			pan_by(mm.relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_reset_pinch()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		_update_pinch()


func _reset_pinch() -> void:
	_pinch_prev_dist = 0.0
	if _touches.size() >= 2:
		var pts := _first_two()
		_pinch_prev_dist = pts[0].distance_to(pts[1])
		_pinch_prev_center = (pts[0] + pts[1]) * 0.5


func _update_pinch() -> void:
	if _touches.size() < 2:
		return
	var pts := _first_two()
	var dist: float = pts[0].distance_to(pts[1])
	var center: Vector2 = (pts[0] + pts[1]) * 0.5
	if _pinch_prev_dist > 10.0 and dist > 10.0:
		zoom_at(center, dist / _pinch_prev_dist)
		pan_by(center - _pinch_prev_center)
	_pinch_prev_dist = dist
	_pinch_prev_center = center


func _first_two() -> Array:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _recalc_limits() -> void:
	var vp := get_viewport_rect().size
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	min_zoom = maxf(vp.x / map_rect.size.x, vp.y / map_rect.size.y)
	min_zoom = minf(min_zoom, max_zoom)


func _on_viewport_resized() -> void:
	_recalc_limits()
	target_zoom = clampf(target_zoom, min_zoom, max_zoom)


func _clamp_pos(p: Vector2, z: float) -> Vector2:
	var half := get_viewport_rect().size / z * 0.5
	var lo := map_rect.position + half
	var hi := map_rect.end - half
	var out := p
	out.x = map_rect.get_center().x if lo.x > hi.x else clampf(p.x, lo.x, hi.x)
	out.y = map_rect.get_center().y if lo.y > hi.y else clampf(p.y, lo.y, hi.y)
	return out
