# ECHO / 同行 · Godot 白盒

**当前玩法：** 纯键盘平台移动 + 分级白色方形声场。**玩家本体不可见**，只能看到自己产生的声场；行走与落地会留下声场，声场可震碎同等级的可破坏图格；红色噪音场中必须待在声场覆盖范围内，否则约 0.1 秒后回到存档点。

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
| 空格 / W / ↑ | 跳跃，高度由 `player.tscn` 的 `jump_height_tiles` 决定（当前 4 格 / 64 像素） |
| R | 回到存档点，并只重置存档点所在房间的玻璃 |
| 鼠标左键 / Esc | 仅机制测试关：调试传送 / 静默暂停 |

## 声场等级

声场在发出后的 **0.1 秒内从中心快速扩散到目标边长**，之后保持满框，存在 **0.5 秒**并淡出；不会推动任何物体。扩散只影响视觉表现，玻璃破碎/噪音隐藏/安全判定仍按目标尺寸在发出瞬间生效。

| 来源 | 等级 | 边长 |
|---|---|---|
| 走路（起步立即发一次，之后每移动 32 像素）；落地落差不足 64 像素 | lv0 | 6 格 / 96 像素 |
| 落地落差 64~127 像素 | lv1 | 10 格 / 160 像素 |
| 落地落差 128 像素及以上 | lv2 | 14 格 / 224 像素 |

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
| `scripts/player.gd` | 移动、跳跃、分级声场（玩家本体不绘制） |
| `scripts/sound_field.gd` | 声场视觉效果（0.1 秒中心扩散 + 0.5 秒淡出） |
| `scripts/breakables.gd` | 图格绘制转碰撞、同级声场震碎、按房间恢复 |
| `scripts/noise_field.gd` | 红色绘制转噪音区域 |
| `resources/whitebox_tileset.tres` | 16×16、47 格黑白 blob 地形图集，含完整物理层 |
| `resources/lv1_tileset.tres`、`lv2_tileset.tres`、`noise_tileset.tres` | 玻璃与噪音瓦片集 |

跳跃高度与行走发波间隔在 `scripts/player.gd` 的 `jump_height_tiles`、`walk_wave_interval_tiles` 中调整；声场等级与边长在 `WAVE_SIDE_TILES` 中定义（16px 格）。

## 检查

用实际 Godot 引擎运行，无外部测试框架。将 `godot` 替换为本机引擎路径：

```powershell
godot --headless --path . --script res://tests/keyboard_movement_checks.gd
godot --headless --path . --script res://tests/big_map_checks.gd
```

- `keyboard_movement_checks.gd`：46 项，覆盖跳跃、声场等级与边长、走路/撞墙、玻璃破碎与恢复、噪音、调试传送。
- `big_map_checks.gd`：21 项，覆盖玩家无可见本体、房间、相机切关、声场 0.1 秒扩散、进房存档点绑定、单房间 R、噪音死亡回存档点。

## 协作与原型范围

远程仓库：<https://github.com/wolfstarlyla0310-ArCatene/NGJ>

本仓库包含可直接导入的白盒工程。功能单独建分支，通过 Pull Request 检查后合并；详见 [CONTRIBUTING.md](CONTRIBUTING.md)。保留 `.uid` 文件，`.godot/` 缓存和导出产物已排除。

本版重点验证玩法和手感，尚未加入实际音频、正式美术、敌人攻击或跨启动存档。
