# 验证记录

2026-11-14（落地声场 3/5/7 分级；触发方块常显）

- `player.gd`：落地等级阈值改为 `tiles > 6 → lv2`、`tiles > 2 → lv1`（正好 6 格算 lv1）；边长 lv0 3 格（48px）、lv1 5 格（80px）、lv2 7 格（112px）。导出 `walk_wave_side_cells` / `landing_lv1_side_cells` / `landing_lv2_side_cells`，可在 Player 检查器调整。
- `TriggerField._ready` 的运行时隐藏已移除：触发图块在编辑器和运行时都显示。
- 测试：`keyboard_movement_checks.gd` 46 项、`big_map_checks.gd` 21 项、`spike_checks.gd` 13 项、`trigger_checks.gd` 7 项全部通过。

2026-11-14（触发方块仅编辑器可见；玩家声场 3/5 格）

- `TriggerField._ready()` 设置 `visible = Engine.is_editor_hint()`：编辑器里显示青色触发图块，运行时整个 `Triggers` 层隐藏（图格本身无贴图）。
- `player.gd` 移除 `WAVE_SIDE_TILES`，新增 `walk_wave_side_cells = 3`、`jump_wave_side_cells = 5`（Player 检查器可调）：走路声场 48px / lv0；落地声场统一 80px，等级仍按落差 lv0/lv1/lv2。
- 测试适配：边长断言改为读取导出值；玻璃测试格改为 `(54,31)` / `(57,31)` 避开玩家下落路径；噪音隐藏检查格改为 `(24,33)`；`trigger_checks.gd` 增加运行时隐藏检查（8 项）。
- 四套 headless 结果：46 + 21 + 13 + 8 全部通过。

2026-11-14（触发方块；刺声场改为 lv0）

- 新增 `resources/trigger_tileset.tres`、`assets/tiles/trigger_tile.svg` 与 `scripts/world/trigger_field.gd`：无碰撞、可直接在 `Triggers` 层绘制；玩家站在触发格上每 0.5 秒发出一次白色 48px 安全声场，不震碎玻璃。
- 大地图新增 `Triggers` 层并接线 `player` / `sound_fields`；房间编辑器新增这两条接线校验。
- `SpikeField.glass_level` 默认改为 0：红色刺声场不再震碎玻璃；`spike_checks.gd` 对应改为验证玻璃保持完整。
- 新增 `tests/trigger_checks.gd` 7 项。四套 headless 结果：46 + 21 + 13 + 7 全部通过。

2026-11-14（刺图格与致命红色声场）

- 新增 `resources/spike_tileset.tres`（16×16 图块，编辑器可见、运行时隐藏）与 `scripts/world/spike_field.gd`（`@tool` TileMapLayer）：可直接在 `Spikes` 层绘制刺格；每个刺格每 1 秒触发一轮、3 连发红色短声场（间隔 0.1 秒、单个 0.2 秒、边长 3 格 = 48px）。
- 刺声场按 lv0 处理、不震碎玻璃；图块在编辑器里显示为红色叉/方框，运行时整个 `Spikes` 层隐藏（图格无贴图）。
- `SoundField` 新增 `color` / `lethal` / `safe_for_player` / `get_rect()`：玩家白色声场保持安全；刺声场红色、致命、非安全区。
- `WorldMap`：玩家身体矩形接触致命声场立即死亡；死亡后回存档点，并在死亡位置发出边长 5 格 = 80px 的红色纯视觉声场；噪音安全/隐藏只统计 `safe_for_player` 声场。
- 房间编辑器新增 `Spikes.sound_fields` / `Spikes.breakables` 接线校验。
- 测试：新增 `tests/spike_checks.gd` 13 项；`big_map_checks.gd` 的扩散检查改为按 `expand_duration` 等待。三套 headless 结果：46 + 21 + 13 全部通过。

2026-11-14（声场扩散视觉）

