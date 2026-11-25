extends Control
## Круговое меню команд. Привязано к мировой точке и следует за камерой
## при перемещении и масштабировании.

signal command_chosen(command_id: String)

const CommandDefs := preload("res://scripts/commands/command_defs.gd")

const RADIUS := 100.0
const BUTTON_SIZE := Vector2(96, 54)

var anchor_world: Vector2 = Vector2.ZERO
var _buttons: Array = []
var _close_btn: Button = null
var _tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open_menu(command_ids: Array, world_pos: Vector2) -> void:
	_clear()
	anchor_world = world_pos
	var n := command_ids.size()
	for i in n:
		var id: String = command_ids[i]
		var def := CommandDefs.get_def(id)
		var b := Button.new()
		b.text = str(def.get("label", id))
		b.custom_minimum_size = BUTTON_SIZE
		b.size = BUTTON_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		var angle := -PI / 2.0 + TAU * float(i) / float(n)
		b.position = Vector2.from_angle(angle) * RADIUS - BUTTON_SIZE * 0.5
		b.pressed.connect(_on_command_pressed.bind(id))
		add_child(b)
		_buttons.append(b)

	_close_btn = Button.new()
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(52, 52)
	_close_btn.size = Vector2(52, 52)
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.position = Vector2(-26, -26)
	_close_btn.pressed.connect(close_menu)
	add_child(_close_btn)

	visible = true
	_update_position()
	scale = Vector2(0.6, 0.6)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.12)
	queue_redraw()


func close_menu() -> void:
	if not visible:
		return
	visible = false
	_clear()


func _clear() -> void:
	for b in _buttons:
		if is_instance_valid(b):
			b.queue_free()
	_buttons.clear()
	if _close_btn != null and is_instance_valid(_close_btn):
		_close_btn.queue_free()
	_close_btn = null


func _on_command_pressed(id: String) -> void:
	command_chosen.emit(id)


func _process(_delta: float) -> void:
	if visible:
		_update_position()


func _update_position() -> void:
	var screen := get_viewport().get_canvas_transform() * anchor_world
	var vp := get_viewport_rect().size
	var m := RADIUS + BUTTON_SIZE.x * 0.5 + 8.0
	position = Vector2(
		clampf(screen.x, m, maxf(m, vp.x - m)),
		clampf(screen.y, m + 60.0, maxf(m + 60.0, vp.y - m)))


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS + 38.0, Color(0, 0, 0, 0.28))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
