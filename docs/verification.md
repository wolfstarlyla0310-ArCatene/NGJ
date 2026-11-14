# 验证记录

2026-11-14（声场扩散视觉）

- [scripts/sound_field.gd](scripts/sound_field.gd)：新增 `expand_duration = 0.1s`，方框从中心 ease-out 扩散到目标边长，之后保持满框并在 0.5 秒生命周期内淡出。
- 扩散**只影响视觉**：`contains_point()` 与世界脚本里的 `_active_sound_field_rects()` 仍用目标 `side_length`，玻璃/噪音/安全判定不变。
- 测试：`tests/big_map_checks.gd` 新增两项扩散状态检查（生成 2 帧后 `current_side ∈ (0, 96)`，0.1 秒后 ≈ 96）。
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
