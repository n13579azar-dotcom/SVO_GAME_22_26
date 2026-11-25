extends Node
## Условия завершения матча. Для каждой стороны в данных сценария заданы
## win_conditions ("eliminate_enemy", "control_all_points") и timeout_result.
## Итог выдаётся сигналом finished с точки зрения игрока.

signal finished(result: Dictionary)

const CHECK_INTERVAL := 0.5

var battle: Node = null
var scenario: Dictionary = {}
var player_faction: String = ""
var time_limit: float = 0.0
var _check_timer: float = 0.0
var _done: bool = false


func setup(p_battle: Node, p_scenario: Dictionary, p_player: String) -> void:
	battle = p_battle
	scenario = p_scenario
	player_faction = p_player
	time_limit = float(p_scenario.get("time_limit", 0))


func get_time_left(elapsed: float) -> float:
	if time_limit <= 0.0:
		return -1.0
	return maxf(0.0, time_limit - elapsed)


func sim_step(dt: float, elapsed: float) -> void:
	if _done:
		return
	_check_timer -= dt
	if _check_timer > 0.0 and not (time_limit > 0.0 and elapsed >= time_limit):
		return
	_check_timer = CHECK_INTERVAL
	_evaluate(elapsed)


func _evaluate(elapsed: float) -> void:
	var sides: Array = scenario.get("sides", [])
	var winners: Array = []
	var reason := ""

	for side in sides:
		var fid := str(side.get("faction", ""))
		var conds: Array = side.get("win_conditions", [])
		if "eliminate_enemy" in conds and _enemies_dead(fid):
			winners.append(fid)
			reason = "Силы противника уничтожены"
		elif "control_all_points" in conds and _controls_all(fid):
			winners.append(fid)
			reason = "Все контрольные точки под контролем"

	# Обе стороны потеряли все подразделения — ничья.
	var alive_sides := 0
	for side in sides:
		if battle.count_units(str(side.get("faction", ""))) > 0:
			alive_sides += 1
	if alive_sides == 0:
		_finish("draw", "", "Все подразделения уничтожены", elapsed)
		return

	if winners.size() == 1:
		_finish_for_winner(winners[0], reason, elapsed)
		return
	if winners.size() > 1:
		_finish("draw", "", "Ничья", elapsed)
		return

	if time_limit > 0.0 and elapsed >= time_limit:
		var timeout_winners: Array = []
		for side in sides:
			if str(side.get("timeout_result", "defeat")) == "victory":
				timeout_winners.append(str(side.get("faction", "")))
		if timeout_winners.size() == 1:
			_finish_for_winner(timeout_winners[0], "Время матча истекло", elapsed)
		else:
			_finish("draw", "", "Время матча истекло", elapsed)


func _finish_for_winner(winner: String, reason: String, elapsed: float) -> void:
	var outcome := "victory" if winner == player_faction else "defeat"
	_finish(outcome, winner, reason, elapsed)


func _finish(outcome: String, winner: String, reason: String, elapsed: float) -> void:
	if _done:
		return
	_done = true
	finished.emit({"outcome": outcome, "winner": winner, "reason": reason, "time": elapsed})


func _enemies_dead(faction: String) -> bool:
	for side in scenario.get("sides", []):
		var other := str(side.get("faction", ""))
		if other != faction and battle.count_units(other) > 0:
			return false
	return true


func _controls_all(faction: String) -> bool:
	if battle.points.is_empty():
		return false
	for p in battle.points:
		if p.owner_id != faction:
			return false
	return true
