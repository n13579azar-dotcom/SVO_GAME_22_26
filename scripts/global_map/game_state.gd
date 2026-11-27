extends Node
## Автозагрузка GameState.
## Хранит состояние глобальной карты (владельцы территорий), результаты
## сценариев и выбор игрока. Сохраняет и загружает прогресс в user://.

signal territory_changed(territory_id: String)

const SAVE_PATH := "user://svo_save.json"
const SAVE_VERSION := 1

const SCENE_MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const SCENE_WORLD_MAP := "res://scenes/world_map/world_map.tscn"
const SCENE_BATTLE := "res://scenes/battle/battle.tscn"

## territory_id -> {"owner": String, "control": String}
var territories: Dictionary = {}
## scenario_id -> {"outcome": String, "side": String, "time": float, "unix": int}
var results: Dictionary = {}

## Положение камеры глобальной карты (сохраняется между экранами в рамках запуска)
var map_camera: Dictionary = {}
## Последняя выбранная/сыгранная территория: карта вернётся к ней после боя
var last_territory_id: String = ""
## Последнее выбранное место сценариев (для возврата на карту после боя)
var last_place_id: String = ""
## Выбранный фильтр года на карте ("" — все)
var map_filter: String = ""

var current_scenario_id: String = ""
var current_side: String = ""


func _ready() -> void:
	_reset_territories()
	load_game()


func _reset_territories() -> void:
	territories.clear()
	for tid in DataLoader.territory_order:
		var t: Dictionary = DataLoader.get_territory(tid)
		territories[tid] = {
			"owner": str(t.get("owner", "neutral")),
			"control": str(t.get("control", "neutral")),
		}


func reset_progress() -> void:
	_reset_territories()
	results.clear()
	save_game()
	for tid in territories.keys():
		territory_changed.emit(tid)


func get_territory_state(id: String) -> Dictionary:
	return territories.get(id, {"owner": "neutral", "control": "neutral"})


func get_result(scenario_id: String) -> Dictionary:
	return results.get(scenario_id, {})


func change_scene(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("GameState: сцена не найдена: %s" % path)
		return
	get_tree().change_scene_to_file(path)


func start_scenario(scenario_id: String, side: String) -> void:
	if DataLoader.get_scenario(scenario_id).is_empty():
		push_error("GameState: неизвестный сценарий: %s" % scenario_id)
		return
	current_scenario_id = scenario_id
	current_side = side
	last_place_id = DataLoader.place_of_event(scenario_id)
	change_scene(SCENE_BATTLE)


## Применяет итог матча к глобальной карте и сохраняет прогресс.
func finish_scenario(scenario_id: String, side: String, result: Dictionary) -> void:
	var outcome := str(result.get("outcome", "draw"))

	# Итог боя НЕ перекрашивает области: вымышленный контроль не должен выглядеть как исторический факт.
	# Прогресс игрока хранится в results и показывается на маркере места сценария.
	results[scenario_id] = {
		"outcome": outcome,
		"side": side,
		"time": float(result.get("time", 0.0)),
		"unix": int(Time.get_unix_time_from_system()),
	}
	save_game()


func _enemy_of(scn: Dictionary, side: String) -> String:
	for s in scn.get("sides", []):
		if str(s.get("faction", "")) != side:
			return str(s.get("faction", "neutral"))
	return "neutral"


func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"territories": territories,
		"results": results,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameState: не удалось сохранить прогресс")
		return
	file.store_string(JSON.stringify(data, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GameState: файл сохранения повреждён, используются значения по умолчанию")
		return
	var saved_r: Variant = parsed.get("results", {})
	if typeof(saved_r) == TYPE_DICTIONARY:
		results = saved_r
