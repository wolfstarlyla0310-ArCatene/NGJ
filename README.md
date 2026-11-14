# ECHO / 同行 · Godot 白盒

**当前玩法：** 纯键盘平台移动 + 分级白色方形声场。玩家本体使用 `white_thing.png` 贴图显示；行走与落地会留下声场，声场可震碎同级玻璃；红色噪音场中身体碰到噪音会进入 0.5 秒冷却，冷却结束时仍在噪音里才回到存档点。

Godot **4.7.2 标准版 + GDScript**，无第三方插件，无需 .NET。完整工程入口为根目录 `project.godot`。

## 立即运行

- 本机双击根目录 **`开始试玩.cmd`**。
- 或在 Godot 中导入 **`project.godot`**，等待首次导入后按 **F5**。
- 默认进入正式大地图 `scenes/world/big_map.tscn`；按 **R** 回到存档点并重置当前房间。
- 机制测试关 `scenes/levels/wave_jump_lab.tscn` 仍保留，可在编辑器中打开后按 F6 单独运行。

Windows 启动器会检查 `GODOT_EXE` 环境变量、系统命令和桌面的 Godot 快捷方式。其他机器找不到引擎时，直接在 Godot 中导入工程。

## 当前操作

| 输入 | 功能 |
|---|---|
| A / D 或 ← / → | 左右移动，空中也可控制方向 |
| 空格 / W / ↑ | 跳跃，高度由 `player.tscn` 的 `jump_height_tiles` 决定（当前 4 格 / 64 像素）；起跳会发出一次 lv0 声场；到达最高点后悬停 1 秒再下落 |
| R | 回到存档点，并只重置存档点所在房间的玻璃 |
| 鼠标左键 / Esc | 仅机制测试关：调试传送 / 静默暂停 |

## 声场等级

声场在发出后的 **`expand_duration`（当前 0.2 秒）内从中心快速扩散到目标边长**，之后保持满框：**lv0/lv1 存在 0.5 秒**并淡出，**lv2 存在 2 秒**；不会推动任何物体。视觉为 **2 像素宽、关闭抗锯齿并按像素对齐**的硬边方框。扩散只影响视觉表现，玻璃破碎/噪音隐藏/安全判定仍按目标尺寸在发出瞬间生效。

玩家、存档点、动物、触发生成的声场会**吸附到 16px 网格**：左上角取整到最近的格线（中心最多偏移 8px），使声场边线与地形/玻璃/噪音格边界对齐。

玩家跳跃上升、头撞到天花板（tile）时会发声场：**起跳瞬间头顶没有任何净空（约 ≤2px）→ lv2 黄色波，持续 2 秒**；有净空 → 与小跳落地的 lv1 蓝波一致（同样能震碎 lv1 玻璃、触发解谜按钮、驱动动物）。每次向上碰撞只发一次；撞墙与落地不会误触发。

玩家**贴着墙壁按 A/D** 时，会按与走路相同的节奏（每 32px 等效）发出 lv0 白色声场；松开方向或离开墙壁后停止。

| 来源 | 等级 | 边长 |
|---|---|---|
| 走路（起步立即发一次，之后每移动 32 像素） | lv0 | 3 格 / 48 像素 |
| 起跳 | lv0 | 3 格 / 48 像素 |
| 落地落差 1~2 格（17~32 像素） | lv0 | 3 格 / 48 像素 |
| 落地落差 3~6 格（33~96 像素） | lv1 | 6 格 / 96 像素 |
| 落地落差 > 6 格（> 96 像素） | lv2 | 10 格 / 160 像素（持续 2 秒） |
| 跳跃上升顶到天花板 | lv2（无净空）/ lv1 | 起跳瞬间头顶无净空：lv2 持续 2 秒（`landing_lv2_side_cells`，当前 10 格 / 160px）；否则与落地 lv1 相同（当前 6 格 / 96px） |
| 动物移动中（每 16 像素） | lv0 | 由 `move_wave_side_cells` 控制（当前 1 格 / 16 像素） |
| 动物静止时（间歇） | lv0 | 由 `idle_wave_side_cells` 控制（当前 1.4 格 / 22.4 像素） |

等级（lv0/1/2）决定能震碎哪一级玻璃；边长由 Player 检查器里的 `walk_wave_side_cells` / `landing_lv1_side_cells` / `landing_lv2_side_cells` 控制。
玩家声场颜色：**lv0 白色、lv1 蓝色、lv2 黄色**；动物/触发为白色，刺/死亡/门脉冲为红色。

