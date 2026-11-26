extends Node2D
## Контроллер матча: загружает сценарий, создаёт карту, точки и подразделения,
## ведёт симуляцию (с паузой и ускорением) и связывает интерфейс, ввод, ИИ и правила.

const UnitScene := preload("res://scenes/units/unit.tscn")
const ControlPointScene := preload("res://scenes/battle/control_point.tscn")
const SelectionManager := preload("res://scripts/units/selection_manager.gd")
const EnemyAI := preload("res://scripts/ai/enemy_ai.gd")
const OrderMarker := preload("res://scripts/battle/order_marker.gd")
const TerrainScript := preload("res://scripts/battle/terrain.gd")
const WreckScript := preload("res://scripts/battle/wreck.gd")

const MAX_SIM_STEP := 0.05
const MAX_STEPS_PER_FRAME := 12

@onready var battle_map: Node2D = $BattleMap
@onready var objectives_node: Node2D = $Objectives
@onready var units_node: Node2D = $Units
@onready var markers_node: Node2D = $Markers
@onready var camera: Camera2D = $Camera
@onready var clock: Node = $GameClock
@onready var rules: Node = $MatchRules
@onready var input_controller: Node = $InputController
@onready var hud: Control = $UI/Hud
@onready var radial_menu: Control = $UI/RadialMenu
@onready var vehicle_panel: Control = $UI/VehiclePanel

var scenario_id: String = ""
var scenario: Dictionary = {}
var player_faction: String = ""
var map_rect: Rect2 = Rect2(0, 0, 3200, 2000)

var units: Array = []
var points: Array = []
var ai_controllers: Array = []
var selection := SelectionManager.new()
var finished: bool = false
var terrain := TerrainScript.new()
## faction_id -> число потерянных подразделений
var losses: Dictionary = {}
var _next_uid: int = 1
var _tick: int = 0


func _ready() -> void:
	scenario_id = GameState.current_scenario_id
	if scenario_id == "" and not DataLoader.scenario_order.is_empty():
		scenario_id = str(DataLoader.scenario_order[0])
	scenario = DataLoader.get_scenario(scenario_id)
	if scenario.is_empty():
		push_error("Battle: сценарий не найден: %s" % scenario_id)
		GameState.change_scene(GameState.SCENE_MAIN_MENU)
		return

	player_faction = GameState.current_side
	if player_faction == "":
		player_faction = str(scenario["sides"][0].get("faction", ""))

	_build_map()
	_spawn_objectives()
	_spawn_units()
	_setup_camera()
	_setup_ai()
	_setup_ui()

	rules.setup(self, scenario, player_faction)
	rules.finished.connect(_on_match_finished)


func _process(delta: float) -> void:
	if finished:
		return
	var time_scale: float = clock.get_scale()
	if time_scale > 0.0:
		var remaining := delta * time_scale
		var steps := clampi(ceili(remaining / MAX_SIM_STEP), 1, MAX_STEPS_PER_FRAME)
		var step := remaining / float(steps)
		for i in steps:
			_sim_step(step)
			if finished:
				break
	selection.prune()


func _sim_step(dt: float) -> void:
	clock.advance(dt)
	_tick += 1
	var order: Array = units.duplicate()
	if _tick % 2 == 1:
		order.reverse()  # чередуем порядок обработки: нет «преимущества первого хода»
	for u in order:
		if is_instance_valid(u):
			u.sim_step(dt)
	_separate_units()
	for p in points:
		p.sim_step(dt, units)
	for a in ai_controllers:
		a.sim_step(dt)
	rules.sim_step(dt, clock.elapsed)


# ---------------------------------------------------------------- построение

func _build_map() -> void:
	var map_data: Dictionary = scenario.get("map", {})
	battle_map.setup(map_data)
	terrain.setup(map_data.get("features", []))
	var sz: Array = map_data.get("size", [3200, 2000])
	map_rect = Rect2(0, 0, float(sz[0]), float(sz[1]))


func _spawn_objectives() -> void:
	for o in scenario.get("objectives", []):
		var p := ControlPointScene.instantiate()
		objectives_node.add_child(p)
		p.setup(o)
		points.append(p)


