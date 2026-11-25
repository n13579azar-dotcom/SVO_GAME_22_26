extends Node
## Простейший ИИ стороны. Раз в think_interval секунд игрового времени:
##  - раненые подразделения в бою отходят на базу;
##  - при виде противника подразделения наступают на него;
##  - иначе занимают ближайшие чужие контрольные точки;
##  - транспорт подвозит пехоту и высаживает её у цели или при контакте.
## Приказы переотдаются только при заметном изменении задачи.

const RETREAT_HP_RATIO := 0.3
const REISSUE_DIST := 60.0

var battle: Node = null
var faction_id: String = ""
var home: Vector2 = Vector2.ZERO
var aggression: float = 0.6
var think_interval: float = 1.0
var _timer: float = 0.0


func setup(p_battle: Node, p_faction: String, side_data: Dictionary) -> void:
	battle = p_battle
	faction_id = p_faction
	var h: Array = side_data.get("home", [0, 0])
	home = Vector2(float(h[0]), float(h[1]))
	var profile: Dictionary = side_data.get("ai", {})
	aggression = float(profile.get("aggression", 0.6))
	think_interval = maxf(0.2, float(profile.get("think_interval", 1.0)))
	_timer = randf() * think_interval


func sim_step(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = think_interval
	_think()


func _think() -> void:
	var mine: Array = []
	for u in battle.units_of(faction_id):
		if u.carried_by == null:
			mine.append(u)
	if mine.is_empty():
		return

	var targets: Array = _target_points()
	var idx := 0
	for u in mine:
		if str(u.type_data.get("category", "")) == "vehicle" and u.capacity > 0:
			_think_transport(u, targets)
			continue
		var enemy: Node2D = battle.find_nearest_enemy(u, u.vision)
		if enemy != null:
			if u.hp < u.max_hp * RETREAT_HP_RATIO and aggression < 0.9:
				_assign(u, "retreat", home)
			else:
				_assign(u, "attack", enemy.position)
			continue
		if not targets.is_empty():
			var p: Node2D = targets[idx % targets.size()]
			idx += 1
			_assign(u, "capture", p.position)
		else:
			_hunt_or_hold(u)


func _target_points() -> Array:
	var out: Array = []
	for p in battle.points:
		if p.owner_id != faction_id:
			out.append(p)
	return out


func _hunt_or_hold(u: Node2D) -> void:
	if aggression >= 0.5:
		var nearest: Node2D = battle.find_nearest_enemy(u, 100000.0)
		if nearest != null:
			_assign(u, "attack", nearest.position)
			return
	_assign(u, "hold", u.position)


func _think_transport(t: Node2D, targets: Array) -> void:
	var enemy: Node2D = battle.find_nearest_enemy(t, t.vision + 60.0)
	if not t.passengers.is_empty():
		var near_goal := false
		for p in targets:
			if t.position.distance_to(p.position) < 260.0:
				near_goal = true
		if enemy != null or near_goal:
			t.order_unboard()
			t.ai_task = {"kind": "unloaded", "pos": t.position}
		elif not targets.is_empty():
			_assign(t, "capture", _nearest_point(t, targets).position)
		return

	# Пустой транспорт: поддержка ближайшей цели и подвоз пехоты.
	for u in battle.units_of(faction_id):
		if u.carried_by == null and bool(u.type_data.get("can_board", false)) and u.ai_task.get("kind", "") == "capture":
			if u.position.distance_to(t.position) < 160.0 and t.free_seats() > 0 \
					and u.position.distance_to(u.ai_task.get("pos", u.position)) > 700.0 and enemy == null:
				u.order_board(t)
				u.ai_task = {"kind": "board", "pos": t.position}
	if enemy != null:
		_assign(t, "attack", enemy.position)
	elif not targets.is_empty():
		_assign(t, "capture", _nearest_point(t, targets).position)


func _nearest_point(u: Node2D, points: Array) -> Node2D:
	var best: Node2D = points[0]
	var best_d := INF
	for p in points:
		var d: float = u.position.distance_squared_to(p.position)
		if d < best_d:
			best_d = d
			best = p
	return best


## Отдаёт приказ, только если задача изменилась.
func _assign(u: Node2D, kind: String, pos: Vector2) -> void:
	var cur: Dictionary = u.ai_task
	if str(cur.get("kind", "")) == kind and pos.distance_to(cur.get("pos", Vector2(-99999, -99999))) < REISSUE_DIST:
		return
	if str(cur.get("kind", "")) == "board" and is_instance_valid(u.board_target) and kind == "capture":
		return
	u.ai_task = {"kind": kind, "pos": pos}
	match kind:
		"retreat":
			u.order_move(battle.clamp_to_map(home, u.radius), true)
		"attack":
			u.order_attack_move(battle.clamp_to_map(pos, u.radius))
		"capture":
			u.order_attack_move(battle.clamp_to_map(pos + Vector2(randf_range(-50, 50), randf_range(-50, 50)), u.radius))
		"hold":
			u.order_hold()