跳跃高度由 `jump_height_tiles` 决定（当前 4 个 16px 格 = 64 像素），不随按键时长变化。起跳与下落保持原重力速度；`apex_hover_time`（默认 1 秒）让玩家到达最高点后先悬停 1 秒，再按原速度下落。

## 可破坏图格

- `Breakables/Lv1`、`Breakables/Lv2` 使用 `assets/tiles/lv1_tileset.png`、`lv2_tileset.png` 绘制；两张贴图都是 **16×16 格、47 格 blob 图集**，连接规则与 CCCAT 一致。
- 运行时，绘制的每个 16×16 格子自动生成实体碰撞；被同级声场命中时消失，缺口周围的玻璃会自动重连边缘。
- **只有同等级声场能震碎**：lv1 只碎 lv1，lv2 只碎 lv2，lv0 不能碎任何图格。
- 按 R 或噪音死亡只还原**存档点所在房间**的玻璃；其它房间被震碎的玻璃保持现状。

## 红色噪音场与声场保命

- `Noise` TileMapLayer 使用半透明红色 16×16 瓦片绘制；运行时绘制的格子自动成为噪音区域（纯视觉、无碰撞）。
- **身体任意部分接触**噪音格就开始冷却；只要身体还碰着噪音且中心不在现存声场内，冷却持续递减。
- 使用 **0.5 秒冷却**：离开噪音或中心进入声场时重置为 0.5 秒；冷却结束时仍接触噪音则死亡。
- 只有被**单个声场完整覆盖**的噪音格才会暂时隐藏；声场已吸附到 16px 网格，因此覆盖到的格子按整格隐藏，部分重叠不隐藏。隐藏的格子仍然致命，声场消失后恢复显示。
- 死亡 = 回到存档点 + 重置存档点房间，噪音绘制保留，死亡计数 +1。

## 刺图格

- 刺是普通 TileMapLayer：在 `Spikes` 层用 `spike_tileset.tres` 直接绘制/刷。图块在编辑器里显示为红色叉/方框，方便摆放；**运行时整个 `Spikes` 层隐藏**，所以图格本身没有贴图，只留下它发出的红色声场。
- 每个刺格每 **1 秒**触发一轮，连续发射 **3 个红色脉冲短声场**（间隔 0.1 秒，单个存在 0.2 秒，视觉边长 **3 格 = 48px**）。
- 红色脉冲**只是视觉**；击杀判定只看**刺格本身（16×16）**：玩家身体矩形碰到刺格立刻死亡，脉冲不参与击杀。
- 刺声场按 **lv0** 处理，**不震碎玻璃**；不提供噪音免疫、也不隐藏噪音。
- 玩家死亡时（刺或噪音），死亡位置会额外发出一个**红色、边长 5 格 = 80px** 的声场，纯视觉、不致死。
- 刺接触 **lv2（第三级、最大的落地声场）** 时会被摧毁：该刺格消失，不再发射红色声场；lv0/lv1 不影响它。按 R / 死亡重置存档点房间时会随房间恢复。

## 触发方块

- 无碰撞箱方块：在 `Triggers` 层用 `trigger_tileset.tres` 直接绘制/刷。图块在编辑器和运行时都显示（当前使用 `assets/tiles/wind.png`）；玩家可以直接穿过。
- 玩家站在触发格上时，每 **0.5 秒**发出一次**白色 3 格声场**（48px）。它与玩家声场一样是安全区：可以隐藏噪音、提供噪音免疫；**不震碎玻璃**。
- 冷却由触发层统一控制；站在触发格上会按 0.5 秒持续触发，离开后停止。

## 声场屏障

- 在 `Barriers` 层用 `barrier_tileset.tres` 直接绘制。编辑器里显示为淡蓝色方块；运行时未激活时以 **20% 透明度**显示、**无碰撞**，玩家可以直接穿过。
- 被**任意声场**（玩家白色、触发方块白色、刺/死亡红色）覆盖时**立即显形并获得碰撞**，挡住玩家；玩家紧贴移动时也会被拦住。
- 声场消失后再保持 **1.2 秒**（比旧版多 1 秒）完整显形，然后回到 20% 透明状态。
- 大地图 `Barriers` 层已接好 `sound_fields`；「校验地图」会检查这条接线。

## 门陷阱与动物

