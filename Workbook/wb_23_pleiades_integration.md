# wb_23_pleiades_integration

## meta
- task: task_23_pleiades_integration
- start: 2026-08-15
- end:
- status: in-progress

## 目标
- Pleiades（无头）作为 Pictor 逻辑内核，GDExtension 桥，Godot 纯表现，移除 WebSocket

## 方案要点
- 命令：request-response 单播（handle 下行）
- 数据/事件：Rust EventBus → sync_to_main_thread → Godot 信号（上行）
- 地图：Rust 权威 + Godot 渲染副本（只读）
- 全走信号（PackedByteArray/Dictionary），不需共享内存
- Godot 4.7.1 + gdext（task17 已调研 0.5.4）

## 背景（故障根因）
- 车端漫游 + DHCP 重启 → L3 拆 → TCP 杀（SSH/WS/VNC 实测断）；libp2p mDNS+dial 抗断
