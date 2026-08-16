# wb_23_pleiades_integration

## meta
- task: task_23_pleiades_integration
- start: 2026-08-15
- end: 2026-08-16
- status: done（已归档）

## 目标
- Pleiades（无头）作为 Pictor 逻辑内核，GDExtension 桥，Godot 纯表现，移除 WebSocket

## 最终架构（定稿 + 已实施）
- 桥 = 哑管道：不解析/不合并业务数据，只透传 robot_bus 原始帧（robot_frame）+ event_bus peer 事件（peer_*）
- 7 信号：kernel_ready / robot_frame / peer_discovered / peer_left / peer_connected / peer_disconnected / peer_info_updated
- 2 方法：send_command(peer_id_hex, frame) / poll()
- peer_id 统一 hex（桥内 base58_to_hex）
- Godot 新增 KernelBridge 适配器：挂 PleiadesKernel、每帧 poll()、信号翻译、cmd_send 下行路由
- 地图：单表、MAP_FULL=替换(set_full)、MAP_DELTA=累加(set_delta)；多车合并+返还合并全量 暂缓
- 车辆生命周期：peer_connected→vehicle_registered（建 Sprite/面板）；peer_disconnected→vehicle_unregistered；peer_left/peer_discovered 不消费
- 面板：vehicle_id 与显示名分离（「连接中」→车名），Disconnect 按钮删除

## 8 条决策（详见 task「待决策问题」）
1 hex 统一 / 2 地图原始帧透传 / 3 WS 连接层移除（protocol/ 保留） / 4 kernel_ready 门控不做 / 5 poll 背压后置 / 6 peer 事件驱动 / 7 面板 UI / 8 e2e 测试删除 + LLM/STT 暂缓

## 实施结果（2026-08-16）
- P0/P1/P2（Rust 桥）Rust 侧完成；P3（Godot 切桥）完成
- Linux headless 验证通过；Windows 真机测试通过（用户验证）
- 踩坑：Windows .dll 依赖 CUDA（pleiades 默认 cuda feature 链 curand64_10.dll=CUDA10，与本机 12.8 不匹配 → Error 126）；关 cuda feature（default-features=false）重编解决
- .gdextension 移到项目根 res://pictor_kernel.gdextension（含 linux+windows 条目）；二进制放 kernel_test/bin/（gitignore）
- .godot/extension_list.cfg 缓存需指向 .gdextension 正确路径（否则「PleiadesKernel 类未注册」）

## 关键文件
- 新增：src/kernel/kernel_bridge.gd、src/ui/WebSocket/vehicle_panel_manager.tscn
- 删除：websocket_manager/client/menu/creation_menu、test_ws_server、test_e2e_multivehicle、test_e2e_orion
- 修改：event_bus（去 url/删 ws_*/map_merged/+peer_info_updated）、message_parser（透传 sysid）、map_data_2d（set_full 替换）、renderer_2d、vehicle_panel_manager、vehicle_panel、main.tscn、project.godot
- docs：pictor_pleiades_integration / bridge_integration_plan / design_review / project_code_overview

## 遗留（后置）
- P4 e2e + 断线重连验证（真车/模拟节点到位再验）
- 多车地图合并 + 返还合并全量（暂缓）
- LLM/STT 归属（llm.gd 现状保留，后续 task 迁 Rust 逻辑层）
- Rust 契约文档 pictor_bridge_sync.md 的 kernel_ready 门控表述与决策 #4 冲突，待同步