func _spawn_units() -> void:
	for side in scenario.get("sides", []):
		var fid := str(side.get("faction", ""))
		for entry in side.get("units", []):
			var type_data: Dictionary = DataLoader.get_unit_type(str(entry.get("type", "")))
			if type_data.is_empty():
				push_warning("Battle: неизвестный тип подразделения: %s" % entry.get("type", ""))
				continue
			var count := int(entry.get("count", 1))
			var base: Array = entry.get("pos", [0, 0])
			var base_pos := Vector2(float(base[0]), float(base[1]))
			var cols := int(ceil(sqrt(float(count))))
			for i in count:
				var off := Vector2(float(i % cols) * 44.0, float(i / cols) * 44.0)
				_create_unit(type_data, fid, base_pos + off)


func _create_unit(type_data: Dictionary, fid: String, pos: Vector2) -> Node2D:
	var u: Node2D = UnitScene.instantiate()
	units_node.add_child(u)
	u.setup(self, type_data, fid, pos, _next_uid, fid == player_faction)
	_next_uid += 1
	u.died.connect(_on_unit_died)
	units.append(u)
	return u


func _setup_camera() -> void:
	camera.set_bounds(map_rect)
	var focus := Vector2.ZERO
	var n := 0
	for u in units:
		if u.is_player:
			focus += u.position
			n += 1
	focus = focus / float(n) if n > 0 else map_rect.get_center()
	camera.focus_on(focus, 0.8)
	camera.position = camera.target_pos
	camera.zoom = Vector2.ONE * camera.target_zoom


func _setup_ai() -> void:
	for side in scenario.get("sides", []):
		var fid := str(side.get("faction", ""))
		if fid == player_faction:
			continue
		var ai := EnemyAI.new()
		add_child(ai)
		ai.setup(self, fid, side)
		ai_controllers.append(ai)


