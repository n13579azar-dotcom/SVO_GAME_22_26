extends Node2D
## Подразделение: движение, бой, посадка в транспорт и отрисовка условным знаком.
## Симуляция вызывается из battle.gd через sim_step(dt) — это позволяет
## ставить игру на паузу и ускорять время, не трогая Engine.time_scale.

signal died(unit: Node2D)

enum Mode { IDLE, MOVE, RUN, ATTACK_MOVE, BOARD }

const ARRIVE_DIST := 5.0
const BOARD_DIST := 34.0
const FORTIFY_TIME := 3.0
const FORTIFY_DEFENSE := 0.6
const FLASH_TIME := 0.15
const SCAN_INTERVAL := 0.3

var battle: Node = null
var uid: int = 0
var type_id: String = ""
var type_data: Dictionary = {}
var faction_id: String = ""
var faction_color: Color = Color.WHITE
var is_player: bool = false

var max_hp: float = 100.0
var hp: float = 100.0
var radius: float = 14.0
var speed: float = 50.0
var run_speed: float = 90.0
var accel: float = 5.0
var attack_dps: float = 5.0
var attack_range: float = 120.0
var vision: float = 250.0
var capacity: int = 0

var alive: bool = true
var selected: bool = false
var mode: int = Mode.IDLE
var destination: Vector2 = Vector2.ZERO
var velocity_vec: Vector2 = Vector2.ZERO
var facing: float = 0.0

var carried_by: Node2D = null
var passengers: Array = []
var board_target: Node2D = null

var holding: bool = false
var fortify_pending: bool = false
var fortify_timer: float = 0.0
var dug_in: bool = false

var target_enemy: Node2D = null
var _scan_timer: float = 0.0
var _flash_timer: float = 0.0
var _flash_to: Vector2 = Vector2.ZERO

## Служебные данные ИИ: {"kind": String, "pos": Vector2}
var ai_task: Dictionary = {}


func setup(p_battle: Node, p_type_data: Dictionary, p_faction: String, p_pos: Vector2, p_uid: int, p_is_player: bool) -> void:
	battle = p_battle
	type_data = p_type_data
	type_id = str(p_type_data.get("id", ""))
	faction_id = p_faction
	faction_color = DataLoader.get_faction_color(p_faction)
	is_player = p_is_player
	uid = p_uid
	position = p_pos
	destination = p_pos

	max_hp = float(p_type_data.get("max_hp", 100))
	hp = max_hp
	radius = float(p_type_data.get("radius", 14))
	speed = float(p_type_data.get("speed", 50))
	run_speed = float(p_type_data.get("run_speed", speed * 1.6))
	accel = float(p_type_data.get("accel", 5.0))
	attack_dps = float(p_type_data.get("attack", 5))
	attack_range = float(p_type_data.get("attack_range", 120))
	vision = float(p_type_data.get("vision", 250))
	capacity = int(p_type_data.get("capacity", 0))
	_scan_timer = randf() * SCAN_INTERVAL
	queue_redraw()


# ---------------------------------------------------------------- приказы

func order_move(pos: Vector2, run: bool = false) -> void:
	_begin_order()
	destination = pos
	mode = Mode.RUN if run else Mode.MOVE


func order_attack_move(pos: Vector2) -> void:
	_begin_order()
	destination = pos
	mode = Mode.ATTACK_MOVE


func order_hold() -> void:
	_begin_order()
	mode = Mode.IDLE
	holding = true


func order_fortify() -> void:
	_begin_order()
	mode = Mode.IDLE
	holding = true
	fortify_pending = true
	fortify_timer = 0.0


func order_board(transport: Node2D) -> void:
	_begin_order()
	board_target = transport
	destination = transport.position
	mode = Mode.BOARD


func order_unboard() -> void:
	unload_all()


func _begin_order() -> void:
	holding = false
	fortify_pending = false
	fortify_timer = 0.0
	dug_in = false
	board_target = null
	queue_redraw()


# ---------------------------------------------------------------- симуляция

func sim_step(dt: float) -> void:
	if not alive:
		return
	if carried_by != null:
		return
	_update_movement(dt)
	_update_fortify(dt)
	_update_combat(dt)
	_update_passengers()
	if _flash_timer > 0.0:
		_flash_timer -= dt
	if selected or _flash_timer > 0.0 or velocity_vec.length_squared() > 1.0:
		queue_redraw()


func _update_movement(dt: float) -> void:
	var desired := Vector2.ZERO
	var max_speed := speed

	match mode:
		Mode.MOVE, Mode.ATTACK_MOVE, Mode.RUN:
			if mode == Mode.RUN:
				max_speed = run_speed
			var engaged := mode == Mode.ATTACK_MOVE and _has_valid_target()
			var to := destination - position
			var dist := to.length()
			if dist <= ARRIVE_DIST:
				mode = Mode.IDLE
			elif not engaged:
				var s := minf(max_speed, dist * 3.0 + 8.0)
				desired = to / dist * s
		Mode.BOARD:
			if not is_instance_valid(board_target) or not board_target.alive:
				mode = Mode.IDLE
				board_target = null
			else:
				destination = board_target.position
				var to_t := destination - position
				var d := to_t.length()
				if d <= BOARD_DIST + board_target.radius:
					if board_target.can_take(self):
						board_target.take_passenger(self)
						return
					mode = Mode.IDLE
					board_target = null
				else:
					max_speed = run_speed
					desired = to_t / d * max_speed

	velocity_vec = velocity_vec.lerp(desired, clampf(accel * dt, 0.0, 1.0))
	if velocity_vec.length_squared() < 0.04 and desired == Vector2.ZERO:
		velocity_vec = Vector2.ZERO
	if velocity_vec != Vector2.ZERO:
		position += velocity_vec * dt
		facing = lerp_angle(facing, velocity_vec.angle(), clampf(10.0 * dt, 0.0, 1.0))
		if battle != null:
			position = battle.clamp_to_map(position, radius)


