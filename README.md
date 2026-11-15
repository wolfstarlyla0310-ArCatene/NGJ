# Keep Sound 驻声 · Godot 白盒

**当前玩法：** 纯键盘平台移动 + 分级白色方形声场。玩家本体使用 `white_thing.png` 贴图显示；行走与落地会留下声场，声场可震碎同级玻璃；红色噪音场中身体碰到噪音会进入可调冷却（默认 0.3 秒，期间贴图渐红），冷却结束时仍在噪音里才回到存档点。

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

**同色重叠合并**：颜色相同（按 RGB）的声场重叠时，只保留并集外轮廓，落在另一个同类声场内部的像素边不再绘制；完全被包住的场不画边界。遮挡按当前视觉尺寸（`current_side`）计算，仅影响绘制，不改变任何判定。

**等级覆盖**：**黄色（lv2）覆盖蓝色（lv1）覆盖白色（lv0）**。不同等级重叠时，被覆盖声场落在覆盖声场矩形内的边段消失，覆盖声场的边界完整保留；绘制层级（z）也按颜色等级排列。红色等非标准颜色只与同色合并，不参与白/蓝/黄等级覆盖。

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
- 使用**可调冷却**（`Noise Grace Seconds`，默认 0.3 秒，在 `BigMap` 根节点检查器调整）：离开噪音或中心进入声场时重置为满值；冷却结束时仍接触噪音则死亡。
- **危险渐红**：冷却递减期间玩家贴图从白色逐渐变红；离开噪音、进入安全声场、死亡或按 R 复活时立即恢复白色。
- 噪音格只要**格子中心落在单个声场矩形内**就会暂时隐藏；声场已吸附到 16px 网格，边缘格与内部格表现一致。隐藏的格子仍然致命，声场消失后恢复显示。
- 死亡 = 回到存档点 + 重置存档点房间，噪音绘制保留，死亡计数 +1。
- **噪音格不发声**：noise tile 只负责区域 / 隐藏 / 致命判定，不再播放任何音效；场景里的 `NoiseSound` 节点保留但保持静默（开局、进入画面都不会响）。

## 刺怪（spike 变成的追击怪）

- 在 `Spikes` 层用 `spike_tileset.tres` 绘制/刷刺格（编辑器里显示红色叉/方框，方便摆放）；**运行时整层隐藏**。
- 进入游戏后，**四邻相连**的刺格自动变成一只怪（`scripts/actors/spike_monster.gd`），挂在 `Monsters` 容器下。
- 视觉为**整组最外缘的满尺寸外框**：每轮只闪 1 次，不再从怪物内部逐格发射；方框立即满尺寸后淡出。边缘尺寸 = 组最长边 + (`Visual Side Cells - 1`) 格（默认单格 48px；大地图 2.5 格 → 单格 40px、2×2 组 56px）。
- 闪烁间隔 `Visual Cycle Interval`、寿命 `Visual Lifetime` 可在 `Spikes` 节点的「刺怪视觉」分组里调整；大地图为 **0.4 秒周期 / 0.15 秒寿命**（快速一明一灭），单个怪物同一时刻最多 1 个外框。
- 怪物外框标记为**永不被覆盖**（`never_covered`）：即使与其它同色红色声场（另一只怪、死亡场、门的红脉冲）重叠，四边也始终完整显示；反过来其它声场仍会被怪物外框覆盖。
- **持续噪音**：每只怪循环播放 `assets/sound/noise.wav`（`Noise` 总线），音量按玩家与怪的**曼哈顿距离**线性衰减，8 格（128px）外停止；`Audible Range Cells` 可在检查器调整。房间裁剪禁用怪物处理时会显式停止音频，恢复房间后重新开始。
- 怪**不绘制 tile 贴图**；命中/接触判定仍是每格 16×16。
- 怪**不受重力、穿墙飞行**，只在出生房间的矩形内活动，不会跨房间追击。
- 追击同一房间内发出声场的目标：**动物一直追**；**玩家只在移动时被追**（静止不追）；**离谁近追谁**。
- 玩家 **lv1 波**命中 → 怪被**推走**，击退期间外框变为**蓝色**；**lv2 波**命中 → 怪被**定住**（不推走，持续到波消失），定住期间外框变为**黄色**；其余时间保持红色。状态切换时会立即补闪一次，不必等下一轮定时闪烁。
- 怪碰到玩家 → 玩家死亡；碰到动物 → 动物被吃掉。目标被吃掉/消耗后不再被追：每帧重新选目标，有其它活目标就换，没有就原地停止（不会停在尸体位置）。
- R / 死亡重置时怪回到出生位置。

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

