# 规则文件

agent必须严格遵守以下规则



# 思考模式
1. agent必须用中文进行思考

# 代码规范
## 归属规范
每一份代码文件必须在开头添加以下注释,注释规范应当严格对应当前语言：
'''
Presented by KeJi
Date ： Current date
'''
## 命名规范
1. 变量 采用lower snake case规范进行命名
2. 函数 采用Pascal snake case规范进行命名
3. 常数 采用Upper snake case规范进行命名

## Godot 规范
1. 场景引用使用 `@export var xxx_scene: PackedScene`，禁止在 `.gd` 中硬编码 `load("res://...")` 路径
2. 子节点引用使用 `@onready var xxx := $NodeName`，禁止使用绝对路径 `get_node("/root/...")` 访问
   - 例外：`EventBus` 是 Autoload，允许 `get_node("/root/EventBus")`
3. 组件间通信通过 `EventBus` 信号，禁止组件间直接调用方法

# 工作流程

## 目录结构
- `Task/` — 当前待执行/进行中的任务文件
  - `archived task/` — 已完成的任务归档
- `Workbook/` — 工作记录（命名格式 `wb_{id}_{description}.md`）
- `docs/` — 设计文档、说明文档

## 任务文件规范
每个任务文件命名格式：`task_{id}_{description}.md`，存储在 `Task/` 目录下。
- 例如：`Task/task_6_session_manager.md`
- 已完成的任务移入 `Task/archived task/`
- agent 只有在人类同意的情况下才能对任务文件进行修改。

## Workbook 规范
Workbook 目录中的工作记录文件与任务文件一一对应，命名方式为 `wb_{id}_{description}.md`（与 `task_{id}_{description}.md` 共享相同的 id 和 description）。用于 agent 记录工作进度，作为工作上下文。agent 在完成每一项任务后必须记录必要信息和重要细节。若文件不存在，agent 应创建一个。采用最高效、最精简的记录方式，无需考虑人类可读性。确保若启动新的 agent，其可基于现有 workbook 文件快速切换至当前工作上下文。

## Agent 工作流程
1. 阅读 `Task/` 目录下的任务文件，根据完成情况和人类评审意见决定下一项任务
2. 更新对应 workbook，记录任务开始时间
3. 根据人类的要求执行特定任务
4. 更新 workbook，记录依赖关系、结束时间，使用最精简的方式记录必要信息
5. 若任务完成，将任务文件移入 `Task/archived task/`
6. 结束任务







# 核心架构原则

## Core 主循环设计原则

Core 的 `tokio::select!` 主循环（5 个 branch）**必须是纯路由层**：

- **只做匹配 + spawn**：每个 branch 只负责识别事件类型并分发，不得在此执行任何业务逻辑或 I/O 操作。
- **毫秒级返回**：任何可能阻塞的操作（文件 I/O、网络传输、模型加载等）必须通过 `tokio::spawn`（或 `std::thread::spawn`）异步化。
- **锁的持有时间最短**：若需持有 `Mutex`，只在 HashMap 插入/删除等瞬时操作期间持有，不得在持有锁期间做 I/O。

```rust
// ✅ 正确：主循环只做路由
UserCommand::Session { model_id } => {
    let session_mgr = self.session_mgr.clone();
    tokio::spawn(async move {
        let id = session_mgr.lock().unwrap().create_session(&model_id);
        // ...
    });
}

// ✅ 正确：Stream 接收也 spawn 出去
Network_Inbound_Event::FileStreamArrived { peer, stream } => {
    let caps = self.capabilities.clone();
    tokio::spawn(async move {
        // 文件接收的全部 I/O 在这里
    });
}

// ❌ 错误：在主循环内做网络 I/O
Network_Inbound_Event::FileStreamArrived { peer, mut stream } => {
    Read_File_Stream_Header(&mut stream).await;   // 阻塞主循环！
}
```

# 初始化

Agent 在首次启动时必须执行以下初始化步骤：

0. **阅读架构文档** — 读取 `Architecture/architecture.md`，理解项目整体架构、各模块职责以及关键接口。
