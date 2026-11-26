extends RefCounted
## Рельеф боевой карты для игровой логики (скорость и укрытие).
## Строится из тех же features, которые рисует battle_map.gd, поэтому
## картинка и правила не расходятся.

# Приоритет: вода > город > лес > дорога > открытая местность.
const RECT_PRIORITY := ["water", "town", "forest"]

var _rects: Array = []
var _roads: Array = []


func setup(features: Array) -> void:
	_rects.clear()
	_roads.clear()
	for kind in RECT_PRIORITY:
		for f in features:
			if str(f.get("type", "")) == kind:
				var a: Array = f.get("rect", [0, 0, 0, 0])
				_rects.append({"kind": kind, "rect": Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))})
	for f in features:
		if str(f.get("type", "")) == "road":
			var pts: Array = f.get("points", [])
			var half := float(f.get("width", 30)) * 0.5
			for i in range(pts.size() - 1):
				_roads.append({
					"a": Vector2(float(pts[i][0]), float(pts[i][1])),
					"b": Vector2(float(pts[i + 1][0]), float(pts[i + 1][1])),
					"half": half,
				})


func kind_at(p: Vector2) -> String:
	for r in _rects:
		if r["rect"].has_point(p):
			return r["kind"]
	for road in _roads:
		var closest := Geometry2D.get_closest_point_to_segment(p, road["a"], road["b"])
		if closest.distance_squared_to(p) <= road["half"] * road["half"]:
			return "road"
	return "open"
