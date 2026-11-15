extends SceneTree
## 用实际画面可见性与播放器验证音效节点，避免只检查脚本是否能解析。

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value:
		print("PASS  ", message)
	else:
		failures.append(message)
		push_error("FAIL  " + message)

func rendered_frames(count: int = 5) -> void:
	for _i in count:
		await process_frame
	await RenderingServer.frame_post_draw

func _run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	var camera := Camera2D.new()
	fixture.add_child(camera)
	var animal: Animal = load("res://scenes/actors/animal.tscn").instantiate()
	animal.gravity = 0.0
	animal.set_physics_process(false)
	fixture.add_child(animal)
	var audio := animal.get_node_or_null("AnimalSound") as AudioStreamPlayer
	var notifier := animal.get_node_or_null("VisibleOnScreenNotifier2D") as VisibleOnScreenNotifier2D
	check(audio != null and audio.stream != null, "Animal prefab includes its call audio and sound resource")
	check(notifier != null and notifier.screen_entered.is_connected(animal._on_visible_on_screen_notifier_2d_screen_entered)
		and notifier.screen_exited.is_connected(animal._on_visible_on_screen_notifier_2d_screen_exited),
		"Animal prefab connects actual screen enter/exit signals")
	await rendered_frames()
	check(notifier.is_on_screen() and audio.playing, "On-screen animal starts its call")
	animal.position = Vector2(10000, 10000)
	await rendered_frames()
	check(not notifier.is_on_screen() and not audio.playing, "Moving off screen stops the call")
	animal.position = Vector2.ZERO
	await rendered_frames()
	check(notifier.is_on_screen() and audio.playing, "Returning on screen restarts the call")
	animal.consume()
	check(not audio.playing, "Consumed animal stops playing immediately")
	animal.reset_home()
	check(not audio.playing and is_zero_approx(animal._animal_sound_elapsed), "Reset clears temporary audio state")
	animal._on_visible_on_screen_notifier_2d_screen_entered()
	check(audio.playing, "Restored animal can play again")
	animal._on_visible_on_screen_notifier_2d_screen_exited()
	check(not audio.playing, "Screen exit stops a restored animal's call")

	# 旧关卡或临时生成的动物没有音效子节点时，也不能触发空实例报错。
	var legacy := Animal.new()
	legacy.gravity = 0.0
	fixture.add_child(legacy)
	legacy._process(0.1)
	legacy._on_visible_on_screen_notifier_2d_screen_entered()
	legacy._on_visible_on_screen_notifier_2d_screen_exited()
	check(legacy._animal_audio == null and legacy._screen_notifier == null,
		"Legacy animal without audio children processes safely")

	var player: EchoPlayer = load("res://scenes/actors/player.tscn").instantiate()
	fixture.add_child(player)
	check(player.move_audio != null and player.move_audio.stream != null
		and player.die_audio != null and player.die_audio.stream != null,
		"Player prefab includes both movement and death sound resources")
	player._play_move_sound()
	check(player.move_audio.playing, "Player movement sound plays")
	player.move_audio.stop()
	player.play_death_sound()
	var death_audio := root.get_child(root.get_child_count() - 1) as AudioStreamPlayer
	check(death_audio != null and death_audio.playing, "Player death sound plays through its one-shot player")
	if death_audio != null:
		death_audio.stop()
		death_audio.queue_free()
	fixture.queue_free()
	await process_frame

	# 主地图全部动物都应继承完整预制体，无需逐个修改用户摆放的节点。
	var map: Node2D = load("res://scenes/world/big_map.tscn").instantiate()
	map.process_mode = Node.PROCESS_MODE_DISABLED
	map.get_node("DoorManager").log_doors = false
	root.add_child(map)
	var complete := true
	for placed in map.get_node("Animals").get_children():
		complete = complete and placed.has_node("AnimalSound") and placed.has_node("VisibleOnScreenNotifier2D")
	check(complete, "Every placed map animal inherits the required nodes")
	check(map.player.move_audio != null and map.player.die_audio != null, "Map player inherits the required audio nodes")
	map.queue_free()
	await process_frame
	print("\nAudio node checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
