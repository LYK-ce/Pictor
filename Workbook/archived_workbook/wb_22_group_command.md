# wb_22_group_command

## meta
- task: task_22_group_command
- start: 2026-08-12
- end: 2026-08-15
- status: done (archived 2026-08-15)

## 方案
- 全部统一多车命令：单车 = member_count=1；取消 = member_count=0
- cmd_send(targets: Array[String], cmd)；members 由 WebSocketManager 查 _peer_ids 表填
- hello peer_id：client 解析 → manager 内部 _peer_ids 表（不上 AppState，唯一消费者是 manager）
- LLM 链路对选中车群发（与右键 Goto 一致）
- 同批升级无过渡期（Orion task_14）

## 进度

### 2026-08-12 实施完成 ✅
- Step 1: hello peer_id（websocket_client 解析 _peer_id + getter；manager _peer_ids 表注册/注销维护；test_ws_server 派生假 peer_id）
- Step 2: Encode/Decode_Task_Set 新布局（mission_count + member_count + members[] + missions[]），越界防御；test_orion_protocol 重写（16/16 PASS）
- Step 3: cmd_send(targets: Array[String], cmd)；调用点 ×5 适配；manager 统一填 members（取消帧 missions 空 → member_count=0）
- Step 4/5: auto_handler 右键 Goto + LLM 均改单条群发帧（selected_ids）
- Step 6: e2e_multivehicle 加 GROUP/SINGLE 阶段（群发双车收到 ✓；单车非成员忽略 ✓）全 PASS
- Step 7: docs/orion_protocol.md §1.5 hello peer_id 字段表 + §3.5 新布局/三分支/同批升级

## 评审（2026-08-15 通过）
- 代码核验：Step 1-7 与任务书一致（hello peer_id / Encode·Decode_Task_Set / cmd_send(targets) / 右键 Goto+LLM 群发 / members 下沉 manager）
- 测试全绿：协议单测 16/16 PASS；e2e_multivehicle（群发双车收到 + 单车非成员忽略）PASS；e2e_orion（hello→map→manual→task_set→cancel）PASS
- 文档：docs/orion_protocol.md §1.5 / §3.5 已同步（§3.5 标题存在重复，小瑕疵）
- 遗留（不阻塞）：_Peer_Id_Bytes 查不到 peer_id 时仍插入 len=0 空成员（建议改跳过）；websocket_client.gd 文件头 Present 拼写

## 踩坑
- `Array[String]([x])` 构造语法在 GDScript 4.7 **不支持**（Parse Error）→ 用 `[x] as Array[String]`
- 信号类型化参数 Array[String] 对未类型化 Array 字面量严格（Cannot convert）→ 所有 emit 用 as 转换
- `[x]` 字面量是未类型化 Array，manager 接收 `_vehicles.get(id)` key 必须 String
- transform 引擎 occurrence:all 只替换首个匹配 → 残留检查用 grep 兜底