### 门（32×32，一次性陷阱）

- 把 `scenes/world/door.tscn` 放到 `Doors` 容器下。门体是 32×32 深红色方块，持续发出 **16~48px 缓慢收缩/放大的红色脉冲声场**，透明度随之变化。
- 任何发声活物（玩家、动物）接触门本体 → 被吃掉并消失，门也消失。
- 门的红色脉冲**接触到白色声场**时，会吃掉这个白色声场的**主人**（玩家或动物），不必接触门体。玩家的 lv0 仍为白色；lv1 蓝色 / lv2 黄色不会触发这条规则。
- 门被吃掉后隐藏、脉冲消失；按 R / 死亡重置存档点房间时随房间恢复。`Doors.sound_fields` 自动通过 `sound_fields` 组找到声场容器。

### 动物（受重力）

- 把 `scenes/actors/animal.tscn` 放到 `Animals` 容器下。动物是 16×16 的**不可见物体**（无贴图），受重力影响，会站在地形上/掉落。
- 附近出现 **lv1 声场**时被激活，向背离声源的方向水平移动；玩家跳落产生 lv1 声场即可把它驱离。
- 移动时每 `wave_interval_pixels`（16px）发出一个由 `move_wave_side_cells` 控制的 **lv0 白色声场**（默认 1 格 / 16px，安全）。
- 静止时按 `idle_wave_interval`（当前 1.0 秒）间歇发出一个由 `idle_wave_side_cells` 控制的 **lv0 白色声场**（默认 1.4 格 / 22.4px）。
- 移动/静止声场边长都在 Animal 检查器的 **「声场」分组**里用滑条调整（单位：16px 格）。
- 动物声场的持续时间与扩散速度由 `wave_lifetime`（当前 1.0 秒）和 `wave_expand_duration`（当前 0.5 秒）控制，比玩家声场更久、更慢。
- 动物也会被门吃掉：它的白色声场碰到门的红色脉冲时，门会吃掉它。

## 按钮与谜题门

- 按钮只响应 **lv1 及以上声场**：声场矩形与按钮的 16×16 区域相交即视为按下；存档点/触发/动物等 lv0 声场不会误触。
- 两种按钮场景：`scenes/world/button_once.tscn`（一次性：首次触发后永久锁定）与 `scenes/world/button_rebound.tscn`（回弹：声场消失即松开）。
- 按钮贴图 `assets/tiles/buttom.png` 是 2×2 帧：左列熄灭 / 右列点亮，上行一次性 / 下行回弹。
- 门画在独立的 `DoorTiles` 图层（`resources/door_tileset.tres`，复制自 CCCAT 的 47 格门图集，含整格碰撞）；四邻相连的门格算一扇门，开门 = 擦掉门格，关门 = 按开局快照回填。
- 把按钮放到 `Buttons` 容器下，在按钮的 `Door Cells` 里填目标门内**任意一格**即可接线；运行一次会在输出面板打印门清单（每扇门的编号与格子）。
- 一扇门连接多个按钮时，需要**全部**按钮同时满足才开门；没有连接按钮的门永远关闭。
- 回弹按钮组锁：同一扇门连接 **≥2 个回弹按钮**时，只要它们被同一个/一组声场同时触发，整组会永久锁定（与 CCCAT 一致）；单按钮门只临时打开。
- 按 R / 死亡重置存档点房间时，该房间内的解谜门恢复关闭、按钮 latch 清除。
- `DoorTiles` / `Buttons` / `DoorManager` 是独立节点；`Doors` 容器仍只放红色门陷阱。

## 正式大地图与房间

