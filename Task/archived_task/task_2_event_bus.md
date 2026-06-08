# Task 2: EventBus

## 目标

创建全局事件总线 `EventBus`，作为组件间唯一通信通道。使用 Godot Autoload 单例模式，任何组件都可直接引用。

## 文件位置

- 脚本：`src/event_bus/event_bus.gd`
- 注册：`project.godot` Autoload 配置

## 功能

1. 全局单例，组件间零引用通信
2. 定义全部跨组件信号
3. 无需手动实例化，Godot 启动时自动加载

## 信号定义

| 信号 | 参数 | 发送者 | 接收者 | 说明 |
|------|------|------|------|------|
| `pose_received` | `pose: Dictionary` | WebSocketClient | Renderer | 车辆位姿 |
| `voxel_received` | `voxels: Array, is_full: bool` | WebSocketClient | Renderer | 体素数据 |
| `path_received` | `points: Array` | WebSocketClient | Renderer | 规划路径 |
| `ctrl_send` | `ctrl: Dictionary` | InputHandler | WebSocketClient | 键盘控制 |

### 消息格式

参考 `docs/protocol.md`。

`pose` Dictionary：
```gdscript
{
    "ts": 1717800000.123,
    "x": 1.5, "y": 0.0, "z": 3.2,
    "yaw": 0.785, "vx": 0.5, "vz": 0.0
}
```

`ctrl` Dictionary：
```gdscript
{
    "type": "ctrl",
    "key": "w",
    "action": "press"
}
```

## 函数

无需自定义函数。EventBus 本身只是一个信号容器，所有功能通过 Godot 内置的 `emit()` / `connect()` 实现。

## 实施步骤

1. 创建 `src/event_bus/event_bus.gd`
   - 继承 `Node`
   - 声明 4 个信号
   - 无需 `_ready` / `_process`

2. 在 `project.godot` 注册 Autoload：
   ```ini
   [autoload]
   EventBus="*res://src/event_bus/event_bus.gd"
   ```

## 测试

- 文件：`test/event_bus/test_event_bus.gd`
- 运行：`godot --headless --script test/event_bus/test_event_bus.gd --path .`

### 测试用例

1. **信号发送与接收**：emit → connect 的回调是否被调用
2. **pose_received 数据完整性**：emit dict，回调收到的数据一致
3. **voxel_received 参数正确**：emit voxels + is_full，回调收到正确参数
4. **ctrl_send 数据完整性**：emit ctrl dict，回调数据一致
5. **多订阅者**：两个回调 connect 同一信号，emit 后都被调用

## 依赖

- [x] 通信协议（docs/protocol.md）
- [x] 架构设计（architecture.md）

## 状态

- [x] 已完成 (2026-06-08)
