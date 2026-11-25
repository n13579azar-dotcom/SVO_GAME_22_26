extends RefCounted
## Исполнитель команд: превращает выбранную команду и точку в приказы подразделениям.
## Используется и игроком, и ИИ-логикой (через методы order_* подразделения).

const FORMATION_SPACING := 46.0


## Возвращает true, если команда принята.
static func execute(cmd: String, units: Array, target: Vector2, battle: Node) -> bool:
	var group: Array = []
	for u in units:
		if is_instance_valid(u) and u.alive and u.carried_by == null and (cmd in u.type_data.get("actions", [])):
			group.append(u)
	if group.is_empty():
		return false

	match cmd:
		"move":
			_group_move(group, target, battle, false)
			return true
		"run":
			_group_move(group, target, battle, true)
			return true
		"attack_move":
			_group_attack(group, target, battle)
			return true
		"wait":
			for u in group:
				u.order_hold()
			return true
		"fortify":
			for u in group:
				u.order_fortify()
			return true
		"unboard":
			for u in group:
				u.order_unboard()
			return true
		"board":
			return _board(group, target, battle)
	return false


static func formation_offsets(count: int) -> Array:
	var offsets: Array = []
	var cols := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(cols)))
	for i in count:
		var r := i / cols
		var c := i % cols
		offsets.append(Vector2(
			(float(c) - float(cols - 1) * 0.5) * FORMATION_SPACING,
			(float(r) - float(rows - 1) * 0.5) * FORMATION_SPACING))
	return offsets


static func _group_move(group: Array, target: Vector2, battle: Node, run: bool) -> void:
	var offs := formation_offsets(group.size())
	for i in group.size():
		group[i].order_move(battle.clamp_to_map(target + offs[i], group[i].radius), run)


static func _group_attack(group: Array, target: Vector2, battle: Node) -> void:
	var offs := formation_offsets(group.size())
	for i in group.size():
		group[i].order_attack_move(battle.clamp_to_map(target + offs[i], group[i].radius))


static func _board(group: Array, target: Vector2, battle: Node) -> bool:
	var transport: Node2D = battle.find_transport_near(target, group[0].faction_id, 110.0)
	if transport == null:
		return false
	var candidates: Array = []
	for u in group:
		if transport.can_take(u):
			candidates.append(u)
	candidates.sort_custom(func(a, b): return a.position.distance_squared_to(transport.position) < b.position.distance_squared_to(transport.position))
	var seats: int = transport.free_seats()
	var assigned := 0
	for u in candidates:
		if assigned >= seats:
			break
		u.order_board(transport)
		assigned += 1
	return assigned > 0
