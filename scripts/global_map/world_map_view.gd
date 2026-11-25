extends Control
## Отображение глобальной карты: территории рисуются по данным
## data/global_map/territories.json и окрашиваются по владельцу из GameState.

signal territory_selected(territory_id: String)

var selected_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameState.territory_changed.connect(func(_id: String): queue_redraw())
	resized.connect(queue_redraw)


func select(id: String) -> void:
	selected_id = id
	queue_redraw()


func _scale() -> float:
	var ms := DataLoader.territory_map_size
	return minf(size.x / ms.x, size.y / ms.y)


func _offset(s: float) -> Vector2:
	return (size - DataLoader.territory_map_size * s) * 0.5


func _polygon(t: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in t.get("polygon", []):
		pts.append(Vector2(float(p[0]), float(p[1])))
	return pts


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var s := _scale()
			var map_pos := (mb.position - _offset(s)) / s
			for id in DataLoader.territory_order:
				var poly := _polygon(DataLoader.get_territory(id))
				if poly.size() >= 3 and Geometry2D.is_point_in_polygon(map_pos, poly):
					selected_id = id
					queue_redraw()
					territory_selected.emit(id)
					return


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0f172a"))
	var s := _scale()
	var off := _offset(s)
	var font := ThemeDB.fallback_font

	for id in DataLoader.territory_order:
		var t := DataLoader.get_territory(id)
		var poly := _polygon(t)
		if poly.size() < 3:
			continue
		var pts := PackedVector2Array()
		var center := Vector2.ZERO
		for p in poly:
			var sp := p * s + off
			pts.append(sp)
			center += sp
		center /= float(pts.size())

		var st := GameState.get_territory_state(id)
		var owner_id := str(st.get("owner", "neutral"))
		var control := str(st.get("control", "neutral"))
		var col := DataLoader.get_faction_color(owner_id)
		col.a = 0.8 if control == "controlled" else 0.45
		draw_colored_polygon(pts, col)

		var closed := pts.duplicate()
		closed.append(pts[0])
		if id == selected_id:
			draw_polyline(closed, Color.WHITE, 4.0)
		elif control == "contested":
			draw_polyline(closed, Color("#facc15"), 3.0)
		else:
			draw_polyline(closed, Color(0, 0, 0, 0.7), 2.0)

		var label := str(t.get("name", id))
		draw_string(font, center + Vector2(-110, 6), label, HORIZONTAL_ALIGNMENT_CENTER, 220, 18, Color.WHITE)
		if not t.get("scenarios", []).is_empty():
			draw_circle(center + Vector2(0, -18), 6.0, Color("#facc15"))
