extends RefCounted
## Список выбранных подразделений.

signal changed(units: Array)

var units: Array = []


func is_empty() -> bool:
	return units.is_empty()


func has(u: Node2D) -> bool:
	return units.has(u)


func set_units(list: Array) -> void:
	for u in units:
		if is_instance_valid(u) and not list.has(u):
			u.set_selected(false)
	units = list.duplicate()
	for u in units:
		u.set_selected(true)
	changed.emit(units)


func add_many(list: Array) -> void:
	var merged := units.duplicate()
	for u in list:
		if not merged.has(u):
			merged.append(u)
	set_units(merged)


func toggle(u: Node2D) -> void:
	var merged := units.duplicate()
	if merged.has(u):
		merged.erase(u)
	else:
		merged.append(u)
	set_units(merged)


func clear() -> void:
	if units.is_empty():
		return
	set_units([])


## Убирает уничтоженные и посаженные в транспорт подразделения.
func prune() -> void:
	var keep: Array = []
	for u in units:
		if is_instance_valid(u) and u.alive and u.carried_by == null:
			keep.append(u)
	if keep.size() != units.size():
		units = keep
		changed.emit(units)


func centroid() -> Vector2:
	if units.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for u in units:
		sum += u.position
	return sum / float(units.size())
