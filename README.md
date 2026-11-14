# ECHO / 同行 · Godot 白盒

**当前玩法：** 纯键盘平台移动 + 分级白色方形声场。玩家本体使用 `white_thing.png` 贴图显示；行走与落地会留下声场，声场可震碎同级玻璃；红色噪音场中必须待在声场覆盖范围内，否则约 0.1 秒后回到存档点。

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
| 空格 / W / ↑ | 跳跃，高度由 `player.tscn` 的 `jump_height_tiles` 决定（当前 4 格 / 64 像素）；起跳会发出一次 lv0 声场 |
| R | 回到存档点，并只重置存档点所在房间的玻璃 |
| 鼠标左键 / Esc | 仅机制测试关：调试传送 / 静默暂停 |

## 声场等级

声场在发出后的 **`expand_duration`（当前 0.2 秒）内从中心快速扩散到目标边长**，之后保持满框，存在 **0.5 秒**并淡出；不会推动任何物体。视觉为 **2 像素宽、关闭抗锯齿并按像素对齐**的硬边方框。扩散只影响视觉表现，玻璃破碎/噪音隐藏/安全判定仍按目标尺寸在发出瞬间生效。

| 来源 | 等级 | 边长 |
|---|---|---|
| 走路（起步立即发一次，之后每移动 32 像素） | lv0 | 2 格 / 32 像素 |
| 起跳 | lv0 | 2 格 / 32 像素 |
| 落地落差 ≤ 2 格（≤ 32 像素） | lv0 | 2 格 / 32 像素 |
| 落地落差 3~6 格（33~96 像素） | lv1 | 5 格 / 80 像素 |
| 落地落差 > 6 格（> 96 像素） | lv2 | 9 格 / 144 像素 |
| 动物移动中（每 16 像素） | lv0 | 1 格 / 16 像素 |
| 动物静止时（间歇） | lv0 | 由 `idle_wave_side_cells` 控制（当前 1.4 格 / 22 像素） |

等级（lv0/1/2）决定能震碎哪一级玻璃；边长由 Player 检查器里的 `walk_wave_side_cells` / `landing_lv1_side_cells` / `landing_lv2_side_cells` 控制。

跳跃高度由 `jump_height_tiles` 决定（当前 4 个 16px 格 = 64 像素），不随按键时长变化。

## 可破坏图格

- `Breakables/Lv1`、`Breakables/Lv2` 使用 `assets/tiles/lv1_tileset.png`、`lv2_tileset.png` 绘制；两张贴图都是 **16×16 格、47 格 blob 图集**，连接规则与 CCCAT 一致。
- 运行时，绘制的每个 16×16 格子自动生成实体碰撞；被同级声场命中时消失，缺口周围的玻璃会自动重连边缘。
- **只有同等级声场能震碎**：lv1 只碎 lv1，lv2 只碎 lv2，lv0 不能碎任何图格。
- 按 R 或噪音死亡只还原**存档点所在房间**的玻璃；其它房间被震碎的玻璃保持现状。

## 红色噪音场与声场保命

- `Noise` TileMapLayer 使用半透明红色 16×16 瓦片绘制；运行时绘制的格子自动成为噪音区域（纯视觉、无碰撞）。
- 玩家中心在噪音内时，必须位于某个现存声场内才算安全。判定时只看玩家中心点。
- 使用 **0.1 秒宽限**：在噪音外或声场内时计时重置为 0.1 秒；在噪音内且不在声场内时递减，归零即死亡。
- 声场覆盖到的红色噪音格会暂时隐藏，声场消失后恢复显示。
- 死亡 = 回到存档点 + 重置存档点房间，噪音绘制保留，死亡计数 +1。

## 刺图格

