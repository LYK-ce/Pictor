# wb_20_protocol_update

开始时间: 2026-08-07

## 任务
task_20_protocol_update：将 Pictor 现有 WebSocket 协议（JSON + 二进制 map_full）修改为 Orion 统一协议风格（MAVLink 风格帧 + 自定义 ORION_ 消息）。规范文档：`docs/orion_protocol.md`（2026-08-07 自 Workspace/Orion/docs/design_doc 复制）。

## 分析结论（2026-08-07 子 agent）
- 核心改动：`src/websocket/` 协议层（protocol_def/message_builder/message_parser + 新建 orion_frame.gd/orion_messages.gd）+ `test_ws_server.gd` + 渲染层状态常量（map_container_2d 是唯一语义判断点）
- EventBus 信号签名若保留 Dict/Array，下游（renderer_2d/vehicle_panel/camera/auto_handler）几乎零改动
- 关键决策点：①传输层（WS 直跑 Orion 帧 vs JSON 包帧）②hello 保留方式 ③cmd_send 签名 ④状态编码 0/1/2→0/100/255 内部统一 ⑤auto 追加→TASK_SET 替换语义冲突（LLM 多指令互覆）⑥sysid 固定值 ⑦Rust 端同步
- 状态编码影响：map_container_2d.gd / map_data_2d.gd / renderer_2d.gd / websocket_client.gd / test_ws_server.gd + 存量 chunk .tres 资源
## 决策（2026-08-07 用户确认）
- 传输层：WS 直接跑 Orion 二进制帧（路线 A）
- hello：过渡期保留 JSON hello 帧（用户："当前保留了hello帧，你不用担心"）
- cmd_send：保留 Dictionary 签名（manager 内部转帧）
- 状态编码：内部统一 0/100/255
- auto：LLM 多指令聚合为一条 TASK_SET（整体替换）
- sysid 固定 200；只改 Pictor + test_ws_server（Rust 端后续）
- yaw 约定一致无需改；time_boot_ms 用 Time.get_ticks_msec()
## 实施完成（2026-08-07）
- 阶段 1-4 全部完成：orion_frame/orion_messages/protocol_def 新建重写，builder/parser/client/manager 改造，状态编码统一+资源迁移，test_ws_server 全链路 Orion 化，auto_handler 聚合
- 验证：单元测试 8/8 PASS；端到端 PASS（hello/map_full/manual/task_set 队列/cancel）；主场景 headless 冒烟无错
- 过程中发现并修复：①客户端 inbound_buffer 默认 64KB < map_full 帧 65.5KB 会断连（Pictor websocket_client 已设 4MB，测试脚本需同样设置）②TASK_SET 需将车切回 AUTO 模式才执行队列 ③parser match 分支顺序（manual/task_set 曾误插在 `_` 后）
- 测试脚本正式存放：src/test/test_orion_protocol.gd（单元）、src/test/test_e2e_orion.gd（端到端）
## 阶段
1. [进行中] 子 agent 代码阅读 → 确定改动清单 → 与用户讨论
2. [ ] 实施
3. [ ] 验证
