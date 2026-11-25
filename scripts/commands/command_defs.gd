extends RefCounted
## Описание команд подразделений (данные интерфейса и правила доступности).
## Чтобы добавить команду: добавьте запись в COMMANDS, id в ORDER,
## id в поле "actions" нужных типов в data/equipment/unit_types.json
## и обработку в command_executor.gd.

const COMMANDS := {
	"move": {"label": "Идти", "needs_target": true, "hint": "Коснитесь точки назначения"},
	"run": {"label": "Бег", "needs_target": true, "hint": "Бег: коснитесь точки (без стрельбы)"},
	"attack_move": {"label": "Атака", "needs_target": true, "hint": "Атака: коснитесь точки наступления"},
	"wait": {"label": "Ждать", "needs_target": false, "hint": ""},
	"board": {"label": "Посадка", "needs_target": true, "hint": "Коснитесь транспорта для посадки"},
	"unboard": {"label": "Высадка", "needs_target": false, "hint": ""},
	"fortify": {"label": "Окопаться", "needs_target": false, "hint": ""},
}

const ORDER := ["move", "run", "attack_move", "wait", "board", "unboard", "fortify"]


static func get_def(id: String) -> Dictionary:
	return COMMANDS.get(id, {"label": id, "needs_target": false, "hint": ""})


## Команды, доступные для всей выбранной группы (пересечение возможностей).
static func available_for(units: Array, battle: Node) -> Array:
	var result: Array = []
	if units.is_empty():
		return result
	for id in ORDER:
		var ok := true
		for u in units:
			if not (id in u.type_data.get("actions", [])):
				ok = false
				break
		if not ok:
			continue
		if id == "board" and not battle.has_free_transport(units[0].faction_id):
			continue
		if id == "unboard":
			var any_loaded := false
			for u in units:
				if not u.passengers.is_empty():
					any_loaded = true
					break
			if not any_loaded:
				continue
		result.append(id)
	return result
