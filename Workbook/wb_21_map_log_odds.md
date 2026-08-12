# wb_21_map_log_odds

## 2026-08-11

- 创建 task_21（讨论中）。
- 已阅读车端设计文档 `Workspace/Orion/docs/design_doc/multi_robot_map.md` 并复制到 `docs/multi_robot_map.md`。
- Pictor 侧影响面分析（对照源码）：改动链路 = 解析层（protocol_def / orion_messages）→ 数据层（map_data_2d / chunk_data_2d）→ 渲染层（map_container_2d）+ 测试。结构利好：CHUNK_SIZE=256 ⇒ 1 chunk = 65536 格 = 整图 = log-odds 缓冲表，无需新增数据结构，纯语义转换。

## 2026-08-11 用户澄清（范围确认）

- 车端三步**全部完成**（已核实代码：grid.rs update() 返回 Option<(bool,u8,i8)>、Delta/MapDelta/MapDeltaEntry 全 delta:i8、lidar_mapper 收集、server.rs+grid.rs 含 log_odds_bytes）。① grid.rs 存储改造（update() 返回 Δ，own 复用 Chunk，log_odds_bytes/from_log_odds_bytes 导入导出，三态读时派生）；② Δ 三层传导 + 5 帧聚合模 5=1s 节流（Δ≠0/净 0 不发，接收方 clamp ±8）；③ WS full map 复用 msgid=2 换 log-odds（连接时一次）。
- **多车对账未做，不在本任务范围**。本任务 = 单车协议语义替换（§6.7 清单）：本地 log-odds 缓冲表 + FULL 初始化 + DELTA += Δ clamp ±8 + 显示阈值 ±6 派生。
- 我此前提的 4 个问题中：对账职责/多车×单图 → 推迟；同批发布节奏 → 仍需确认车端完成时间点；D* Unknown → 与本任务无关。
- 待确认实施细节：DELTA 有符号解释（byte>127→−256）、test_ws_server 模拟器先行升级、测试字节级断言更新。

## 2026-08-11 子 agent 调研完成（修改方案定稿）

- 车端语义核实（代码级）：clamp ±8 / 阈值 ±6 严格 / Δ=i8 位模式直传无符号位特殊处理 / 聚合不预 clamp 接收方先加后 clamp（单条 Δ 可超 ±8）/ FULL=own 表连接时一次 / DELTA 1Hz Δ≠0 才发 / 255 不再是 Unknown 标记 / hello 门控不影响地图。
- 修改清单：12 源码/资源文件 + 4 文档。关键发现：① 存量 map_chunk_0_0.tres 含 0/100 非法数据需重新生成；② get_cell 返回 i8 无外部调用者（安全）；③ 0/100/255 残留 7 处需逐处排查；④ cells_changed 载荷 state→log_odds；⑤ message_builder 零改动。
- 实施顺序：常量→协议层→数据层→渲染层→测试资源→模拟车端→单元/e2e→文档→验证。
- task_21 已更新为完整实施蓝图（13 个子任务）。

## 2026-08-11 实施完成（13/13 子任务）

- 全部代码改动落地：protocol_def（LOG_ODDS_CLAMP/THRESHOLD）、chunk_data_2d（to_i8/to_u8/to_state）、orion_messages（delta i8 位模式编解码）、map_data_2d（FULL 防御 clamp 初始化 + DELTA 累加先加后 clamp + get_cell i8 + 删 _dict_to_packed）、map_container_2d（阈值 ±6 派生）、两处 DEBUG 统计、test_ws_server（确定性图 + 1Hz DELTA 聚合模拟，覆盖 Δ=+15 场景）、gen_chunk_0_0（确定性图）、map_chunk_0_0.tres 重新生成（值域 {0,8,248} 验证）。
- 测试：单元 13/13 PASS（新增 signed/clamp/threshold）；e2e PASS（map_full log-odds wall + delta 到达 max|Δ|=15）；主场景 headless 90 帧冒烟无脚本错误。
- 文档：orion_protocol.md（§3 频率/§3.2/§3.3 + 同批发布警告）、websocket_protocol.md（废弃头注）、multi_robot_map.md（§6.7 已实施标注）。
- 遗留：与车端真机联调 ⬜（待车端 WS 可用）；task_21 待归档（需人类确认）。
