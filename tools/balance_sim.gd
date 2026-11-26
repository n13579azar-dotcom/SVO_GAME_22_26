extends Node
## Стенд баланса (только для разработки, в APK не попадает).
## Запускает бои ИИ против ИИ без графики и печатает статистику.
##
## Запуск:
##   godot --headless --path . res://tools/balance_sim.tscn -- scenario=test_01 runs=20 step=0.1
## Параметры (все необязательны): scenario=<id|all>, runs=<число>, step=<сек симуляции>, strict=1
## При strict=1 процесс завершается с кодом 1, если часть боёв не завершилась победой или поражением.

const EnemyAI := preload("res://scripts/ai/enemy_ai.gd")
const BattleScene := preload("res://scenes/battle/battle.tscn")
const MAX_SIM_TIME := 3600.0

var _runs: int = 10
var _step: float = 0.1
var _scenario: String = "all"
var _strict: bool = false


func _ready() -> void:
	_parse_args()
	var ids: Array = DataLoader.scenario_order if _scenario == "all" else [_scenario]
	var failed := false
	for sid in ids:
		if DataLoader.get_scenario(str(sid)).is_empty():
			push_error("balance_sim: неизвестный сценарий %s" % sid)
			failed = true
			continue
		var ok: bool = await _run_scenario(str(sid))
		failed = failed or not ok
	get_tree().quit(1 if (failed and _strict) else 0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := str(arg).split("=", false, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"runs":
				_runs = maxi(1, int(kv[1]))
			"step":
				_step = clampf(float(kv[1]), 0.02, 0.5)
			"scenario":
				_scenario = kv[1]
			"strict":
				_strict = kv[1] == "1"


func _run_scenario(sid: String) -> bool:
	var scn: Dictionary = DataLoader.get_scenario(sid)
	var sides: Array = scn.get("sides", [])
	var wins: Dictionary = {"draw": 0}
	var survivors: Dictionary = {}
	for s in sides:
		wins[str(s["faction"])] = 0
		survivors[str(s["faction"])] = 0.0
	var total_time := 0.0
	var min_time := INF
	var max_time := 0.0
	var timeouts := 0
	var reasons: Dictionary = {}
	var all_finished := true
	var limit := float(scn.get("time_limit", 0))

	for i in _runs:
		seed(1000 + i)
		GameState.current_scenario_id = sid
		GameState.current_side = str(sides[0]["faction"])
		var battle: Node2D = BattleScene.instantiate()
		add_child(battle)
		# Сохранение прогресса игрока не трогаем: итог матча обрабатывает стенд.
		battle.rules.finished.disconnect(battle._on_match_finished)
		battle.clock.set_paused(true)
		for s in sides:
			if str(s["faction"]) == battle.player_faction:
				var ai := EnemyAI.new()
				battle.add_child(ai)
				ai.setup(battle, battle.player_faction, s)
				battle.ai_controllers.append(ai)

		var box: Dictionary = {}
		battle.rules.finished.connect(func(r: Dictionary): box["r"] = r)
		while not box.has("r") and battle.clock.elapsed < MAX_SIM_TIME:
			battle._sim_step(_step)

		var t: float = battle.clock.elapsed
		if box.has("r"):
			var winner := str(box["r"].get("winner", ""))
			wins[winner if winner != "" else "draw"] += 1
			var key := "%s: %s" % [winner if winner != "" else "ничья", str(box["r"].get("reason", ""))]
			reasons[key] = int(reasons.get(key, 0)) + 1
			if winner == "" and limit > 0.0 and t >= limit:
				timeouts += 1
			elif winner == "":
				pass
			t = float(box["r"].get("time", t))
		else:
			all_finished = false
			wins["draw"] += 1
		for s in sides:
			survivors[str(s["faction"])] += battle.count_units(str(s["faction"]))
		total_time += t
		min_time = minf(min_time, t)
		max_time = maxf(max_time, t)
		remove_child(battle)
		battle.free()
		await get_tree().process_frame

	print("=== %s (%s), боёв: %d, шаг %.2f с ===" % [sid, str(scn.get("name", "")), _runs, _step])
	for s in sides:
		var f := str(s["faction"])
		print("  %-8s роль=%-9s побед: %2d (%3d%%)  выжило в среднем: %.1f" % [
			f, str(s.get("role", "")), wins[f], int(round(100.0 * wins[f] / _runs)), survivors[f] / _runs])
	print("  ничьих: %d (по таймеру: %d)" % [wins["draw"], timeouts])
	for k in reasons.keys():
		print("    %s — %d" % [k, reasons[k]])
	print("  длительность: средняя %s, мин %s, макс %s (лимит %s)" % [
		_fmt(total_time / _runs), _fmt(min_time), _fmt(max_time), _fmt(limit)])
	return all_finished


func _fmt(sec: float) -> String:
	if sec == INF:
		return "-"
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]
