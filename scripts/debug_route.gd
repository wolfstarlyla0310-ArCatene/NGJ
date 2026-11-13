extends Node2D

func _draw() -> void:
	for x in range(-384, 2945, 64):
		draw_line(Vector2(x, 64), Vector2(x, 768), Color(1, 1, 1, 0.06))
	for y in range(64, 769, 64):
		draw_line(Vector2(-384, y), Vector2(2944, y), Color(1, 1, 1, 0.06))
	draw_dashed_line(Vector2(640, 512), Vector2(1536, 512), Color(1, 1, 1, 0.35), 1.0, 12.0)
	draw_line(Vector2(2016, 240), Vector2(2016, 448), Color.WHITE, 2.0)
