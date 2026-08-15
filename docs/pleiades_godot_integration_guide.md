# Pleiades × Godot 集成实施指南（修改清单 + 构建部署）

> 创建日期：2026-08-15
> 关联：`task_23_pleiades_integration.md`（任务）、`docs/pictor_pleiades_integration.md`（架构设计）
> 本文档回答三个问题：**Rust 侧改什么、Godot 侧改什么、两者怎么合并到一起。**

---

## 0. 总览

目标架构：**Pleiades（无头）= 逻辑层，Godot = 表现层，中间一个 GDExtension 桥（单进程）。**

涉及两个代码库：

| 代码库 | 位置 | 角色 |
|---|---|---|
| Orion（Rust） | `/Workspace/Orion/` | 逻辑层（libp2p 网络 / 协议 / 地图合并 / LLM） |
| Pictor（Godot） | 本仓库 | 表现层（渲染 / UI / 输入） |

桥的物理形态 = **一个 Rust 编译出的共享库（`.so`）** + **一个 Godot 注册文件（`.gdextension`）**。

---

## 1. Rust 侧（Orion）需要做的修改

### 1.1 保留全部功能，仅无头化

- **现状**：Pleiades 是完整节点，`[lib] name = "pleiades"` 导出全部模块（网络 + ML + TUI + API + VM）。
- **目标**：**功能全部保留**（ML 推理 / axum API / Lua VM / 存储照常），唯一去掉的是 TUI（`Src/TUI/`），展示交给 Godot。
- **方式**：加一个「无头」入口，启动时跳过 TUI 初始化，其余模块（ML/API/VM/网络/存储）原样运行。

### 1.2 无头模式

- 不启动 TUI（`Src/TUI/`），事件/状态改由桥导出。
- 参照 `orion-robot`（已是无头）的模式，做一个「终端节点」变体。

### 1.3 命令 request-response 接收路由

- **现状**：命令走 WebSocket（`Src/WebSocket/server.rs` → `parse_orion_frame` → `robot_cmd_tx`）。
- **目标**：在 request-response 协议里加「机器人控制」命令类型；车端收到 → 复用 `parse_orion_frame` → `robot_cmd_tx`（解析和命令通道都是现成的，只换投递入口）。
- `Src/WebSocket/server.rs` 退役（可暂留作调试）。

### 1.4 新增桥 crate（`pictor-kernel`）

- 新 crate：`crate-type = ["cdylib"]`。
- 依赖：`godot`（gdext）+ Pleiades（完整，保留 ML/API/VM）。
- 内容：桥类（信号 + handle 方法），见 §3.5。

---

## 2. Godot 侧（Pictor）需要做的修改

### 2.1 删除

| 文件 | 原因 |
|------|------|
| `src/websocket/` 整套（client / manager / protocol） | WebSocket 通道移除，由 libp2p 替代 |
| `src/renderer_2d/map_data_2d.gd` + `.tscn` | 地图合并逻辑移到 Rust |
| `src/renderer_2d/map_accumulator.gd` | 同上（多车累加） |
| `src/renderer_2d/chunk_data_2d.gd` | 同上（log-odds 存储） |
| `src/util/llm.gd` + `.tscn` | LLM 并入 Pleiades（task 16，含硬编码 API Key 一并移除） |

### 2.2 保留（改造）

| 文件 | 改造 |
|------|------|
| `src/renderer_2d/map_container_2d.gd` | 数据源从 `map_data_2d` 改为桥信号（PackedByteArray）；保留「全量 + 增量」两套渲染 |
| `src/renderer_2d/renderer_2d.gd` | 车辆 Sprite 生命周期不变，pose 来源改桥 |
| `src/event_bus/event_bus.gd` | 信号定义保留，发出方由 WebSocketClient 改为桥 |
| `src/control/input_handler.gd` / `auto_handler.gd` | 命令发送改调桥 handle（`send_manual` / `send_task_set`） |
| `src/ui/` `src/camera/` `src/app_state/` | 基本不动 |

### 2.3 新增

- `.gdextension` 注册文件（项目内）。
- `bin/` 目录放 `.so`。
- 桥接 GDScript：把桥信号转发到 `EventBus`（或让组件直接 connect 桥），二选一，建议前者以最小化现有组件改动。

---

## 3. 合并 / 构建 / 部署

### 3.1 Rust 编译成什么

```
cargo build --release   →   target/release/libpictor_kernel.so   (Linux cdylib)
```

一个 `.so`，就是整个「逻辑层 + 桥」。

### 3.2 `.gdextension` 注册文件

INI 格式（入口符号名在 P0 时核实）：

```ini
[configuration]
entry_symbol = "pictor_kernel_init"
compatibility_minimum = "4.2"

[libraries]
linux.debug.x86_64 = "res://bin/libpictor_kernel.so"
linux.release.x86_64 = "res://bin/libpictor_kernel.so"
```

### 3.3 文件放置

```
Pictor/                         ← Godot 项目根
├── project.godot
├── pictor_kernel.gdextension   ← 注册文件（res:// 内任意位置，建议放根）
├── bin/
│   └── libpictor_kernel.so     ← Rust 编译产物
├── src/ ...                    ← Godot 场景 / 脚本
└── docs/ ...
```

Godot 启动时自动扫描 `.gdextension` 文件并加载对应 `.so`，桥即可用。

### 3.4 构建流程（`build.sh`）

```bash
# 1. 编译桥 crate（在 Orion 仓库内）
cargo build --release -p pictor-kernel
# 2. 拷贝产物到 Godot 项目
cp target/release/libpictor_kernel.so <Pictor>/bin/
# 3. 启动 Godot（自动加载 .gdextension）
```

### 3.5 桥在 Godot 里的形态

Rust 类（如 `PleiadesKernel`，extends Node）在 GDScript 里可直接实例化使用：

- **信号（上行，Rust → Godot）**：`pose_received` / `map_updated` / `peer_connected` / `peer_disconnected` / `cmd_result`
- **方法 / handle（下行，Godot → Rust）**：`send_manual(peer_id, action)` / `send_task_set(members, missions)` / `get_peers()`
- **线程**：后台 tokio 线程随桥初始化拉起，随桥销毁而退出

---

## 4. 分阶段（对应 task_23 P0–P4）

| 阶段 | 内容 | 验证 |
|------|------|------|
| P0 | 桥骨架：cdylib + tokio + swarm + 订阅 pose 打日志 | headless 打印车端 pose |
| P1 | 抽内核 crate + 无头模式 | 车端 / 终端共用编译通过 |
| P2 | 桥 API：信号 + handle | Godot 显示真实 pose |
| P3 | Godot 拆 WebSocket 栈 + 切桥 | 群发 Goto 跑通 |
| P4 | e2e + 断线重连验证 | 拔网线 → 自动恢复 |

---

## 5. 待核实（P0 时确认）

- gdext（godot crate）精确版本号（task 17 记 `0.5.4`，需再核实是否匹配 4.7.1）。
- `.gdextension` 的 `entry_symbol` 确切命名（gdext 宏自动生成，需确认）。
- 桥 crate 放哪：Orion workspace 成员 vs Pictor `rust/` 子目录（需定）。
- 命令 request-response 的 `DataType` 扩展方式（加新变体 vs 复用现有 Command）。
