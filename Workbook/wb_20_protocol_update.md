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
## 字节序修复（2026-08-07，真实小车联调发现）
- 现象：`len mismatch: header=335544576 actual=65556` / `header=402653184 actual=24`
- 根因：**Pictor 端字节序错误**——Godot PackedByteArray 的 encode_u32/decode_u32/decode_float 等原生 API 均为小端，而 Orion 协议 §2 规定全大端；Rust 端发送标准大端符合协议
- 修复：orion_frame.gd 新增 Read_U16/S16/U32/S32/F32_BE + Write_* 大端 helper（float 用 encode_float 小端写+反转），帧编解码与 orion_messages.gd 全部替换为 BE helper
- 影响面：上行（pose/map_full/map_delta 解析）+ 下行（manual_control/task_set 编码）全部覆盖
- 验证：单元测试新增 endianness 断言（len [00 00 00 05]、65556 Rust 帧、f32 1.5→[3F C0 00 00]、i16 -50→[FF CE] 等）9/9 PASS；端到端 PASS
## Code review 修复（2026-08-07）
- 🔴-1 LLM mission type：字符串 "goto" → 0 归一化（build_task_set + Encode_Task_Set 双层防御），LLM 自然语言指令可正常下发
- 🔴-2 TASK_SET 语义：模拟端对齐 Rust robot.rs（Manual 忽略 Auto 命令）；**车开机默认 AUTO**（Rust 端 mode.rs 已改，用户 2026-08-07 确认）
- 🔴-3 指令顺序：auto_handler 全 goto 才聚合为一条 TASK_SET，混合指令按 LLM 原始顺序逐条下发
- 🟡 mode 未知 action 拒绝下发；task_set/map_delta count 钳制（255/65535）；beep 映射已存在（review 误报）
- 测试：单元 10/10 PASS（新增 llm_string_type：字符串 type + 混合指令顺序）；e2e PASS（新增队列顺序断言 m1→m2 + Manual 忽略语义适配）；主场景冒烟 0 错误
- 提交：fca3225（已推送）
## LLM 任务序列语义对齐（2026-08-07，用户决策后实施）
- 线上格式确认：TASK_SET 帧（count u8 + 每项 type u8 + x/y f32 BE），无 push/cancel 概念；count=0 取消
- llm.gd SYSTEM_PROMPT：改为只输出 missions JSON 数组（方案 A），删除 manual/mode/push/cancel 旧格式
- 删除 MessageBuilder.build_from_llm（旧格式解析，无调用点）
- auto_handler：LLM missions 数组 → 全部任务合并为一条 TASK_SET 广播
- 取消（count=0）由 UI 显式触发——当前无此功能，不做（用户指示）
- 测试：llm_string_type → llm_missions（含与 Rust 字节比对 3.0→40400000）
## 阶段
1. [进行中] 子 agent 代码阅读 → 确定改动清单 → 与用户讨论
2. [ ] 实施
3. [ ] 验证