- 把 `scenes/actors/animal.tscn` 放到 `Animals` 容器下。动物是 16×16 的受重力物体（带 `assets/animal.png` 贴图），会站在地形上/掉落。
- 前进方向遇到**一格高的台阶**会爬上去继续走；**一格深的沟会尝试走过去**，超过一格深才停在平台边缘。
- 被 **lv2 声场**命中时会被震飞一段距离，然后受重力掉落。
- 按 R / 死亡重置时，所有动物回到各自的刷新点；若动物被驱赶进另一个房间且玩家也进入了该房间，刷新点会改到新房间（Room11 → Room12 场景）。
- **Room3 例外**：刷新点落在 Room3 的动物一律改记到 **Room4 的 Checkpoint4 右侧 48px**（玩家在 Room4 复活，避免复活时看不到动物）。只改记录点——动物在 Room3 时保持原位，离开房间组不会被拉回，按 R / 死亡重置才回到 Room4。
- 被怪/门吃掉后动物节点保留（隐藏、停止处理），按 R / 死亡重置会回到刷新点复活。
- 附近出现 **lv1 声场**时被激活，向背离声源的方向水平移动；玩家跳落产生 lv1 声场即可把它驱离。
- 移动时每 `wave_interval_pixels`（16px）发出一个由 `move_wave_side_cells` 控制的 **lv1 蓝色声场**（默认 1 格 / 16px，安全）。
- 停止移动的第一帧**立即**发出一次由 `idle_wave_side_cells` 控制的 **lv1 蓝色声场**，之后按 `idle_wave_interval`（当前 1.0 秒）重复。
- 移动/静止声场边长都在 Animal 检查器的 **「声场」分组**里用滑条调整（单位：16px 格）。
- 动物声场的持续时间与扩散速度由 `wave_lifetime`（当前 1.0 秒）和 `wave_expand_duration`（当前 0.5 秒）控制，比玩家声场更久、更慢。
- 动物也会被门吃掉：它的蓝色声场碰到门的红色脉冲时，门会吃掉它。
- **叫声随距离衰减**：动物在屏时按玩家与动物的**曼哈顿距离**（`|dx|+|dy|`，格）调音量；距离 0 为 0 dB，线性衰减到 `audible_range_cells`（默认 **8 格 = 128px**）时静音，超过即停止播放。`EchoPlayer` 加入 `player` 组供动物查找。

## 按钮与谜题门

- 按钮**只响应蓝色 lv1 声场**：声场矩形与按钮的 16×16 区域相交即视为按下；lv0 白色 / lv2 黄色都不会触发。动物声场现在也是蓝色，因此动物叫声也能按按钮。
- 两种按钮场景：`scenes/world/button_once.tscn`（一次性：首次触发后永久锁定）与 `scenes/world/button_rebound.tscn`（回弹：声场消失即松开）。
- 按钮贴图 `assets/tiles/buttom.png` 是 2×2 帧：左列熄灭 / 右列点亮，上行一次性 / 下行回弹。**所有按钮的点亮帧统一使用右上蓝色帧**，熄灭帧仍按行区分；行为不变。
- `ButtonOnce4` 勾选了 `keep_latched_on_reset`：一旦触发，死亡 / R 也不会清除，永久保持开启。
- 门画在独立的 `DoorTiles` 图层（`resources/door_tileset.tres`，复制自 CCCAT 的 47 格门图集，含整格碰撞）；四邻相连的门格算一扇门，开门 = 擦掉门格，关门 = 按开局快照回填。
- 把按钮放到 `Buttons` 容器下，在按钮的 `Door Cells` 里填目标门内**任意一格**即可接线；运行一次会在输出面板打印门清单（每扇门的编号与格子）。
- 一扇门连接多个按钮时，需要**全部**按钮同时满足才开门；没有连接按钮的门永远关闭。
- 回弹按钮组锁：同一扇门连接 **≥2 个回弹按钮**时，只要它们被同一个/一组声场同时触发，整组会永久锁定（与 CCCAT 一致）；单按钮门只临时打开。
- 按 R / 死亡重置存档点房间时，该房间内的解谜门恢复关闭、按钮 latch 清除（标记了 `keep_latched_on_reset` 的按钮除外）。
- `DoorTiles` / `Buttons` / `DoorManager` 是独立节点；`Doors` 容器仍只放红色门陷阱。