- `scenes/world/big_map.tscn` 是默认入口：一张大地图 + `Rooms/RoomN` 房间框。
- **起始房间**：选中 `BigMap` 根节点，在检查器把 `Start Room` 设成某个 `Room` 节点；开局会把玩家放到该房间的 Checkpoint（没有则房间中心）。如果直接放在 Checkpoint 上，第一物理帧的接触会绑定它。留空则使用玩家在场景里的初始房间。
- 每个 `Room.rect` 同时决定**相机取景范围**与 **R 重置范围**；跨房时相机用 0.5 秒缓动滑到新房间中心，并按房间大小自动缩放。
- 存档点**必须实际接触 Checkpoint 才更新**；只进入房间不再自动绑定。房间内没有 Checkpoint、或还没接触过任何 Checkpoint 时，重生点使用玩家当前位置（开局位置/起始锚点）。
- 每个存档点每 **0.2 秒**发射一个 **5 格 / 80px** 的白色 lv0 安全声场（`emitter` 为空，门不会吃它）；因此存档点周围是永久噪音安全区，附近的声场屏障也会被持续激活。
- R / 噪音死亡：清空声场、只还原存档点所在房间的玻璃、把玩家放回存档点、相机瞬时 snap。
- 存档点只是**本局内的一个世界坐标**：不写磁盘、不加标题界面、下次启动不会读档。
- 地形直接用 TileMap 绘制（白盒图集带完整 16px 碰撞）；编辑流程见 [docs/大地图制作手册.md](docs/大地图制作手册.md)。
- **性能/房间裁剪**：只让玩家所在房间 + 上下左右相邻房间内的 `Checkpoint` / `Animal` / `Button` 参与处理与渲染；其它房间的节点保留但不处理、不显示。噪音可见性只扫描声场覆盖到的格子；`DoorTiles` / `DoorManager` 保持全局（有一扇门跨房间）。

## 房间编辑器

- 插件 `addons/room_editor` 已启用；打开 `big_map.tscn` 后工具栏出现 **添加房间** / **校验地图**。
- 选中 `Room` 节点后可拖 8 向手柄；Shift 多选 / 整组拖动 / 轴向锁；Ctrl+Z 撤销。
- 「校验地图」会检查：地形碰撞层、房间尺寸与重叠、地形/玻璃/噪音格是否都在房间内、玩家与相机、存档点是否在 `Objects` 下且落在房间内。

## 模板内容

- 大地图：两间相邻房间（各 1152×648）、连续地板、两个存档点 `(240,556)`、`(1350,556)`；`Breakables`、`Noise` 初始为空，由你绘制。
- 机制测试关：`Breakables/Lv1` 在 `(34,32)`、`(35,32)`，`Lv2` 在 `(30,26)`，噪音区 x=40~43、y=24~33；这些演示格直接写在场景里，编辑器可见。
- `Breakables` / `Noise` 不再在运行时自动补演示内容。

## 工程结构与调参

| 文件 / 目录 | 用途 |
|---|---|
| `scenes/world/big_map.tscn` | 默认入口：正式大地图 |
| `scripts/world/world_map.gd` | 房间、切关接线、存档点绑定、单房间 R、噪音死亡 |
| `scripts/world/room.gd` | 房间框（`@tool` 蓝框 gizmo、取景/R 范围） |
| `scripts/world/room_camera_controller.gd` | 房间切换：相机 Tween + 自动缩放 |
| `scripts/world/checkpoint.gd`、`scenes/world/checkpoint.tscn` | 存档点标记：重生坐标 + 每 0.2 秒 80px 白色安全声场 |
| `addons/room_editor/` | 房间编辑器插件（添加房间 / 校验 / 拖拽手柄） |
| `scenes/levels/wave_jump_lab.tscn` | 机制测试关 |
| `scripts/wave_jump_lab.gd` | 测试关的 R、声场生成、噪音生存、鼠标传送 |
| `scripts/player.gd` | 移动、跳跃、分级声场（本体由 `player.tscn` 的 Sprite2D 显示） |
| `scripts/sound_field.gd` | 声场视觉效果（中心扩散 + 淡出；lv2 使用 `LV2_LIFETIME = 2 秒`；生成时吸附 16px 网格） |
| `scripts/world/spike_field.gd` | 刺图格层：定期发射 3 连发红色脉冲短声场（脉冲仅视觉，击杀看刺格） |
| `scripts/world/trigger_field.gd` | 触发方块层：玩家站上去每 0.5 秒发一次白色 3 格声场 |
| `scripts/world/barrier_field.gd` | 声场屏障层：未激活 20% 透明；被任意声场覆盖时完整显形挡人，1.2 秒后回到 20% |
| `scripts/world/door.gd`、`scripts/world/door_field.gd`、`scenes/world/door.tscn` | 32×32 门陷阱与 16~48px 红色脉冲声场 |
| `scripts/world/button.gd`、`scenes/world/button_once.tscn`、`button_rebound.tscn` | 声场按钮：lv1+ 触发，一次性 / 回弹 |
| `scripts/world/puzzle_door_manager.gd` | 谜题门管理器：门格分组、按钮接线、开合、组锁、按房间重置 |
| `resources/door_tileset.tres`、`assets/tiles/cccat_door_tileset.png` | 复制自 CCCAT 的 47 格门图集（含整格物理层） |
| `scripts/actors/animal.gd`、`scenes/actors/animal.tscn` | 受重力动物：lv1 驱赶、移动发 1×1 白色声场 |
| `scripts/breakables.gd` | 图格绘制转碰撞、同级声场震碎、按房间恢复 |
| `scripts/noise_field.gd` | 红色绘制转噪音区域；单个声场完全覆盖才隐藏，身体矩形接触判定 |
| `resources/whitebox_tileset.tres` | 16×16、47 格黑白 blob 地形图集，含完整物理层 |
| `resources/lv1_tileset.tres`、`lv2_tileset.tres`、`noise_tileset.tres` | 玻璃与噪音瓦片集 |
| `resources/spike_tileset.tres`、`assets/tiles/spike_tile.svg` | 刺图格的编辑器可见标记（运行时刺层隐藏） |
| `resources/trigger_tileset.tres`、`assets/tiles/wind.png` | 触发方块的可见 16×16 图块（常显、无碰撞） |
| `resources/barrier_tileset.tres`、`assets/tiles/barrier_tile.svg` | 声场屏障图块（编辑器可见、含物理层） |

