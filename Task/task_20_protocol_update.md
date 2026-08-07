# Task 20: Protocol Update

## 目标

将 Pictor 现有 WebSocket 协议（JSON 文本帧 + 二进制 map_full）迁移为 **Orion 统一通信协议**（MAVLink 风格帧 + ORION_ 自定义消息）。规范文档：`docs/orion_protocol.md`。

## 设计决策（2026-08-07 与用户确认）

| 项 | 决定 |
|------|------|
| 传输层 | **WS 直接跑 Orion 二进制帧**（put_packet(encode_frame(...))），不做 JSON 包帧 |
| hello | **过渡期保留 JSON hello 帧**（Orion 无此消息，vehicle_registered 机制原样保留） |
| cmd_send 信号 | **保留 Dictionary 签名**（websocket_manager 内部做 Dict → Orion 帧翻译，下游 3 个调用点零改动） |
| 状态编码 | **内部存储统一 0/100/255**（0=free/100=occupied/255=unknown），存量 chunk .tres 资源迁移 |
| auto 语义 | **LLM 多指令聚合为一条 TASK_SET 整体下发**（整体替换语义） |
| sysid | **固定 200**（过渡期，无 libp2p peer_id）；compid 车=1 / 终端=200 |
| 互通范围 | Pictor + test_ws_server 已改；Rust 小车端已同步切换新协议，且开机默认 AUTO 模式 ✅ |
| yaw | 顺时针为正，与现有 vehicle_2d yaw_offset=-PI/2 约定一致，无需改动（需回归验证） |
| time_boot_ms | `Time.get_ticks_msec()`（仅模拟小车侧 test_ws_server 填写） |

## 子任务

- [x] 1. 新建 `orion_frame.gd` — 帧编解码（magic 0x4F + len u32 BE + seq 0 + sysid + compid + msgid u16 BE + payload + checksum 0）✅ 2026-08-07
- [x] 2. 新建 `orion_messages.gd` — 5 种消息 payload 编解码（POSE/MAP_FULL/MAP_DELTA/MANUAL_CONTROL/TASK_SET）✅ 2026-08-07
- [x] 3. 重写 `protocol_def.gd` — Orion 常量（msgid/action 枚举 0-9/mission type/cell 状态 0/100/255）✅ 2026-08-07
- [x] 4. 改造 `message_builder.gd` — Dict → Orion payload（保留 build_* 接口 + build_task_set + build_from_llm）✅ 2026-08-07
- [x] 5. 改造 `message_parser.gd` — 帧解析 + 按 msgid 分发（5 种消息全支持）✅ 2026-08-07
- [x] 6. 适配 `websocket_client.gd` / `websocket_manager.gd` — 二进制帧收发 + hello 门控保留 ✅ 2026-08-07
- [x] 7. 状态编码统一 0/100/255：`map_container_2d.gd` 渲染判断 + 3 处 DEBUG 统计 + 存量 .tres 迁移 ✅ 2026-08-07
- [x] 8. 改造 `test_ws_server.gd` — 新协议小车侧参考实现（含 TASK_SET 队列替换语义、task 自动切 AUTO 模式）✅ 2026-08-07
- [x] 9. auto_handler 聚合 LLM 多指令为一条 TASK_SET ✅ 2026-08-07
- [x] 10. 端到端验证（hello/map_full/manual/task_set/cancel 全链路）✅ 2026-08-07

## 验证结果（2026-08-07）

- **单元测试** `src/test/test_orion_protocol.gd`：8/8 PASS（帧编解码/大端/错误路径/5 消息 roundtrip/build_cmd/parser 分发）
- **端到端测试** `src/test/test_e2e_orion.gd`：PASS（hello → map_full 100-encoding → manual 移动 → TASK_SET 队列逐任务执行 → cancel 停车）
- **主场景冒烟**：headless 60 帧无脚本错误
- 用法：`godot --headless -s src/test/test_orion_protocol.gd` / `-s src/test/test_e2e_orion.gd`

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/websocket/protocol/orion_frame.gd` | ✅ 新建 | 帧编解码 |
| `src/websocket/protocol/orion_messages.gd` | ✅ 新建 | 消息 payload 编解码 + Build_Cmd |
| `src/websocket/protocol/protocol_def.gd` | ✅ 重写 | Orion 常量 |
| `src/websocket/protocol/message_builder.gd` | ✅ 改造 | Orion Dict 构造（build_* 接口兼容） |
| `src/websocket/protocol/message_parser.gd` | ✅ 改造 | 帧解析分发（5 消息） |
| `src/websocket/websocket_client.gd` | ✅ 适配 | send_binary + _match_orion_msg + hello 门控 |
| `src/websocket/websocket_manager.gd` | ✅ 适配 | Build_Cmd 编码发送 |
| `src/renderer_2d/map_container_2d.gd` | ✅ 修改 | 状态判断 0/100/255 |
| `src/renderer_2d/map_data_2d.gd` / `renderer_2d.gd` | ✅ 修改 | DEBUG 统计 0/100/255 |
| `src/renderer_2d/chunk_data_2d.gd` | ✅ 修改 | 注释更新 |
| `Assets/2D/map_chunk_0_0.tres` | ✅ 迁移 | cells 0/1/2 → 0/100/255（脚本执行） |
| `src/test/test_ws_server.gd` | ✅ 改造 | 新协议参考实现 |
| `src/control/auto_handler.gd` | ✅ 修改 | LLM 指令聚合 TASK_SET |
| `src/test/test_orion_protocol.gd` | ✅ 新建 | 协议单元测试 |
| `src/test/test_e2e_orion.gd` | ✅ 新建 | 端到端测试 |

## 遗留事项

- ~~Rust 小车端尚未切换新协议~~ ✅ 已同步（2026-08-07 用户确认：Rust 端协议已切换 + 开机默认 AUTO）
- `test_ws_server.gd` 中 `"[" + vehicle_id + "]"` 拼接风格与项目其他文件不一致（功能正确）
- 旧 JSON pose/map_delta 消息现在被忽略（日志提示），旧协议小车无法连接
