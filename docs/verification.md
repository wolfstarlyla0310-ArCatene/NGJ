# 验证记录

2026-11-14（移植 CCCAT 按钮 + 谜题门）

- 新增 `DoorButton`（`scripts/world/button.gd`，Area2D）与 `button_once.tscn` / `button_rebound.tscn`：触发改为 **lv1 及以上声场**与按钮 16×16 区域相交；删除 CCCAT 的朝向/踩踏逻辑，贴图 `assets/tiles/buttom.png` 2×2 帧（左灭 / 右亮，上行一次性 / 下行回弹）。
- 新增 `PuzzleDoorManager`（`scripts/world/puzzle_door_manager.gd`）：四邻分组 `DoorTiles` 门格、开局快照擦除/回填、`door_cells` 接线、全部相连按钮满足才开门、≥2 个回弹按钮同时满足时整组锁死、按房间 `reset_room`；不依赖 BoardManager / 朝向。
- 复制 CCCAT `door_tileset.png` → `assets/tiles/cccat_door_tileset.png`，新建 `resources/door_tileset.tres`（47 格门图集 + 整格物理层 + terrain 3「门」）。
- `big_map.tscn` 新增 `DoorTiles` / `Buttons` / `DoorManager`；`world_map.gd` 在 `_ready` 调 `setup(get_rooms())`、在 `reset_to_checkpoint` 调 `reset_room(room)`；房间编辑器校验新增 DoorTiles / DoorManager 检查。
- 新增 `tests/button_door_checks.gd` **38 项**（门图集与按钮四帧、门格分组、lv0/lv1/lv2、回弹、一次性、组锁、擦格/回填、按房间重置）。七套 headless（本机 Godot 4.5.1）：38 + 67 + 29 + 19 + 7 + 8 + 17；仅 `door_animal_checks` 既有「Animal has no visible texture」失败 1 项。

2026-11-14（声场生成对准 16px 网格）

- `SoundField` 新增 `TILE_SIZE` 与静态 `snap_origin_to_grid(origin, side)`：把声场左上角取整到最近的 16px 格线（中心最多偏移 8px），保证声场边线与格子边界对齐。
- `world_map` / `wave_jump_lab` 的 `_on_wave`、`checkpoint._spawn_field`、`animal._spawn_wave`、`trigger_field._emit_field` 改用吸附后的原点；世界/测试关的玻璃破碎矩形与 lv2 刺摧毁也使用同一个吸附原点，视觉与判定一致。噪音隐藏仍使用单个声场 `encloses`，因为声场已整格对齐。
- 手动创建的 `SoundField`（测试/调试）、刺脉冲、死亡场、门脉冲不吸附。
- 测试：`keyboard_movement_checks` 64 → **67**（新增 helper 左上角对齐、生成声场边线对齐断言）。六套 headless（本机 Godot 4.5.1）：67 + 29 + 19 + 7 + 8 + 17；仅 `door_animal_checks` 既有「Animal has no visible texture」失败 1 项。

2026-11-14（噪音冷却 / 完全覆盖隐藏 / 存档点声场 / lv2 常驻）