- [scripts/sound_field.gd](scripts/sound_field.gd)：新增 `expand_duration`（当前 0.2s），方框从中心 ease-out 扩散到目标边长，之后保持满框并在 0.5 秒生命周期内淡出。
- 扩散**只影响视觉**：`contains_point()` 与世界脚本里的 `_active_sound_field_rects()` 仍用目标 `side_length`，玻璃/噪音/安全判定不变。
- 测试：`tests/big_map_checks.gd` 新增两项扩散状态检查（生成 2 帧后 `current_side ∈ (0, 96)`，按 `expand_duration` 等待后 ≈ 96）。
- 同步当前工作区调整：玩家碰撞体 16×16、跳跃高度按 `jump_height_tiles` 计算（当前 6 格 / 96px），测试按 `jump_height_tiles × 16` 校验跳跃顶点、撞墙 `contact_x = 136`；大地图测试改为从当前场景动态读取房间/存档点/相机，避免绑定具体关卡内容。
- headless：`keyboard_movement_checks.gd` 46 项、`big_map_checks.gd` 21 项全部通过。

2026-11-14（16px 图格、完整物理层、正式大地图、玩家隐去）

- 三张图集恢复为 CCCAT 原生的 **128×96、16×16 一格**；瓦片集 `texture_region_size = 16×16`、`tile_size = 16×16`，47 格 blob 连接规则与 CCCAT 一致。
- 白盒地形图集补齐**完整物理层**：47 个图块各有 32 个顶点的整格多边形（16×16），`collision_layer = 1`；大地图 `Terrain` 的 `collision_enabled = true`，画出来的墙直接可站。
- 玩家本体不再绘制；所有方形扩散波统一命名为「声场」（`ForcePulse` → `SoundField`，`Pulses` → `SoundFields`）。
- 机制测试关改用直接绘制的 16px 地形（`Terrain/Visual`），移除 `terrain_visual.gd` 与 WallPlatform；玻璃/噪音演示格按 16px 坐标重新烘焙。
- 新增正式大地图 `scenes/world/big_map.tscn`：两间房、连续 16px 地板、Checkpoint、`RoomCamera` 相机切关、单房间 R、进房自动绑定存档点（只记录坐标，不写磁盘）。
- 移植 CCCAT 的房间编辑器插件（添加房间 / 校验地图 / 8 向拖拽）。
- headless 验证：`tests/keyboard_movement_checks.gd` 46 项、`tests/big_map_checks.gd` 21 项全部通过；编辑器插件加载无报错。

2026-11-14，本机 Godot 4.7.2 标准版（Steam 版引擎）。

- 分级声波 / 可破坏图格 / 噪音场 / 调试传送：`tests/keyboard_movement_checks.gd` 共 **46 项全部通过**。
  - 冷启动不产生声波；跳跃顶点 96 ±1 像素（3 格）。
  - 声波等级与边长：落差 1 格 → lv0 / 96 像素；2~3 格 → lv1 / 160 像素；4 格 → lv2 / 224 像素；不足 1 格不发声波；走路为 lv0 / 96 像素。
  - 走路、撞墙、双击等既有行为保持不变，声波仍然不推动玩家。
  - 可破坏图格：lv1 波只碎 lv1，lv2 波只碎 lv2，lv0 不能碎任何图格；重置可恢复被震碎的格子。
  - 噪音场：进入后站桩约 0.1 秒重开；持续走动安全（起步立即生成一个白框）；跳跃滞空约 0.1 秒死亡；出生点（噪音外）始终安全；死亡后回到出生点。
  - 白框覆盖到的红色噪音格会暂时隐藏，白框消失后恢复显示。
  - 鼠标左键点击可把玩家传送到点击位置。
- 架构：新增 `Breakables`（TileMapLayer 绘制转实体碰撞）与 `NoiseField`（红色绘制转噪音区域）；白色方框存活时间保持 0.5 秒，死亡豁免时间改为 0.1 秒；白框会临时隐藏其覆盖的红色噪音格；关卡加入 `Breakables/Lv1`、`Breakables/Lv2`、`Noise` 节点与三个 TileSet。
- 静态检查：新增资源均被场景引用；未发现残留的旧等级/推动/疾跑机制引用。

以上为 headless 自动验证。手感、画面观感和地形衔接仍需在本机实际试玩确认。尚未做正式音频、美术、完整游戏流程或跨设备性能测试。
