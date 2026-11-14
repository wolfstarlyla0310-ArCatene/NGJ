# 协作约定

- 引擎版本统一为 Godot 4.7.2 标准版，使用 GDScript。
- `main` 保持能导入、能运行。新功能在 `feature/功能名` 分支开发，修复在 `fix/问题名` 分支开发。
- 提交前运行游戏，验证受影响的玩法；机制跑 `tests/keyboard_movement_checks.gd`，大地图/房间跑 `tests/big_map_checks.gd`。
- PR 写明改动、试玩操作和已验证项。涉及画面时附一张正常模式截图。
- 关卡内容统一编辑 `scenes/world/big_map.tscn`；房间框用 `addons/room_editor` 的「添加房间」/「校验地图」。
- 公共脚本与地图修改先在团队内协调，避免多人同时编辑相同场景。
- 保留 Godot 生成的 `.uid` 文件；不要提交 `.godot/` 缓存或本机路径配置。
- 当前玩法为纯键盘平台跳跃，玩家本体不可见；鼠标点击/传送只保留在机制测试关。