- 噪音死亡：`world_map.gd` / `wave_jump_lab.gd` 的 `GRACE_SECONDS` 0.1 → **0.5 秒**；接触判定从玩家中心改为**整个碰撞体**（新增 `NoiseField.touches_rect()`，隐藏格仍然致命）；安全判定仍是中心点在 `safe_for_player` 声场内。
- 噪音隐藏：`NoiseField.sync_visibility()` 从“任意重叠”改为**单个声场 `Rect2.encloses(16×16 格)` 完全覆盖**；同时修正原先误用的 32×32 膨胀格矩形。
- 存档点：每 **0.2 秒**发一个 **5 格 / 80px** 白色 lv0 安全声场（`emitter = null`，门忽略；存档点附近屏障会被持续激活）；新增导出 `fields_enabled` / `field_side_cells` / `field_interval` / `field_lifetime`。
- lv2：玩家 `level == 2` 落地声场 `lifetime = INF`（非 persistent），常驻到 R / 死亡重置；`sound_field.gd` 注释补充 INF 语义。
- 测试：`keyboard_movement_checks` 51 → **64**（0.5s 冷却、身体边缘接触、完全覆盖/部分重叠、`touches_rect`、lv2 常驻/重置）；`big_map_checks` 24 → **29**（存档点 80px 声场与重发、噪音冷却）；`spike_checks` 17 → **19**（过滤存档点声场、lv2 常驻）；`trigger_checks` 仍 7（只统计 48px 声场）。六套 headless（本机 Godot 4.5.1）：64 + 29 + 19 + 7 + 8 + 17；仅 `door_animal_checks` 因工作区既有 `animal.tscn` 移除 `visible = false` 失败 1 项「Animal has no visible texture」，其余全部通过。

2026-11-14（动物声场边长可在检查器调）

- `animal.gd`：移动声场的 `wave_side`（像素）改为 **`move_wave_side_cells`（格）**，默认 1.0 格 = 16px；`idle_wave_side_cells` 默认 1.4 格 = 22.4px。两者都加 `@export_range(0.25, 16.0, 0.25)`，连同 `wave_interval_pixels` / `wave_lifetime` / `wave_expand_duration` / `idle_wave_interval` 归入检查器 **「声场」** 分组；默认表现不变。
- `door_animal_checks.gd` 的移动声场断言改为读取 `move_wave_side_cells * 16.0`。
- 测试（本机 Godot 4.5.1 headless）：`keyboard_movement_checks` / `big_map_checks` / `spike_checks` / `trigger_checks` / `barrier_checks` 全部通过；`door_animal_checks` 的移动/静止声场断言通过。工作区既有未提交改动（`animal.tscn` 移除 `visible = false`）导致「Animal has no visible texture」1 项失败，与本次修改无关。

2026-11-14（玩家声场颜色：lv1 蓝、lv2 黄）

- `SoundField` 新增 `color_for_level()`：lv0 白色、lv1 蓝色 `(0.3, 0.65, 1)`、lv2 黄色 `(1.0, 0.9, 0.2)`；世界与测试关的 `_on_wave` 按等级写入 `field.color`。
- lv0（走路/起跳/小落差）保持白色；门的「红色脉冲吃白色声场主人」规则因此只对 lv0/触发等白色声场生效，lv1/lv2 蓝/黄不触发。
- 测试：`keyboard_movement_checks.gd` 51 项（新增 3 项颜色断言）。六套 headless 51 + 23 + 17 + 7 + 8 + 17 全部通过。

2026-11-14（跳跃最高点悬停 1 秒）

- `player.gd`：移除 `air_time_extra` 的低重力方案，恢复原重力（起跳/下落速度变快）；新增 `apex_hover_time = 1.0`：跳跃到达最高点（竖直速度转为 >= 0）时清零竖直速度并悬停 1 秒，之后恢复原下落速度。
- 跳跃高度仍由 `jump_height_tiles` 决定（当前 4 格 = 64px）；空中水平控制保持；落地/`reset_to` 会清空悬停状态。
- 测试：键盘 48 项及六套 headless 48 + 23 + 17 + 7 + 8 + 17 全部通过。

2026-11-14（刺声场范围改为三格）

- `SpikeField.field_side_cells` 1.4 → **3.0**：红色脉冲视觉边长 48px；击杀判定仍只看刺格本身（16×16），脉冲不参与击杀。
- `spike_checks.gd` 按导出值断言，17 项全部通过。

2026-11-14（玩家滞空 +1s；屏障存在时间 +1s）

