extends Node
## 全局音频管理器（自动加载单例）：把所有音效归类到总线，
## 音量集中在 resources/audio_settings.tres 里调整。

const CATEGORY_BUSES := {
	&"move": &"Move",
	&"die": &"Die",
	&"animal": &"Animal",
}

var settings: Resource = preload("res://resources/audio_settings.tres")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_settings()

func apply_settings() -> void:
	set_category_volume(&"move", float(settings.get("move_db")))
	set_category_volume(&"die", float(settings.get("die_db")))
	set_category_volume(&"animal", float(settings.get("animal_db")))

func set_category_volume(category: StringName, volume_db: float) -> void:
	var bus_name: StringName = CATEGORY_BUSES.get(category, category)
	var idx := AudioServer.get_bus_index(String(bus_name))
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_db)

func get_category_volume(category: StringName) -> float:
	var bus_name: StringName = CATEGORY_BUSES.get(category, category)
	var idx := AudioServer.get_bus_index(String(bus_name))
	if idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(idx)