- 刺是普通 TileMapLayer：在 `Spikes` 层用 `spike_tileset.tres` 直接绘制/刷。图块在编辑器里显示为红色叉/方框，方便摆放；**运行时整个 `Spikes` 层隐藏**，所以图格本身没有贴图，只留下它发出的红色声场。
- 每个刺格每 **1 秒**触发一轮，连续发射 **3 个红色短声场**（间隔 0.1 秒，单个存在 0.2 秒，边长 3 格 = 48px）。
- 刺声场与玩家声场的扩散/淡出表现一致，但为红色且**致命**：玩家身体碰到红色声场立刻死亡。
- 刺声场按 **lv0** 处理，**不震碎玻璃**；不提供噪音免疫、也不隐藏噪音。
- 玩家死亡时（刺或噪音），死亡位置会额外发出一个**红色、边长 5 格 = 80px** 的声场，纯视觉、不致死。
- 刺接触 **lv2（第三级、最大的落地声场）** 时会被摧毁：该刺格消失，不再发射红色声场；lv0/lv1 不影响它。按 R / 死亡重置存档点房间时会随房间恢复。

## 触发方块

- 无碰撞箱方块：在 `Triggers` 层用 `trigger_tileset.tres` 直接绘制/刷。图块在编辑器和运行时都显示（当前使用 `assets/tiles/wind.png`）；玩家可以直接穿过。
- 玩家站在触发格上时，每 **0.5 秒**发出一次**白色 3 格声场**（48px）。它与玩家声场一样是安全区：可以隐藏噪音、提供噪音免疫；**不震碎玻璃**。
- 冷却由触发层统一控制；站在触发格上会按 0.5 秒持续触发，离开后停止。

## 声场屏障

- 在 `Barriers` 层用 `barrier_tileset.tres` 直接绘制。图块在编辑器里显示为淡蓝色方块，运行时**平时隐藏、无碰撞**，玩家可以直接穿过。
- 被**任意声场**（玩家白色、触发方块白色、刺/死亡红色）覆盖时**立即显形并获得碰撞**，挡住玩家；玩家紧贴移动时也会被拦住。
- 声场消失后再保持 **0.2 秒**才隐去。
- 大地图 `Barriers` 层已接好 `sound_fields`；「校验地图」会检查这条接线。

## 门陷阱与动物

### 门（32×32，一次性陷阱）

- 把 `scenes/world/door.tscn` 放到 `Doors` 容器下。门体是 32×32 深红色方块，持续发出 **16~48px 缓慢收缩/放大的红色脉冲声场**，透明度随之变化。
- 任何发声活物（玩家、动物）接触门本体 → 被吃掉并消失，门也消失。
- 门的红色脉冲**接触到白色声场**时，会吃掉这个白色声场的**主人**（玩家或动物），不必接触门体。
- 门被吃掉后隐藏、脉冲消失；按 R / 死亡重置存档点房间时随房间恢复。`Doors.sound_fields` 自动通过 `sound_fields` 组找到声场容器。

### 动物（受重力）

- 把 `scenes/actors/animal.tscn` 放到 `Animals` 容器下。动物是 16×16 的**不可见物体**（无贴图），受重力影响，会站在地形上/掉落。
- 附近出现 **lv1 声场**时被激活，向背离声源的方向水平移动；玩家跳落产生 lv1 声场即可把它驱离。
- 移动时每 16px 像玩家一样发出一个 **1×1 格（16px）白色声场**（安全，level 0）。
- 静止时每 **2 秒**间歇性发出一个由 `idle_wave_side_cells` 控制的 **lv0 白色声场**（当前 1.4 格 / 22px；间隔 `idle_wave_interval` 可调）。
- 动物声场的持续时间与扩散速度由 `wave_lifetime`（当前 1.0 秒）和 `wave_expand_duration`（当前 0.5 秒）控制，比玩家声场更久、更慢。
- 动物也会被门吃掉：它的白色声场碰到门的红色脉冲时，门会吃掉它。

## 正式大地图与房间

