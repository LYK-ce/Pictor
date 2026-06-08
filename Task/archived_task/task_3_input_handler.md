# Task 3: InputHandler

## 目标

实现键盘输入组件 `InputHandler`，将 WASD / Space 按键转换为 `ctrl` 消息，通过 EventBus 发送。

## 文件位置

- 脚本：`src/input_handler/input_handler.gd`

## 功能

1. 捕获键盘事件（`_input`）
2. 将 `w` `s` `a` `d` `space` 映射为 `ctrl` 消息
3. 通过 `EventBus.ctrl_send.emit()` 发送
4. 区分 `press`（按下）和 `release`（松开）
5. 不依赖任何其他组件，只认识 EventBus

## 键位映射

| 按键 | 动作 |
|------|------|
| `W` | 前进（沿车头方向） |
| `S` | 后退 |
| `A` | 左旋（车身原地逆时针） |
| `D` | 右旋（车身原地顺时针） |
| `Space` | 🛑 紧急停止 |

> 坦克式操纵：A/D 原地旋转车身，W/S 沿朝向移动。

## 消息格式

参考 `docs/protocol.md`：

```json
{
    "type": "ctrl",
    "key": "w",
    "action": "press"
}
```

## 函数

| 函数 | 说明 |
|------|------|
| `_input(event)` | Godot 内置回调，处理 InputEventKey |
| `_key_to_ctrl(key, action)` | private，按键 → ctrl Dictionary |

`InputHandler` 继承 `Node`，无 `_process` 需求。

## 实现细节

- `InputEventKey` 需要设置 `echo = false` 过滤，避免按住时重复触发
- `action`：`event.pressed == true` → `"press"`，`false` → `"release"`
- Godot 按键常量：`KEY_W` `KEY_S` `KEY_A` `KEY_D` `KEY_SPACE`

## 实施步骤

1. 创建 `src/input_handler/input_handler.gd`
   - 继承 `Node`
   - 实现 `_input(event)`
   - 过滤 5 个目标键
   - 忽略 echo 事件
   - 组装 ctrl Dictionary → `EventBus.ctrl_send.emit()`

## 测试

- 文件：`test/input_handler/test_input.gd`
- 运行：`godot --headless --display-driver headless --path . --script test/input_handler/test_input.gd`

### 测试用例

1. **W 键生成正确的 ctrl**：模拟 W press，检查 emit 的 dict
2. **S 键 release**：模拟 S release，action = "release"
3. **Space 键**：模拟 space press，key = "space"
4. **非目标键忽略**：模拟 KEY_ENTER，不应触发 emit
5. **echo 事件过滤**：echo=true 的按键事件应被忽略
6. **多键连续**：连续模拟 W press → W release，两次 emit 数据正确

### 测试实现注意

`InputEventKey` 不能直接被 headless 模式生成（无图形输入）。测试应绕过 `_input`，直接调用内部转换逻辑，或者手动构造消息并验证格式。

## 依赖

- [x] EventBus (task_2)
- [x] 通信协议（docs/protocol.md）

## 状态

- [x] 已完成 (2026-06-08)