## 收集品（星星）

- 从 `scenes/world/collectible.tscn` 拖一个到 `Collectibles` 容器下；贴图使用 `assets/star.png`（16×16）。
- **没有物理碰撞**：根节点是 `Area2D`，只检测玩家层；玩家可以直接穿过，接触即触发 `collected` 信号并 `queue_free`。
- 贴图缓慢旋转，速度由 `spin_speed`（弧度/秒）控制。
- **纯视觉脉冲**：每 `pulse_interval`（默认 1.2 秒）在星星下生成一个 2 格（32px）、半透明白色（alpha 0.4）的扩散方框，`pulse_lifetime`（0.6 秒）后自动消失。脉冲是收集品的子节点，**不进 `SoundFields` 容器、不进 `sound_fields` 组**，所以不会隐藏噪音、触发屏障/门/按钮，也不会推动动物或刺怪；参数在检查器的「脉冲」分组调整。
- 房间裁剪时，远处房间的收集品会停止旋转、不可见，脉冲也一起暂停；进入该房间后恢复。
- 一次性收集：房间重置不会复活；需要计分/UI 时订阅 `collected`。

## 音频

- 全局自动加载单例 **`AudioManager`**（`scripts/audio/audio_manager.gd`）是音频总控器：启动时把 **`resources/audio_settings.tres`**（`AudioSettings` 资源）里的全部音量写入对应总线。
- 检查器里可调的类别（当前值）：`Master Db` **0**、`Move Db`（走路）**-7**、`Die Db`（死亡）**-4**、`Animal Db`（动物叫声）**-11**、`Jump Db`（小跳/小顶头）**0**、`Drop Db`（大跳/大顶头）**-6**、`Pickup Db`（拾取）**0**、`Glass Db`（玻璃破碎）**-8**、`Noise Db`（噪音提示）**0**、`Button Db`（按钮）**-2**（单位 dB）。改完数值运行即生效，无需改场景节点。
- 音源只负责挂 Stream 并选择总线：`Player/MoveSound`→`Move`、`Player/DieSound`→`Die`、`Player/BlueDropSound`→`Jump`、`Player/YellowDropSound`→`Drop`、`Player/PickUpSound`→`Pickup`、`Animal/AnimalSound`→`Animal`、`Noise/NoiseSound`→`Noise`（噪音格已静音，节点仅保留）、`Breakables/GlassBreakingSound`→`Glass`、按钮 `BottonSound`→`Button`。
- 刺怪在 `setup()` 中创建 `MonsterSound`（`noise.wav`、`Noise` 总线、向前循环），按玩家曼哈顿距离 8 格衰减；存档点激活音效使用 `Pickup` 总线的一次性播放器。
- 例外：`Animal/AnimalSound.volume_db` 由动物按**玩家曼哈顿距离**每帧设置（0 格 0 dB → 8 格静音），最终音量 = 距离衰减 × `Animal` 总线音量。
- 玩家**小跳落地（lv1）与小顶头（lv1）**音效使用 `assets/sound/player_jump.wav`（与走路同一个文件）；大跳/大顶头仍用 `YellowDrop`。
- 新增音效时：在 `default_bus_layout.tres` 加总线，并在 `AudioManager.CATEGORY_BUSES` / `AudioSettings` 增加类别；`AudioManager.apply_settings()` 会自动遍历应用。

## 正式大地图与房间