- `scenes/world/big_map.tscn` 是默认入口：一张大地图 + `Rooms/RoomN` 房间框。
- 每个 `Room.rect` 同时决定**相机取景范围**与 **R 重置范围**；跨房时相机用 0.5 秒缓动滑到新房间中心，并按房间大小自动缩放。
- 进房自动绑定该房间的 `Checkpoint` 位置作为存档点；房间内没有 Checkpoint 时，记录玩家刚进入房间的位置。
- R / 噪音死亡：清空声场、只还原存档点所在房间的玻璃、把玩家放回存档点、相机瞬时 snap。
- 存档点只是**本局内的一个世界坐标**：不写磁盘、不加标题界面、下次启动不会读档。
- 地形直接用 TileMap 绘制（白盒图集带完整 16px 碰撞）；编辑流程见 [docs/大地图制作手册.md](docs/大地图制作手册.md)。

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
| `scripts/world/checkpoint.gd`、`scenes/world/checkpoint.tscn` | 存档点标记 |
| `addons/room_editor/` | 房间编辑器插件（添加房间 / 校验 / 拖拽手柄） |
| `scenes/levels/wave_jump_lab.tscn` | 机制测试关 |
| `scripts/wave_jump_lab.gd` | 测试关的 R、声场生成、噪音生存、鼠标传送 |
| `scripts/player.gd` | 移动、跳跃、分级声场（本体由 `player.tscn` 的 Sprite2D 显示） |
| `scripts/sound_field.gd` | 声场视觉效果（中心扩散 + 0.5 秒淡出；白色安全 / 红色致命） |
| `scripts/world/spike_field.gd` | 刺图格层：定期发射 3 连发红色致命短声场 |
| `scripts/world/trigger_field.gd` | 触发方块层：玩家站上去每 0.5 秒发一次白色 3 格声场 |
| `scripts/world/barrier_field.gd` | 声场屏障层：被任意声场覆盖时显形挡人，声场消失 0.2 秒后隐去 |
| `scripts/world/door.gd`、`scripts/world/door_field.gd`、`scenes/world/door.tscn` | 32×32 门陷阱与 16~48px 红色脉冲声场 |
| `scripts/actors/animal.gd`、`scenes/actors/animal.tscn` | 受重力动物：lv1 驱赶、移动发 1×1 白色声场 |
| `scripts/breakables.gd` | 图格绘制转碰撞、同级声场震碎、按房间恢复 |
| `scripts/noise_field.gd` | 红色绘制转噪音区域 |
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
```

- `keyboard_movement_checks.gd`：48 项，覆盖跳跃/起跳声场、声场等级与边长、走路/撞墙、玻璃破碎与恢复、噪音、调试传送。
- `big_map_checks.gd`：21 项，覆盖玩家可见贴图、房间、相机切关、声场扩散、进房存档点绑定、单房间 R、噪音死亡回存档点。
- `spike_checks.gd`：16 项，覆盖刺层存在、3 连发红色致命声场、边长 48px、不碎玻璃、接触死亡、死亡发出 80px 红色声场、lv2 摧毁与房间重置恢复。
- `trigger_checks.gd`：7 项，覆盖触发格存在、站上去重复发白色 48px 声场、安全区、不碎玻璃、冷却。
- `barrier_checks.gd`：7 项，覆盖屏障初始隐藏、任意声场显形、物理层、阻挡玩家、声场结束 0.2 秒后隐去。
- `door_animal_checks.gd`：17 项，覆盖门脉冲、红脉冲吃白声场主人、门随房间恢复、动物重力/不可见/静止声场/lv1 驱赶/移动声场与时长扩散、门吃动物。

## 协作与原型范围

远程仓库：<https://github.com/wolfstarlyla0310-ArCatene/NGJ>

本仓库包含可直接导入的白盒工程。功能单独建分支，通过 Pull Request 检查后合并；详见 [CONTRIBUTING.md](CONTRIBUTING.md)。保留 `.uid` 文件，`.godot/` 缓存和导出产物已排除。

本版重点验证玩法和手感，尚未加入实际音频、正式美术、敌人攻击或跨启动存档。
