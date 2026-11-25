extends Node2D
## Контрольная точка (цель сценария). Захватывается, когда в зоне находится
## только одна сторона достаточно долго.

signal owner_changed(point: Node2D, old_owner: String, new_owner: String)

var point_id: String = ""
var point_name: String = ""
var radius: float = 120.0
var owner_id: String = ""
var capture_time: float = 12.0
var capturer: String = ""
var progress: float = 0.0


func setup(data: Dictionary) -> void:
	point_id = str(data.get("id", ""))
	point_name = str(data.get("name", ""))
	var p: Array = data.get("pos", [0, 0])
	position = Vector2(float(p[0]), float(p[1]))
	radius = float(data.get("radius", 120))
	owner_id = str(data.get("owner", ""))
	capture_time = maxf(1.0, float(data.get("capture_time", 12)))
	queue_redraw()


func sim_step(dt: float, units: Array) -> void:
	var present: Dictionary = {}
	for u in units:
		if is_instance_valid(u) and u.alive and u.carried_by == null:
			if u.position.distance_squared_to(position) <= radius * radius:
				present[u.faction_id] = true

	var old_progress := progress
	if present.size() == 1:
		var f: String = present.keys()[0]
		if f == owner_id:
			progress = move_toward(progress, 0.0, dt / capture_time)
		else:
			if capturer != f:
				capturer = f
				progress = 0.0
			progress += dt / capture_time
			if progress >= 1.0:
				var old := owner_id
				owner_id = f
				progress = 0.0
				capturer = ""
				owner_changed.emit(self, old, owner_id)
				queue_redraw()
	elif present.is_empty():
		progress = move_toward(progress, 0.0, dt / capture_time * 0.5)
	if absf(progress - old_progress) > 0.0001:
		queue_redraw()


func _draw() -> void:
	var col := DataLoader.get_faction_color(owner_id) if owner_id != "" else Color(0.85, 0.85, 0.85)
	draw_circle(Vector2.ZERO, radius, Color(col.r, col.g, col.b, 0.16))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.9), 4.0)
	if progress > 0.0 and capturer != "":
		var cc := DataLoader.get_faction_color(capturer)
		draw_arc(Vector2.ZERO, radius - 10.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, cc, 8.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-radius, 8.0), point_name, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 22, Color.WHITE)