- `player.gd` 新增 `air_time_extra = 1.0`：`_ready` 根据当前跳跃高度反算更低的重力，使滞空时间在保持跳跃高度的前提下增加 1 秒（当前 4 格跳跃约 0.58s → 1.58s）。
- `barrier_field.gd` 的 `hide_delay` 0.2 → **1.2 秒**：动物在屏障上方持续发 1 格移动 / 1.4 格静止声场时，动物声场（1.0s）+ 屏障延迟（1.2s）足以覆盖动物的静止间隔（1.0s），屏障不会消失，动物不会掉落。
- `animal.tscn` 恢复 `visible = false` 并移除过期的属性覆盖，使用脚本当前默认（声场 1.0s / 扩散 0.5s / 静止间隔 1.0s / 1.4 格）。
- 测试：键盘跳跃/噪音等待、屏障延迟等待适配新时长；六套 headless 48 + 23 + 17 + 7 + 8 + 17 全部通过。

2026-11-14（可设置起始房间）

- `WorldMap` 新增 `@export var start_room: Room`：设置后开局把玩家放到该房间的 Checkpoint（没有则房间中心），并绑定初始存档点；留空则沿用玩家在场景中的初始房间。
- 房间编辑器「校验地图」新增：Start Room 必须是 `Rooms` 下的房间；该房间没有 Checkpoint 时提示会从房间中心出生。
- 测试适配：`big_map_checks.gd` 显式把 Start Room 设为与玩家位置不同的房间并验证出生点/相机/存档点；`door_animal_checks.gd` 自动选一个非存档点房间放门外陷阱。六套 headless 48 + 23 + 17 + 7 + 8 + 17 全部通过。

2026-11-14（屏障未激活 20% 透明）

- `BarrierField` 新增 20% 透明背景层 `Ghost`（同图集、无碰撞、`modulate.a = 0.2`，位于主屏障层下方）：未激活/延迟结束后的屏障以 20% 透明度显示；被声场覆盖时主层完整显形并获得碰撞，0.2 秒后回到 20%。
- 测试：`barrier_checks.gd` 8 项（新增未激活 20% 背景层检查）。六套 headless 48 + 21 + 17 + 7 + 8 + 17 全部通过。

2026-11-14（刺脉冲仅视觉；击杀改用刺格本体）

- `SpikeField` 的 `field_side_length` 改为 `field_side_cells = 1.4`（视觉边长 22.4px）；生成的红色脉冲 `lethal = false`、`safe_for_player = false`。
- 新增 `SpikeField.touches_rect(area)`：用现存刺格本身的 16×16 区域判定；`WorldMap._physics_process` 使用玩家碰撞体矩形（含 CollisionShape2D 偏移）接触刺格即死亡，脉冲不再参与击杀。
- 测试：`spike_checks.gd` 17 项（脉冲 22.4px、非致命，接触刺格死亡）。六套 headless 48 + 21 + 17 + 7 + 7 + 17 全部通过。

2026-11-14（声场像素化）

- `SoundField._draw()` 与 `DoorField._draw()` 改为共用的 `_draw_pixel_square()`：边框 2 像素、关闭抗锯齿、四边吸附到整数世界坐标，扩散时按整像素步进，消除模糊。
- 只影响绘制；`contains_point()`、玻璃/噪音/安全判定与声场尺寸逻辑不变。
- 六套 headless 测试保持不变并全部通过。

2026-11-14（玩家贴图与 12×15 碰撞体）

- `scenes/actors/player.tscn` 新增 `Sprite2D`（`white_thing.png`），碰撞体改为 12×15。测试改为按实际碰撞宽度计算贴墙接触点，大地图测试改为验证玩家可见贴图，屏障阻挡距离按碰撞半宽校验。
- 六套 headless：48 + 21 + 16 + 7 + 7 + 17 全部通过。

2026-11-14（动物声场更久、扩散更慢）

