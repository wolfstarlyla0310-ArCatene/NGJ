class_name AudioSettings
extends Resource
## 全局音频音量设置（dB）。在 resources/audio_settings.tres 的检查器里调整。

@export_range(-80.0, 6.0, 0.5) var move_db := -12.0
@export_range(-80.0, 6.0, 0.5) var die_db := 0.0
@export_range(-80.0, 6.0, 0.5) var animal_db := -6.0