- `scenes/world/big_map.tscn` 是默认入口：一张大地图 + `Rooms/RoomN` 房间框。
- **起始房间**：选中 `BigMap` 根节点，在检查器把 `Start Room` 设成某个 `Room` 节点；开局会把玩家放到该房间的 Checkpoint（没有则房间中心）。如果直接放在 Checkpoint 上，第一物理帧的接触会绑定它。留空则使用玩家在场景里的初始房间。
- 每个 `Room.rect` 同时决定**相机取景范围**与 **R 重置范围**；跨房时相机用 0.5 秒缓动滑到新房间中心，并按房间大小自动缩放。`RoomCamera.fit_margin` 默认 **0**：房间在受限方向上严格铺满视口（480×288 房间在 1280×720 下 zoom = 2.5，横向因宽高比各留 40px）。
- 存档点**必须实际接触 Checkpoint 才更新**；只进入房间不再自动绑定。房间内没有 Checkpoint、或还没接触过任何 Checkpoint 时，重生点使用玩家当前位置（开局位置/起始锚点）。
- 存档点贴图：未激活使用 `assets/flag_close.png`（80% 不透明度），激活后换成 `assets/flag_open.png`（完全不透明）。
- 存档点**只在玩家接触并绑定后**发出一次 **5 格 / 80px** 白色 lv0 安全场（`emitter` 为空，门不会吃它；`lifetime = INF`、`persistent = true`），之后**一直保持**：更换绑定点、离开房间、按 R / 死亡重置都不会移除；未激活的存档点没有安全区。声场带**渐隐渐显**视觉循环（`field_fade_seconds` 默认 1.2 秒、`field_min_alpha` 默认 0.35，只改节点透明度，不影响安全/隐藏噪音等判定）。
- 玩家**激活存档点时播放一次星星收集品音效**（`assets/sound/PickUP/pickup.mp3`，`Pickup` 总线）。只在 `set_active` 的未激活→激活转换时触发，重启安全场/复活不会重播。
- **死亡**：玩家停在死亡位置、不可操作，**贴图立即隐藏**；按一次 **R** 才回存档点并重置存档点房间（清声场、还原玻璃/刺/门、动物全部归位、相机瞬时 snap），同时恢复玩家贴图。存活时按 R 仍是手动重置。
- **跨房间刷新**：玩家离开一个房间（组）时，上一个房间自动刷新（玻璃、陷阱门、解谜门/按钮、动物、刺怪）；**联动房间一起刷新**（**Room3+Room4+Room5**、Room6+Room8），在联动组内部移动不触发刷新。
- **Room2 的 R 键提示**（`Node2D/R`）初始隐藏，玩家**第一次死亡后永久显示**；按 R 复活后仍保留，提醒玩家可用 R 回到存档点。
- 存档点只是**本局内的一个世界坐标**：不写磁盘、不加标题界面、下次启动不会读档。
- 地形直接用 TileMap 绘制（白盒图集带完整 16px 碰撞）。
- **性能/房间裁剪**：只让玩家**当前房间**内的 `Checkpoint` / `Animal` / `Button` 参与处理与渲染；其它房间的节点保留但不处理、不显示。联动组：**Room3+Room4+Room5**、**Room6+Room8** 各自一起加载。噪音可见性只扫描声场覆盖到的格子；`DoorTiles` / `DoorManager` 保持全局（有一扇门跨房间）。

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
| `scripts/world/world_map.gd` | 房间、切关接线、存档点绑定、单房间 R、噪音死亡、第一次死亡后显示 R 提示 |
| `scripts/world/room.gd` | 房间框（`@tool` 蓝框 gizmo、取景/R 范围） |
| `scripts/world/room_camera_controller.gd` | 房间切换：相机 Tween + 自动缩放（`fit_margin=0` 精确铺满） |
| `scripts/world/checkpoint.gd`、`scenes/world/checkpoint.tscn`、`assets/flag_close.png`、`assets/flag_open.png` | 存档点：重生坐标 + 玩家激活后持续 80px 白色安全声场 + 激活前后旗子贴图 + 激活时播放一次拾取音效 |
| `addons/room_editor/` | 房间编辑器插件（添加房间 / 校验 / 拖拽手柄） |
| `scenes/levels/wave_jump_lab.tscn` | 机制测试关 |
| `scripts/wave_jump_lab.gd` | 测试关的 R、声场生成、噪音生存、鼠标传送 |
| `scripts/player.gd` | 移动、跳跃、分级声场、`Terminal Fall Speed` 可调最大下落速度、危险倒计时贴图渐红（本体由 `player.tscn` 的 Sprite2D 显示） |
| `scripts/sound_field.gd` | 声场视觉效果（中心扩散 + 淡出；`expand_duration = 0` 时直接满尺寸；lv2 使用 `LV2_LIFETIME = 2 秒`；生成时吸附 16px 网格；同色合并 + 黄>蓝>白等级覆盖；`never_covered` 场始终完整绘制；绘制前按相交预筛兄弟场，每帧只扫描一次） |
| `scripts/world/spike_field.gd`、`scripts/actors/spike_monster.gd` | 刺格 → 刺怪生成器（四邻分组）与追击/推/定住/吃人行为；视觉为整组最外缘满尺寸外框闪烁；击退蓝色、定住黄色、目标死亡后停止/换目标；持续循环噪音按距离衰减 |
| `scripts/world/trigger_field.gd` | 触发方块层：玩家站上去每 0.5 秒发一次白色 3 格声场 |
| `scripts/world/barrier_field.gd` | 声场屏障层：未激活 20% 透明；被任意声场覆盖时完整显形挡人，1.2 秒后回到 20% |
| `scripts/world/door.gd`、`scripts/world/door_field.gd`、`scenes/world/door.tscn` | 32×32 门陷阱与 16~48px 红色脉冲声场 |
| `scripts/world/button.gd`、`scenes/world/button_once.tscn`、`button_rebound.tscn` | 声场按钮：lv1+ 触发，一次性 / 回弹 |
| `scripts/world/puzzle_door_manager.gd` | 谜题门管理器：门格分组、按钮接线、开合、组锁、按房间重置 |
| `resources/door_tileset.tres`、`assets/tiles/cccat_door_tileset.png` | 复制自 CCCAT 的 47 格门图集（含整格物理层） |
| `scripts/world/collectible.gd`、`scenes/world/collectible.tscn`、`assets/star.png` | 收集品星星：无碰撞、玩家接触即收集、缓慢旋转、纯视觉 2 格白色脉冲 |
| `scripts/actors/animal.gd`、`scenes/actors/animal.tscn` | 受重力动物：lv1 驱赶、移动/静止发蓝色 lv1 声场、爬一格/过一格沟/换房刷新、叫声按玩家曼哈顿距离衰减 |
| `scripts/breakables.gd` | 图格绘制转碰撞、同级声场震碎、按房间恢复 |
| `scripts/noise_field.gd` | 红色绘制转噪音区域；格子中心在单个声场内即隐藏，身体矩形接触判定；噪音格不播放音效 |
| `scripts/audio/audio_manager.gd`、`scripts/audio/audio_settings.gd`、`resources/audio_settings.tres`、`default_bus_layout.tres` | 音频总控器：Master/Move/Die/Animal/Jump/Drop/Pickup/Glass/Noise/Button 总线，全部音量集中在检查器调 |
| `resources/whitebox_tileset.tres` | 16×16、47 格黑白 blob 地形图集，含完整物理层 |
| `resources/lv1_tileset.tres`、`lv2_tileset.tres`、`noise_tileset.tres`、`assets/tiles/noise_tile.png` | 玻璃与噪音瓦片集（噪音使用 PNG 贴图） |
| `resources/spike_tileset.tres`、`assets/tiles/spike_tile.svg` | 刺图格的编辑器可见标记（运行时刺层隐藏） |
| `resources/trigger_tileset.tres`、`assets/tiles/wind.png` | 触发方块的可见 16×16 图块（常显、无碰撞） |
| `resources/barrier_tileset.tres`、`assets/tiles/barrier_tile.svg` | 声场屏障图块（编辑器可见、含物理层） |