跳跃高度与行走发波间隔在 `scripts/player.gd` 的 `jump_height_tiles`、`walk_wave_interval_tiles` 中调整；走路/lv1/lv2 落地声场边长在 `walk_wave_side_cells` / `landing_lv1_side_cells` / `landing_lv2_side_cells`（16px 格）中调整。

## 检查

用实际 Godot 引擎运行，无外部测试框架。将 `godot` 替换为本机引擎路径：

```powershell
godot --headless --path . --script res://tests/keyboard_movement_checks.gd
godot --headless --path . --script res://tests/big_map_checks.gd
godot --headless --path . --script res://tests/spike_checks.gd
godot --headless --path . --script res://tests/trigger_checks.gd
godot --headless --path . --script res://tests/barrier_checks.gd
godot --headless --path . --script res://tests/door_animal_checks.gd
godot --headless --path . --script res://tests/button_door_checks.gd
```

- `keyboard_movement_checks.gd`：79 项，覆盖跳跃/起跳悬停、顶天花板 lv1/lv2（零净空）声场、贴墙发声场、声场等级/边长/颜色、声场 16px 网格吸附、lv2 2 秒寿命、走路/撞墙、玻璃破碎与恢复、噪音 0.5 秒冷却/身体接触/整格隐藏、调试传送。
- `big_map_checks.gd`：40 项，覆盖玩家可见贴图、Start Room 起始房间、房间、相机切关、声场扩散、存档点每 0.2 秒 80px 声场、进房不自动绑定/接触才绑定存档点、单房间 R、噪音冷却后死亡回存档点、房间裁剪与正交邻接。
- `spike_checks.gd`：19 项，覆盖刺层存在、3 连发红色脉冲、脉冲 48px 且非致命、接触刺格死亡、不碎玻璃、死亡发出 80px 声场、lv2 摧毁与 2 秒寿命、房间重置恢复。
- `trigger_checks.gd`：7 项，覆盖触发格存在、站上去重复发白色 48px 声场、安全区、不碎玻璃、冷却。
- `barrier_checks.gd`：8 项，覆盖屏障未激活 20% 透明、任意声场完整显形、物理层、阻挡玩家、声场结束 1.2 秒后回到 20%。
- `door_animal_checks.gd`：17 项，覆盖门脉冲、红脉冲吃白声场主人、门随房间恢复、动物重力/不可见/静止声场/lv1 驱赶/移动声场与时长扩散、门吃动物。
- `button_door_checks.gd`：38 项，覆盖 CCCAT 门图集/按钮四帧、门格四邻分组、lv0 不触发、lv1/lv2 触发、回弹、一次性锁定、≥2 回弹按钮组锁、开门擦格/关门回填、按房间重置。

## 协作与原型范围

远程仓库：<https://github.com/wolfstarlyla0310-ArCatene/NGJ>

本仓库包含可直接导入的白盒工程。功能单独建分支，通过 Pull Request 检查后合并；详见 [CONTRIBUTING.md](CONTRIBUTING.md)。保留 `.uid` 文件，`.godot/` 缓存和导出产物已排除。

本版重点验证玩法和手感，尚未加入实际音频、正式美术、敌人攻击或跨启动存档。
