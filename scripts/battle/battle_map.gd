extends Node2D
## Тестовая 2D-карта сверху. Рисуется целиком из данных сценария
## (фон, сетка, дороги, леса, вода, строения). Рельеф в версии 0.1 только визуальный.

var map_size: Vector2 = Vector2(3200, 2000)
var background: Color = Color("#4b6b3a")
var features: Array = []


func setup(map_data: Dictionary) -> void:
	var sz: Array = map_data.get("size", [3200, 2000])
	map_size = Vector2(float(sz[0]), float(sz[1]))
	background = Color.html(str(map_data.get("background", "#4b6b3a")))
	features = map_data.get("features", [])
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, map_size), background)

	var grid := Color(1, 1, 1, 0.05)
	var x := 0.0
	while x <= map_size.x:
		draw_line(Vector2(x, 0), Vector2(x, map_size.y), grid, 1.0)
		x += 200.0
	var y := 0.0
	while y <= map_size.y:
		draw_line(Vector2(0, y), Vector2(map_size.x, y), grid, 1.0)
		y += 200.0

	# Сначала вода и леса, затем дороги и строения.
	for f in features:
		match str(f.get("type", "")):
			"water":
				var r := _rect(f)
				draw_rect(r, Color("#3b6ea5"))
				draw_rect(r, Color("#2a4f7a"), false, 3.0)
			"forest":
				var r2 := _rect(f)
				draw_rect(r2, Color(0.12, 0.30, 0.14, 0.85))
				_draw_trees(r2)
	for f in features:
		if str(f.get("type", "")) == "road":
			var pts := PackedVector2Array()
			for p in f.get("points", []):
				pts.append(Vector2(float(p[0]), float(p[1])))
			if pts.size() >= 2:
				draw_polyline(pts, Color("#b8a77a"), float(f.get("width", 30)))
	for f in features:
		if str(f.get("type", "")) == "town":
			var r3 := _rect(f)
			draw_rect(r3, Color("#6b7280"))
			draw_rect(r3, Color("#374151"), false, 3.0)

	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.8, 0.15, 0.15, 0.9), false, 6.0)


func _rect(f: Dictionary) -> Rect2:
	var a: Array = f.get("rect", [0, 0, 0, 0])
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


func _draw_trees(r: Rect2) -> void:
	var step := 40.0
	var yy := r.position.y + step * 0.5
	while yy < r.end.y:
		var xx := r.position.x + step * 0.5
		while xx < r.end.x:
			draw_circle(Vector2(xx, yy), 13.0, Color(0.08, 0.22, 0.10, 0.9))
			xx += step
		yy += step
