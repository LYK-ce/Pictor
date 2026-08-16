# wb_24_circle_command

开始时间: 2026-08-16（实施）/ 2026-08-16（完成）

## 任务
task_24_circle_command：Pictor 新增 Circle 命令下发（type=1，环形散布）。触发：Z 键待命 + 左键点圆心；群发给 selected_ids，复用 Goto 全链路。车端 Orion task_18 已实施（MISSION_CIRCLE=1 车端已识别）。

## 实现（2026-08-16 完成，单测 + 冒烟通过）
- 协议常量：`protocol_def.gd` 加 `MISSION_TYPE_CIRCLE := 1` + `Mission_Type_From(t)`（"goto"→0/"circle"→1/未知→0，大小写不敏感）
- 构造器：`message_builder.gd` 加 `build_auto_push_circle(x, y)`；`_Normalize_Mission_Type` 委托 `ProtocolDef.Mission_Type_From`
- 编码：`orion_messages.gd` `Encode_Task_Set` 字符串 type 归一化改走 `Mission_Type_From`
- 触发：`auto_handler.gd` `PendingAction` 加 `CIRCLE`；`_unhandled_input` 加键盘分支（KEY_Z 置位 / KEY_ESCAPE 取消）；`_execute_pending` 实现（game_to_tile→tile_to_real→build_auto_push_circle→cmd_send(selected_ids)+goto_issued 高亮）
- LLM：`llm.gd` SYSTEM_PROMPT 加 `{"type":"circle","x":圆心x,"y":圆心y}`
- 单测：`test_orion_protocol.gd` 加 `_test_circle_task_set`（归一化/build/roundtrip/字符串归一化）

## 关键决策
- 触发键 Z（弃用 A：input_handler `KEY_A:spin_left` 被手动占用）
- 半径 0.5m 车端写死，不进协议；Pictor 只发 type=1 + 圆心
- 高亮复用 `goto_issued`，不新增信号
- 下游（KernelBridge 填 members / Build_Cmd / send_command）零改动
- 归一化集中到 ProtocolDef.Mission_Type_From，避免 message_builder/orion_messages 两处漂移

## 验证
- 单测 `godot --headless --path . -s src/test/test_orion_protocol.gd`：ALL PASS: true（含 PASS circle_task_set，17 项）
- 冒烟 `godot --headless --path . --quit-after 90 src/main/main.tscn`：`[Main] ready: 7 children` 无脚本错误（renderer_2d.tscn UID 警告为存量）

## 文档
- `docs/orion_protocol.md` §3.5：type 加 1=Circle + x/y 圆心语义 + Circle 注记 + 三分支「第一个 Goto 或 Circle」+ 修重复标题
- `Architecture/architecture.md`：整篇重写对齐 KernelBridge + Orion + Circle 现状

## 依赖
- 车端 Orion task_18（已实施，MISSION_CIRCLE=1）。type=1 纯新增，无同批升级压力。
- 遗留：实车联调（4 车围圈）待真车可用时执行。

结束时间: 2026-08-16
