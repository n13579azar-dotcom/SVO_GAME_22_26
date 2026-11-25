extends Node
## Обработка ввода в бою: выделение (одно/несколько/рамка), открытие командного
## интерфейса, выбор команды и точки назначения. Работает с мышью и касаниями.
## Камеру двигает перетаскивание по пустому месту (в режиме рамки — рисует рамку).

const CommandDefs := preload("res://scripts/commands/command_defs.gd")
const CommandExecutor := preload("res://scripts/commands/command_executor.gd")

enum State { IDLE, PICK_TARGET }

const DRAG_THRESHOLD := 14.0
const TAP_PAD_SCREEN := 26.0

var battle: Node = null
var camera: Camera2D = null
var selection: RefCounted = null
var radial: Control = null
var vehicle_panel: Control = null
var hud: Control = null

var state: int = State.IDLE
var pending_command: String = ""
var multi_mode: bool = false

var _pressed: bool = false
var _dragging: bool = false
var _box_mode: bool = false
var _press_pos: Vector2 = Vector2.ZERO


func setup(p_battle: Node, p_camera: Camera2D, p_selection: RefCounted, p_radial: Control, p_vehicle: Control, p_hud: Control) -> void:
	battle = p_battle
	camera = p_camera
	selection = p_selection
	radial = p_radial
	vehicle_panel = p_vehicle
	hud = p_hud
	selection.changed.connect(_on_selection_changed)


func set_multi_mode(on: bool) -> void:
	multi_mode = on


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _unhandled_input(event: InputEvent) -> void:
	if battle == null or battle.finished:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pressed = true
			_dragging = false
			_press_pos = mb.position
			_box_mode = multi_mode or Input.is_key_pressed(KEY_SHIFT)
		else:
			if _pressed:
				if _dragging and _box_mode and not camera.is_pinching():
					_finish_box(mb.position)
				elif not _dragging:
					_handle_tap(mb.position)
			_pressed = false
			_dragging = false
			hud.set_box(Rect2(), false)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not _pressed or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		if camera.is_pinching():
			_dragging = true
			_box_mode = false
			hud.set_box(Rect2(), false)
			return
		if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			if _box_mode:
				hud.set_box(_screen_rect(_press_pos, mm.position), true)
			else:
				camera.pan_by(mm.relative)


func _screen_rect(a: Vector2, b: Vector2) -> Rect2:
	var top_left := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var bottom_right := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(top_left, bottom_right - top_left)


func _handle_tap(screen_pos: Vector2) -> void:
	var world := screen_to_world(screen_pos)

	if state == State.PICK_TARGET:
		_finish_target(world)
		return

	var pad := TAP_PAD_SCREEN / camera.zoom.x
	var u: Node2D = battle.pick_player_unit(world, pad)
	if u != null:
		if multi_mode:
			selection.toggle(u)
			radial.close_menu()
		else:
			if selection.has(u) and selection.units.size() > 1:
				pass
			else:
				selection.set_units([u])
			open_command_ui()
	else:
		selection.clear()
		radial.close_menu()
		vehicle_panel.close_panel()


func _finish_box(screen_end: Vector2) -> void:
	var a := screen_to_world(_press_pos)
	var b := screen_to_world(screen_end)
	var rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(a.x - b.x), absf(a.y - b.y)))
	var found: Array = battle.units_in_rect(rect, true)
	if found.is_empty():
		return
	selection.add_many(found)
	open_command_ui()


# ---------------------------------------------------------------- команды

## Показывает круговое меню (пехота/смешанная группа) или панель техники.
func open_command_ui() -> void:
	selection.prune()
	if selection.is_empty():
		hud.toast("Сначала выберите подразделения")
		return
	var cmds: Array = CommandDefs.available_for(selection.units, battle)
	if cmds.is_empty():
		hud.toast("Нет общих команд для этой группы")
		return
	var all_vehicles := true
	for u in selection.units:
		if str(u.type_data.get("category", "")) != "vehicle":
			all_vehicles = false
			break
	if all_vehicles:
		radial.close_menu()
		vehicle_panel.open_panel(selection.units, cmds)
	else:
		vehicle_panel.close_panel()
		radial.open_menu(cmds, selection.centroid())


func on_command_chosen(cmd: String) -> void:
	var def := CommandDefs.get_def(cmd)
	radial.close_menu()
	if bool(def.get("needs_target", false)):
		pending_command = cmd
		state = State.PICK_TARGET
		vehicle_panel.close_panel()
		hud.show_hint("%s — %s" % [def.label, def.hint])
		hud.set_cancel_visible(true)
	else:
		var ok := CommandExecutor.execute(cmd, selection.units, Vector2.ZERO, battle)
		hud.toast("Команда: %s" % def.label if ok else "Команда недоступна")
		if all_selected_vehicles():
			open_command_ui()


func all_selected_vehicles() -> bool:
	if selection.is_empty():
		return false
	for u in selection.units:
		if str(u.type_data.get("category", "")) != "vehicle":
			return false
	return true


func _finish_target(world: Vector2) -> void:
	var cmd := pending_command
	var ok := CommandExecutor.execute(cmd, selection.units, world, battle)
	if not ok:
		hud.toast("Здесь нельзя выполнить команду")
		return
	battle.spawn_marker(battle.clamp_to_map(world), Color(1, 1, 0.4))
	cancel_pending()


func cancel_pending() -> void:
	state = State.IDLE
	pending_command = ""
	if hud != null:
		hud.hide_hint()
		hud.set_cancel_visible(false)


func _on_selection_changed(_units: Array) -> void:
	if selection.is_empty():
		radial.close_menu()
		vehicle_panel.close_panel()
		if state == State.PICK_TARGET:
			cancel_pending()
