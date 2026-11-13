extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var level: Node2D = load("res://scenes/levels/l_relay_puzzle.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://docs/previews")
	root.get_texture().get_image().save_png("res://docs/previews/l-puzzle-start.png")
	level.hud.overlay.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("res://docs/previews/l-puzzle.png")
	var floor_pixel := image.get_pixel(320, 540)
	var player_pixel := image.get_pixel(656, 490)
	var closed_gate := image.get_pixel(990, 540)
	var passed: bool = floor_pixel.r > 0.5 and player_pixel.r > 0.5 and closed_gate.r < 0.1
	print("PASS" if passed else "FAIL", "  Full map and player visible; closed right-wall gate stays disconnected")
	quit(0 if passed else 1)
