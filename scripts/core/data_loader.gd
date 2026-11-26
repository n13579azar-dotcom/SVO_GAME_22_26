extends Node
## Автозагрузка DataLoader.
## Читает все игровые данные (фракции, типы подразделений, сценарии, территории)
## из JSON-файлов в папке data. Список файлов берётся из data/manifest.json,
## поэтому новый сценарий добавляется без изменения кода.

const MANIFEST_PATH := "res://data/manifest.json"

var factions: Dictionary = {}
var unit_types: Dictionary = {}
var scenarios: Dictionary = {}
var scenario_order: Array = []
var territories: Dictionary = {}
var territory_order: Array = []
var territory_map_size: Vector2 = Vector2(1000, 600)
var balance: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	balance.clear()
	factions.clear()
	unit_types.clear()
	scenarios.clear()
	scenario_order.clear()
	territories.clear()
	territory_order.clear()

	var manifest: Variant = _read_json(MANIFEST_PATH)
	if typeof(manifest) != TYPE_DICTIONARY:
		push_error("DataLoader: не удалось прочитать manifest: %s" % MANIFEST_PATH)
		return

	var b_data: Variant = _read_json(str(manifest.get("balance", "")))
	if typeof(b_data) == TYPE_DICTIONARY:
		balance = b_data

	var f_data: Variant = _read_json(str(manifest.get("factions", "")))
	if typeof(f_data) == TYPE_DICTIONARY:
		for f in f_data.get("factions", []):
			factions[str(f.get("id", ""))] = f

	var u_data: Variant = _read_json(str(manifest.get("unit_types", "")))
	if typeof(u_data) == TYPE_DICTIONARY:
		for u in u_data.get("unit_types", []):
			unit_types[str(u.get("id", ""))] = u

	var t_data: Variant = _read_json(str(manifest.get("territories", "")))
	if typeof(t_data) == TYPE_DICTIONARY:
		var ms: Array = t_data.get("map_size", [1000, 600])
		territory_map_size = Vector2(float(ms[0]), float(ms[1]))
		for t in t_data.get("territories", []):
			var tid := str(t.get("id", ""))
			territories[tid] = t
			territory_order.append(tid)

	for path in manifest.get("scenarios", []):
		var s: Variant = _read_json(str(path))
		if typeof(s) == TYPE_DICTIONARY:
			var sid := str(s.get("id", ""))
			scenarios[sid] = s
			scenario_order.append(sid)


## Значение из data/balance.json: balance_value("combat", "damage_scale", 1.0).
func balance_value(section: String, key: String, default_value: Variant) -> Variant:
	var s: Variant = balance.get(section, {})
	if typeof(s) == TYPE_DICTIONARY and s.has(key):
		return s[key]
	return default_value


## Параметры рельефа (скорость и укрытие) из data/balance.json.
func terrain_params(kind: String) -> Dictionary:
	var t: Variant = balance.get("terrain", {})
	if typeof(t) == TYPE_DICTIONARY:
		if t.has(kind):
			return t[kind]
		if t.has("open"):
			return t["open"]
	return {"infantry_speed": 1.0, "vehicle_speed": 1.0, "defense": 1.0}


func get_faction(id: String) -> Dictionary:
	return factions.get(id, {})


func get_faction_name(id: String) -> String:
	return str(get_faction(id).get("name", id))


func get_faction_color(id: String) -> Color:
	var f := get_faction(id)
	if f.is_empty():
		return Color(0.6, 0.6, 0.6)
	return Color.html(str(f.get("color", "#9ca3af")))


func get_unit_type(id: String) -> Dictionary:
	return unit_types.get(id, {})


func get_scenario(id: String) -> Dictionary:
	return scenarios.get(id, {})


func get_territory(id: String) -> Dictionary:
	return territories.get(id, {})


func _read_json(path: String) -> Variant:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("DataLoader: файл не найден: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: не удалось открыть: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("DataLoader: ошибка JSON в файле: %s" % path)
	return parsed
