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
	check(audio != null and audio.bus == &"Animal", "Animal call routes to the Animal bus")
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
	check(player.move_audio.bus == &"Move" and player.die_audio.bus == &"Die",
		"Player sounds route to Move/Die buses")
	var small_jump := player.get_node_or_null("BlueDropSound") as AudioStreamPlayer
	check(small_jump != null and small_jump.stream != null \
		and small_jump.stream.resource_path == "res://assets/sound/player_jump.wav",
		"Small jump and small ceiling bump use player_jump.wav")
	var manager := root.get_node_or_null("AudioManager")
	check(manager != null, "AudioManager autoload is present")
	var move_bus := AudioServer.get_bus_index("Move")
	var die_bus := AudioServer.get_bus_index("Die")
	var animal_bus := AudioServer.get_bus_index("Animal")
	var jump_bus := AudioServer.get_bus_index("Jump")
	var drop_bus := AudioServer.get_bus_index("Drop")
	var pickup_bus := AudioServer.get_bus_index("Pickup")
	var glass_bus := AudioServer.get_bus_index("Glass")
	var noise_bus := AudioServer.get_bus_index("Noise")
	var button_bus := AudioServer.get_bus_index("Button")
	check(move_bus >= 0 and die_bus >= 0 and animal_bus >= 0
		and jump_bus >= 0 and drop_bus >= 0 and pickup_bus >= 0
		and glass_bus >= 0 and noise_bus >= 0 and button_bus >= 0,
		"Every audio category bus exists")
	var yellow_drop := player.get_node_or_null("YellowDropSound") as AudioStreamPlayer
	var pickup_sound := player.get_node_or_null("PickUpSound") as AudioStreamPlayer
	check(small_jump.bus == &"Jump" and yellow_drop != null and yellow_drop.bus == &"Drop"
		and pickup_sound != null and pickup_sound.bus == &"Pickup",
		"Player jump/drop/pickup sounds route to Jump/Drop/Pickup buses")
	if manager != null:
		var settings_obj := manager.get("settings") as Resource
		var all_applied := true
		for category: StringName in manager.CATEGORY_BUSES:
			var bus_idx := AudioServer.get_bus_index(String(manager.CATEGORY_BUSES[category]))
			var expected: float = float(settings_obj.get(String(category) + "_db"))
			all_applied = all_applied and bus_idx >= 0 \
				and absf(AudioServer.get_bus_volume_db(bus_idx) - expected) < 0.1
		check(all_applied, "AudioManager applies every volume from AudioSettings")
		var master_db: float = float(settings_obj.get("master_db"))
		check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) - master_db) < 0.1,
			"Master bus volume follows AudioSettings")
	# 动物叫声随玩家曼哈顿距离衰减，8 格（128px）为最远可听距离。
	animal.global_position = Vector2.ZERO
	player.global_position = Vector2.ZERO
	animal._on_visible_on_screen_notifier_2d_screen_entered()
	await rendered_frames()
	check(audio.playing and absf(audio.volume_db) < 0.1,
		"Animal call is full volume at the player's position")
	player.global_position = Vector2(32, 32)
	await rendered_frames()
	var expected_half_db := linear_to_db(0.5)
	check(absf(audio.volume_db - expected_half_db) < 0.6,
		"Animal call volume follows Manhattan distance")
	player.global_position = Vector2(64, 64)
	await rendered_frames()
	check(not audio.playing, "Animal call is silent at Manhattan distance 8 tiles")
	player.global_position = Vector2.ZERO
	await rendered_frames()
	check(absf(audio.volume_db) < 0.1, "Animal call volume returns at the player's position")

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
	var noise_audio := map.get_node_or_null("Noise/NoiseSound") as AudioStreamPlayer
	var map_glass := map.get_node_or_null("Breakables/GlassBreakingSound") as AudioStreamPlayer
	check(noise_audio != null and noise_audio.bus == &"Noise", "Noise cue routes to the Noise bus")
	check(map_glass != null and map_glass.bus == &"Glass", "Map glass breakage routes to the Glass bus")
	map.queue_free()
	await process_frame

	var lab: Node = load("res://scenes/levels/wave_jump_lab.tscn").instantiate()
	var lab_glass := lab.get_node_or_null("Breakables/GlassBreakingSound") as AudioStreamPlayer
	check(lab_glass != null and lab_glass.bus == &"Glass", "Lab glass breakage routes to the Glass bus")
	lab.free()
	var button_scenes := ["res://scenes/world/button_once.tscn", "res://scenes/world/button_rebound.tscn"]
	var buttons_routed := true
	for path: String in button_scenes:
		var button: Node = load(path).instantiate()
		var button_audio := button.get_node_or_null("BottonSound") as AudioStreamPlayer2D
		buttons_routed = buttons_routed and button_audio != null and button_audio.bus == &"Button"
		button.free()
	check(buttons_routed, "Button sounds route to the Button bus")
	print("\nAudio node checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