跳跃高度与行走发波间隔在 `scripts/player.gd` 的 `jump_height_tiles`、`walk_wave_interval_tiles` 中调整；走路/lv1/lv2 落地声场边长在 `walk_wave_side_cells` / `landing_lv1_side_cells` / `landing_lv2_side_cells`（16px 格）中调整。

## 检查

用实际 Godot 引擎运行，无外部测试框架。将 `godot` 替换为本机引擎路径：

```powershell
# 音频套件需要渲染窗口（不要加 --headless）；改过 noise.wav 导入设置后先重导入
godot --headless --path . --import
godot --path . --script res://tests/audio_node_checks.gd
godot --headless --path . --script res://tests/keyboard_movement_checks.gd
godot --headless --path . --script res://tests/big_map_checks.gd
godot --headless --path . --script res://tests/spike_checks.gd
godot --headless --path . --script res://tests/trigger_checks.gd
godot --headless --path . --script res://tests/barrier_checks.gd
godot --headless --path . --script res://tests/door_animal_checks.gd
godot --headless --path . --script res://tests/button_door_checks.gd
godot --headless --path . --script res://tests/collectible_checks.gd
godot --headless --path . --script res://tests/checkpoint_wave_checks.gd
godot --headless --path . --script res://tests/sound_field_border_checks.gd
```