func _setup_ui() -> void:
	hud.bind(self, clock, selection)
	input_controller.setup(self, camera, selection, radial_menu, vehicle_panel, hud)
	hud.multi_mode_toggled.connect(input_controller.set_multi_mode)
	hud.commands_requested.connect(input_controller.open_command_ui)
	hud.cancel_requested.connect(input_controller.cancel_pending)
	hud.world_map_requested.connect(func(): GameState.change_scene(GameState.SCENE_WORLD_MAP))
	hud.menu_requested.connect(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
	hud.restart_requested.connect(func(): get_tree().reload_current_scene())
	radial_menu.command_chosen.connect(input_controller.on_command_chosen)
	vehicle_panel.command_chosen.connect(input_controller.on_command_chosen)


# ---------------------------------------------------------------- события

func _on_unit_died(u: Node2D) -> void:
	units.erase(u)
	losses[u.faction_id] = int(losses.get(u.faction_id, 0)) + 1
	spawn_wreck(u.position, u.faction_color, u.radius)


func _on_match_finished(result: Dictionary) -> void:
	if finished:
		return
	finished = true
	selection.clear()
	radial_menu.close_menu()
	vehicle_panel.close_panel()
	input_controller.cancel_pending()
	var own := int(losses.get(player_faction, 0))
	var total := 0
	for f in losses.keys():
		total += int(losses[f])
	result["losses_own"] = own
	result["losses_enemy"] = total - own
	GameState.finish_scenario(scenario_id, player_faction, result)
	hud.show_result(result)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and hud != null and not finished:
		hud.toggle_pause_menu()


# ---------------------------------------------------------------- запросы

func clamp_to_map(pos: Vector2, margin: float = 0.0) -> Vector2:
	return Vector2(
		clampf(pos.x, map_rect.position.x + margin, map_rect.end.x - margin),
		clampf(pos.y, map_rect.position.y + margin, map_rect.end.y - margin))


func terrain_at(pos: Vector2) -> String:
	return terrain.kind_at(pos)


## Противники в радиусе (для выбора цели). Посаженные в транспорт не учитываются.
func enemies_in_range(unit: Node2D, max_range: float) -> Array:
	var out: Array = []
	var r2 := max_range * max_range
	for u in units:
		if not is_instance_valid(u) or not u.alive or u.carried_by != null:
			continue
		if u.faction_id == unit.faction_id:
			continue
		if unit.position.distance_squared_to(u.position) <= r2:
			out.append(u)
	return out


## Свои подразделения в радиусе (без самого unit, без посаженных в транспорт).
func friends_in_range(unit: Node2D, max_range: float) -> Array:
	var out: Array = []
	var r2 := max_range * max_range
	for u in units:
		if not is_instance_valid(u) or not u.alive or u.carried_by != null or u == unit:
			continue
		if u.faction_id == unit.faction_id and unit.position.distance_squared_to(u.position) <= r2:
			out.append(u)
	return out


## Мягкое разведение: подразделения не слипаются в одну точку.
func _separate_units() -> void:
	var active: Array = []
	for u in units:
		if is_instance_valid(u) and u.alive and u.carried_by == null:
			active.append(u)
	var n := active.size()
	for i in n:
		var a: Node2D = active[i]
		for j in range(i + 1, n):
			var b: Node2D = active[j]
			var min_d: float = a.radius + b.radius + 2.0
			var delta: Vector2 = b.position - a.position
			var d2 := delta.length_squared()
			if d2 >= min_d * min_d:
				continue
			var d := sqrt(d2)
			var dir := delta / d if d > 0.001 else Vector2.RIGHT.rotated(float(a.uid) * 2.4)
			var shift := dir * (min_d - d) * 0.25
			a.position = clamp_to_map(a.position - shift, a.radius)
			b.position = clamp_to_map(b.position + shift, b.radius)


func spawn_wreck(world_pos: Vector2, color: Color, radius: float) -> void:
	var w := WreckScript.new()
	w.color = color
	w.radius = radius
	w.lifetime = float(DataLoader.balance_value("combat", "wreck_lifetime", 25.0))
	w.position = world_pos
	markers_node.add_child(w)


func count_units(faction: String) -> int:
	var n := 0
	for u in units:
		if is_instance_valid(u) and u.alive and u.faction_id == faction:
			n += 1
	return n


func units_of(faction: String) -> Array:
	var out: Array = []
	for u in units:
		if is_instance_valid(u) and u.alive and u.faction_id == faction:
			out.append(u)
	return out


func find_nearest_enemy(unit: Node2D, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range * max_range
	for u in units:
		if not is_instance_valid(u) or not u.alive or u.carried_by != null:
			continue
		if u.faction_id == unit.faction_id:
			continue
		var d: float = unit.position.distance_squared_to(u.position)
		if d <= best_d:
			best_d = d
			best = u
	return best


func pick_player_unit(world_pos: Vector2, pad: float) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for u in units:
		if not is_instance_valid(u) or not u.alive or not u.is_player or u.carried_by != null:
			continue
		if u.contains_point(world_pos, pad):
			var d: float = u.position.distance_squared_to(world_pos)
			if d < best_d:
				best_d = d
				best = u
	return best


func units_in_rect(rect: Rect2, player_only: bool = true) -> Array:
	var out: Array = []
	for u in units:
		if not is_instance_valid(u) or not u.alive or u.carried_by != null:
			continue
		if player_only and not u.is_player:
			continue
		if rect.has_point(u.position):
			out.append(u)
	return out


func has_free_transport(faction: String) -> bool:
	for u in units:
		if is_instance_valid(u) and u.alive and u.faction_id == faction and u.capacity > 0 and u.free_seats() > 0:
			return true
	return false


func find_transport_near(pos: Vector2, faction: String, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist * max_dist
	for u in units:
		if not is_instance_valid(u) or not u.alive or u.faction_id != faction:
			continue
		if u.capacity <= 0 or u.free_seats() <= 0:
			continue
		var d: float = u.position.distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = u
	return best


func spawn_marker(world_pos: Vector2, color: Color) -> void:
	var m := OrderMarker.new()
	m.color = color
	m.position = world_pos
	markers_node.add_child(m)
