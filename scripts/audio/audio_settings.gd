class_name AudioSettings
extends Resource
## 全局音频音量设置（dB）。在 resources/audio_settings.tres 的检查器里统一调整。

## 总音量：影响下面所有类别（Master 总线）。
@export_range(-80.0, 6.0, 0.5) var master_db := 0.0
## 玩家走路。
@export_range(-80.0, 6.0, 0.5) var move_db := -12.0
## 玩家死亡。
@export_range(-80.0, 6.0, 0.5) var die_db := 0.0
## 动物叫声（节点还会按距离额外衰减）。
@export_range(-80.0, 6.0, 0.5) var animal_db := -6.0
## 小跳 / 小顶头。
@export_range(-80.0, 6.0, 0.5) var jump_db := 0.0
## 大跳 / 大顶头。
@export_range(-80.0, 6.0, 0.5) var drop_db := 0.0
## 收集品拾取。
@export_range(-80.0, 6.0, 0.5) var pickup_db := 0.0
## 玻璃破碎。
@export_range(-80.0, 6.0, 0.5) var glass_db := 0.0
## 噪音提示。
@export_range(-80.0, 6.0, 0.5) var noise_db := 0.0
## 按钮。
@export_range(-80.0, 6.0, 0.5) var button_db := 0.0