- `keyboard_movement_checks.gd`：81 项，覆盖跳跃/起跳悬停、顶天花板 lv1/lv2（零净空）声场、贴墙发声场、声场等级/边长/颜色、声场 16px 网格吸附、lv2 2 秒寿命、最大下落速度限制、走路/撞墙、玻璃破碎与恢复、可调噪音冷却/身体接触/中心覆盖隐藏、调试传送。
- `sound_field_border_checks.gd`：23 项，覆盖同色重叠合并为并集外轮廓、黄>蓝>白等级覆盖（被覆盖边消失）、颜色层级 z 序、红色不参与等级覆盖、同色贴边保留公共边、逻辑判定不变、不同父节点/不可见场/分离场不参与遮挡、`expand_duration = 0` 第一帧即满尺寸、`never_covered` 场不被同色场覆盖但仍覆盖别人。
- `big_map_checks.gd`：77 项，覆盖玩家可见贴图、Start Room 起始房间、房间、相机严格满屏、声场扩散、存档点接触激活后的持续 80px 声场（含渐隐渐显视觉）/旗子贴图、进房不自动绑定/接触才绑定存档点、死亡需按 R 且隐藏贴图并播放死亡音效、Room2 R 提示初始隐藏/首次死亡后永久显示、危险倒计时渐红、房间裁剪（仅当前房间 / Room3+Room4+Room5、Room6+Room8 联动）、跨房间刷新与联动组一起刷新、动物归位与被驱赶换房后的刷新点、Room3 动物刷新点改记 Room4 存档点旁。
- `checkpoint_wave_checks.gd`：25 项，覆盖未激活无场、玩家接触后才发出一次持续场、唯一性/参数、激活时播放一次拾取音效且重启不重播、3 秒不替换、不同相位死亡重开同步安全、`fields_enabled` 清场与重建、离开房间后场保持。
- `spike_checks.gd`：43 项，覆盖刺层隐藏、四邻分组生成怪、每组只发 1 个满尺寸外框（组中心、无内部扩散、覆盖整组、永不被覆盖、自然闪烁时每怪最多 1 个）/判定仍按 tile、刺怪噪音节点/循环/8 格距离衰减/显式启停、击退变蓝/定住变黄（含状态切换即时补闪）、无重力、追动物/移动玩家、近者优先、不跨房间、玩家 lv1 推开、lv2 定住、非玩家声场不推怪、目标死亡后停止/换目标、R 归位、接触吃玩家/动物、被吃动物 R 复活。
- `audio_node_checks.gd`：33 项，覆盖动物/玩家音效节点、全部音频总线存在、各音源总线归属（Move/Die/Animal/Jump/Drop/Pickup/Noise/Glass/Button）、`AudioManager` 自动加载并把 `AudioSettings` 每一类（含 Master）写入总线、动物叫声按玩家曼哈顿距离衰减且 8 格静音、小跳/小顶头使用 `player_jump.wav`、噪音格进入画面也不发声、大地图/测试关/按钮场景的音效路由；需要渲染窗口（不要加 `--headless`）。
- `trigger_checks.gd`：7 项，覆盖触发格存在、站上去重复发白色 48px 声场、安全区、不碎玻璃、冷却。
- `barrier_checks.gd`：8 项，覆盖屏障未激活 20% 透明、任意声场完整显形、物理层、阻挡玩家、声场结束 1.2 秒后回到 20%。
- `door_animal_checks.gd`：26 项，覆盖门脉冲、红脉冲吃白声场主人、门随房间恢复、动物重力/贴图/蓝色 lv1 静止声场（停止后立即发）/lv1 驱赶/移动声场与时长扩散、lv2 震飞、平台边缘停住、一格深沟走过、爬一格台阶、归位、门吃动物。
- `button_door_checks.gd`：40 项，覆盖 CCCAT 门图集/按钮帧（点亮统一蓝色）、门格四邻分组、lv0/lv2 不触发、lv1 触发、回弹、一次性锁定、ButtonOnce4 永久锁定、≥2 回弹按钮组锁、开门擦格/关门回填、按房间重置。
- `collectible_checks.gd`：17 项，覆盖星星贴图/缓慢旋转、纯视觉 32px 白色脉冲（不属于游戏声场）、脉冲按间隔重复、无物理阻挡、玩家接触即收集并消失、远处房间裁剪且节点不释放。

## 协作与原型范围

远程仓库：<https://github.com/wolfstarlyla0310-ArCatene/NGJ>

本仓库包含可直接导入的白盒工程。功能单独建分支，通过 Pull Request 检查后合并；详见 [CONTRIBUTING.md](CONTRIBUTING.md)。保留 `.uid` 文件，`.godot/` 缓存和导出产物已排除。

本版重点验证玩法和手感，尚未加入实际音频、正式美术、敌人攻击或跨启动存档。