func _update_fortify(dt: float) -> void:
	if fortify_pending and velocity_vec == Vector2.ZERO:
		fortify_timer += dt
		if fortify_timer >= FORTIFY_TIME:
			fortify_pending = false
			dug_in = true
			queue_redraw()


func _has_valid_target() -> bool:
	return is_instance_valid(target_enemy) and target_enemy.alive and target_enemy.carried_by == null \
		and position.distance_to(target_enemy.position) <= attack_range


func _update_combat(dt: float) -> void:
	if mode == Mode.RUN or mode == Mode.BOARD:
		target_enemy = null
		return
	_scan_timer -= dt
	if _scan_timer <= 0.0 or not _has_valid_target():
		if _scan_timer <= 0.0:
			_scan_timer = SCAN_INTERVAL
			target_enemy = battle.find_nearest_enemy(self, attack_range) if battle != null else null
	if _has_valid_target():
		target_enemy.take_damage(attack_dps * dt, self)
		_flash_timer = FLASH_TIME
		_flash_to = target_enemy.position - position


func _update_passengers() -> void:
	for p in passengers:
		if is_instance_valid(p):
			p.position = position


func take_damage(amount: float, _source: Node2D = null) -> void:
	if not alive:
		return
	var mult := FORTIFY_DEFENSE if dug_in else 1.0
	hp -= amount * mult
	queue_redraw()
	if hp <= 0.0:
		die()


func die() -> void:
	if not alive:
		return
	alive = false
	selected = false
	unload_all(true)
	if carried_by != null and is_instance_valid(carried_by):
		carried_by.passengers.erase(self)
	carried_by = null
	died.emit(self)
	queue_free()


# ---------------------------------------------------------------- транспорт

func can_take(u: Node2D) -> bool:
	return alive and capacity > 0 and passengers.size() < capacity \
		and u.faction_id == faction_id and bool(u.type_data.get("can_board", false))


func free_seats() -> int:
	return capacity - passengers.size()


func take_passenger(u: Node2D) -> void:
	passengers.append(u)
	u.carried_by = self
	u.visible = false
	u.selected = false
	u.mode = Mode.IDLE
	u.velocity_vec = Vector2.ZERO
	u.board_target = null
	u.position = position
	queue_redraw()


func unload_all(wounded: bool = false) -> void:
	var n := passengers.size()
	for i in n:
		var p: Node2D = passengers[i]
		if not is_instance_valid(p):
			continue
		var ang := facing + PI + TAU * float(i) / maxf(n, 1.0) * 0.6
		p.carried_by = null
		p.visible = true
		p.position = position + Vector2.from_angle(ang) * (radius + p.radius + 14.0)
		p.mode = Mode.IDLE
		p.destination = p.position
		if wounded:
			p.take_damage(p.max_hp * 0.3, self)
		p.queue_redraw()
	passengers.clear()
	queue_redraw()


# ---------------------------------------------------------------- выбор

func contains_point(world_pos: Vector2, pad: float = 0.0) -> bool:
	return position.distance_to(world_pos) <= radius + pad


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


# ---------------------------------------------------------------- отрисовка

func _draw() -> void:
	if not alive:
		return
	var col := faction_color
	var shape := str(type_data.get("shape", "circle"))

	if selected:
		draw_arc(Vector2.ZERO, radius + 7.0, 0.0, TAU, 32, Color(1, 1, 0.3), 3.0)
		if mode != Mode.IDLE:
			var local_dest := destination - position
			draw_dashed_line(Vector2.ZERO, local_dest, Color(1, 1, 1, 0.55), 2.0, 10.0)
			draw_circle(local_dest, 5.0, Color(1, 1, 1, 0.7))

	if _flash_timer > 0.0:
		draw_line(Vector2.ZERO, _flash_to, Color(1.0, 0.85, 0.3, 0.9), 2.0)

	if shape == "square":
		var r := Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0))
		draw_rect(r, col)
		draw_rect(r, Color(0, 0, 0, 0.8), false, 2.0)
	else:
		draw_circle(Vector2.ZERO, radius, col)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(0, 0, 0, 0.8), 2.0)

	# Направление движения
	var tip := Vector2.from_angle(facing) * (radius + 6.0)
	draw_line(Vector2.ZERO, tip, Color(0, 0, 0, 0.8), 3.0)

	# Условный символ
	var font := ThemeDB.fallback_font
	var sym := str(type_data.get("symbol", "?"))
	draw_string(font, Vector2(-radius, 6.0), sym, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 16, Color.WHITE)

	# Полоса здоровья
	var w := radius * 2.0
	var ratio := clampf(hp / max_hp, 0.0, 1.0)
	var y := -radius - 10.0
	draw_rect(Rect2(Vector2(-radius, y), Vector2(w, 4.0)), Color(0, 0, 0, 0.6))
	var hp_col := Color(0.3, 0.9, 0.3).lerp(Color(0.95, 0.2, 0.2), 1.0 - ratio)
	draw_rect(Rect2(Vector2(-radius, y), Vector2(w * ratio, 4.0)), hp_col)

	# Десант и окоп
	if capacity > 0:
		draw_string(font, Vector2(-radius, radius + 14.0), "%d/%d" % [passengers.size(), capacity], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 13, Color.WHITE)
	if dug_in:
		draw_rect(Rect2(Vector2(-radius - 4.0, -radius - 4.0), Vector2(radius * 2.0 + 8.0, radius * 2.0 + 8.0)), Color(0.9, 0.8, 0.5, 0.8), false, 2.0)