- `animal.gd`：`wave_lifetime` 默认 0.5 → **1.0 秒**；新增 `wave_expand_duration = 0.5` 并写入动物生成的每个 `SoundField`，扩散比玩家声场更慢。移动 1 格 / 静止 `idle_wave_side_cells`（当前 1.4 格）的尺寸规则不变。
- 测试：`door_animal_checks.gd` 17 项（移动/静止声场按动物导出值断言，并新增时长/扩散参数检查）。六套 headless 48 + 21 + 16 + 7 + 7 + 17 全部通过。

2026-11-14（起跳声场；动物静止声场与隐藏）

- `player.gd`：起跳时发出一次 lv0 声场（`walk_wave_side_cells` 边长，`kind = "jump"`）。
- `animal.gd`：静止（无 lv1 驱动、落地、水平速度≈0）时每 `idle_wave_interval`（默认 2 秒）发一次 **2 格 lv0 白色声场**；移动仍每 16px 发 1 格；`animal.tscn` 设置为 `visible = false`（无贴图）。
- 测试：`keyboard_movement_checks.gd` 48 项（新增起跳两项）、`door_animal_checks.gd` 16 项（新增不可见、静止 2 格声场）。六套 headless 48 + 21 + 16 + 7 + 7 + 16 全部通过。

2026-11-14（门陷阱与受重力动物）

- `SoundField` 新增 `level`、`persistent`、`emitter`；世界/测试关的玩家声场写入等级与 emitter；世界重置跳过 persistent 声场。
- 新增 `DoorField`（红色脉冲 16~48px，透明度随脉冲变化、persistent）与 `Door`（32×32 Area2D）：门体接触吃掉玩家/动物；红色脉冲接触白色声场时吃掉白声场主人；吃掉后隐藏并释放脉冲；按 R / 死亡重置存档点房间时随房间恢复。
- 新增 `Animal`（CharacterBody2D，layer 4，受重力）：附近有 lv1 声场时背离声源水平移动，移动时每 16px 发 1×1 白色声场；可被门吃掉。
- 大地图新增 `SoundFields` 组、`Doors` / `Animals` 容器；`project.godot` 增加 `2d_physics/layer_4="动物"`；`WorldMap` 加入 `world_map` 组、写入声场等级/emitter、重置时恢复门。
- 新增 `tests/door_animal_checks.gd` 14 项；六套 headless 46 + 21 + 16 + 7 + 7 + 14 全部通过。

2026-11-14（声场显形屏障）

- 新增 `assets/tiles/barrier_tile.svg`、`resources/barrier_tileset.tres`（16×16，含整格物理层）与 `scripts/world/barrier_field.gd`：运行时初始隐藏/无碰撞；被任意 `SoundField` 覆盖时 `set_cell` 显形并获得碰撞；声场消失后 0.2 秒擦除。编辑器里保留绘制内容。
- 大地图新增 `Barriers` 层（`collision_enabled = true`、`sound_fields` 接线）；房间编辑器新增接线校验。
- 新增 `tests/barrier_checks.gd` 7 项：初始隐藏、物理层、白色声场显形、阻挡玩家、红色声场同样激活、0.2 秒延迟隐去。五套 headless 46 + 21 + 16 + 7 + 7 全部通过。

2026-11-14（lv2 声场摧毁刺；随房间恢复）

- `SpikeField` 新增初始快照 `_baseline`、`refresh_baseline()`、`destroy_in_rect()`、`restore_rect()`；`WorldMap._on_wave` 在 `level == 2` 时摧毁命中的刺格，`reset_to_checkpoint()` 时随存档点房间恢复刺。
- 刺在运行时仍不可见；「消失」表现为该刺格不再发射红色声场。
- 测试：`spike_checks.gd` 16 项（新增 lv1 不摧毁、lv2 摧毁、房间重置恢复）；四套 headless 46 + 21 + 16 + 7 全部通过。
- README 声场表的「当前」边长同步为 Player 脚本实际默认值 2 / 5 / 9 格。

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
