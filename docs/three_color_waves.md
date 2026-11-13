# 三色声波与持续声源

## 版本与实现

`project.godot` 声明 Godot 4.7，`CONTRIBUTING.md` 约定 4.7.2 标准版。沿用项目已有的 Godot 4 `TileMapLayer` 与 `TileSetAtlasSource` API。

- `WaveTypes.WaveType` 定义 WHITE / RED / BLUE。类型独立保存，默认白色；颜色由 `color_for()` 统一映射。
- `WaveFactory.spawn(parent, global_origin, wave_type, options)` 在入树前配置参数，并将全局位置转换到容器坐标。点击、撞击和持续声源通过关卡 `emit_wave()` 进入同一工厂。
- 默认关卡继续使用 `ForcePulse`：点击仍在原格中心，速度 760、范围 240、四向单次施力；撞击仍在原接触位置生成速度 300、范围 70 的纯视觉波，不改变反弹规则。源发出的波保留传播/施力/销毁机制，但关闭格心吸附以使用声源的准确全局位置。
- 旧 `first_crossing` 关卡继续使用寿命 2.4 秒的回声脉冲，保留听觉衰减及边缘反射，反射支持类型颜色。
- 墙体保留 `WallPlatform` 场景、整块矩形碰撞及自动生成图块的结构。现有 TileSet 增加红/蓝 alternative（ID 1/2）与整数 `wave_type` 自定义数据。没有将单格改成独立场景。
- 持续声源不包含碰撞节点，多个实例使用各自的 Timer。发出的波归属关卡波容器，删除声源不会删除已发出的波。

## 放置红蓝图块

1. 打开现有关卡，例如 `scenes/levels/wave_jump_lab.tscn`。
2. 选择 `Terrain` 下已有的墙体，或从文件系统拖入 `scenes/actors/wall_platform.tscn`，放到 `Terrain` 下。保持原关卡对墙体的收集方式。
3. 设置 `Tiles Wide`、`Tiles High` 和位置；设置 `Wave Type` 为 WHITE / RED / BLUE 即可改变整块墙内图块。编辑器中立即显示对应颜色。
4. 要在一块墙中混用颜色，在 `Red Cells` / `Blue Cells` 数组添加局部 `Vector2i` 格坐标。例如 `(0, 0)` 是左上格，`(1, 0)` 是右侧第二格。Blue Cells 优先于 Red Cells，未覆盖的格使用 Wave Type。
5. 当前墙体会自动重建 `Tiles`，请通过这些 Inspector 参数配置，不要直接手绘它的子 TileMapLayer；重建会覆盖手绘内容。独立使用该 TileSet 时，也可在 TileMap 编辑器选择白/红/蓝 alternative，其自定义数据分别为 0/1/2。
6. 运行默认关卡，开始后左键点击图块；撞击图块时同样产生对应颜色波。旧关卡的点击规则（例如敲铃）保持原样。

## 放置持续声源

1. 将 `scenes/actors/SoundSource.tscn` 拖入当前 2D 关卡，设置位置。可以放在嵌套 Node2D 下。
2. 在 Inspector 设置 `Wave Type`（默认 WHITE）、`Emission Interval`（秒，默认 1，最小 0.001）和 `Start Emitting`（默认勾选）。首次脉冲在一个间隔后发出。
3. 复制多个实例，分别配置颜色和间隔。源的圆形标识在编辑器与游戏中随类型变色。
4. 运行时可通过 `start()` / `stop()` 控制，或关闭 `Enabled` / 将节点 `Process > Mode` 设为 Disabled。恢复 Enabled 会按新间隔重新计时；恢复 Process Mode 则继续原计时。修改运行中间隔会从新间隔重新计时。
5. 已发出的波会自然消失；退出场景停止 Timer。声源没有碰撞体。
6. 有 `emit_wave()` 的祖先关卡使用该关卡原有生成参数；其他 Node2D 场景通过同一工厂生成默认 ForcePulse。没有玩家目标时只显示脉冲，不施力。声源的自动发声独立于关卡自定义的开始/暂停 UI；如需与这些状态同步，可由关卡调用 `start()` / `stop()` 或设置 Enabled。

## 验证

本环境实际安装 Godot **4.6.3 stable**，没有更改项目声明的版本。以下均通过：

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script tests/color_wave_checks.gd
godot --headless --path . --script tests/grid_rebound_checks.gd
godot --headless --path . --script tests/wave_jump_checks.gd
godot --headless --path . --script tests/puzzle_checks.gd
godot --headless --path . --script tests/gameplay_checks.gd
```

新增测试覆盖三色真实鼠标输入、三色实际玩家落地、原传播参数、变换父节点下的位置、多个不同间隔声源、运行时参数变化、停用/停止/退出、脉冲正常销毁和旧回声接口。原测试覆盖角色移动、跳跃、格心点击与反弹规则。项目加载没有新增脚本解析错误或无效节点引用。

尚未验证：Godot 4.7.2 下的实际运行，以及图形界面中 Inspector 操作和最终视觉截图。本会话没有可调用的桌面控制工具或已连接的图形显示，测试使用 headless 模式；视觉颜色已通过统一映射和 TileSet 数据接入，但没有进行像素级渲染验收。
