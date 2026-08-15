# Task 23: Pleiades 集成（逻辑与表现分离）

> 创建日期：2026-08-15
> 状态：🟡 方案已定稿，待实施
> 前身：task_23_websocket_reconnect（已重定向——WebSocket 重连方案作废）

---

## 背景

真实部署中，车端 Wi-Fi 漫游（AP 切换）会触发 NetworkManager 重新激活接口 + 重跑 DHCP，导致 L3 地址被摘、**所有 TCP 连接被杀**（SSH / WebSocket / VNC 实测均断，`journalctl` 日志实锤）。

而车端已有的 **libp2p P2P 网络**（`Orion/`，libp2p 0.56 + tcp + mdns）在同样漫游中**不断线**——`swarm_events.rs` 里 mDNS 发现后自动 `dial` 重连。

**结论**：与其给 Pictor 的 WebSocket 打重连补丁，不如让 Pictor 直接接入已有的、天生抗断的 libp2p 网络，并彻底移除 WebSocket。

## 方案定稿

**架构原则：逻辑与表现分离。** Pleiades（无头模式）= 逻辑层（网络 / 协议 / 地图合并 / LLM / STT），Godot = 表现层（渲染 / UI / 输入），中间一个 GDExtension 桥。

```
Godot 进程（单进程）
├── Godot 表现层（帧循环）  ◄── 信号 / handle ──►  Pleiades 逻辑层（后台 tokio）
│   渲染 / UI / 相机 / 输入                          ├── libp2p swarm（mDNS 自动发现加入）
└──────────────────────────────────────────────────┘── gossipsub / request-response
                                                       └── 车们 (orion-robot)
```

详见 `docs/pictor_pleiades_integration.md`。

## 设计决策记录

| 决策 | 结论 |
|------|------|
| 通信方式 | ✅ 纯 libp2p，**移除 WebSocket**（车端 `WebSocket/server.rs` 退役，Godot `websocket/` 整套删除） |
| 进程模型 | ✅ GDExtension 内嵌（单进程多线程；Pleiades 跑后台 tokio 线程） |
| 无头模式 | ✅ Pleiades 不启动 TUI（`Src/TUI/` 独立模块），状态由桥导出 |
| 嵌入范围 | ✅ 保留全部功能（ML/API/VM 照常），仅无头化（不启动 TUI） |
| 桥：下行（命令） | ✅ handle（一组方法）→ request-response 单播到指定 peer_id |
| 桥：上行（数据/事件） | ✅ Rust EventBus → 桥订阅 → sync_to_main_thread → Godot 信号 → GDScript connect |
| 地图数据 | ✅ Rust 权威（合并+存储）+ Godot 渲染副本（只读 PackedByteArray） |
| 跨桥数据格式 | ✅ 全走信号：地图 PackedByteArray / 位姿 Dictionary，不需共享内存 |
| Godot 版本 | ✅ 4.7.1 + gdext 对应版本（task 17 已调研 godot crate 0.5.4） |

## 实施步骤（依赖顺序）

- [ ] **P0** GDExtension 骨架：起 tokio + swarm，订阅 pose 打日志（验证：headless 打印车端 pose）
- [ ] **P1** Pleiades 无头模式（不启动 TUI，保留 ML/API/VM）+ 桥 crate 骨架（验证：车端/终端共用编译通过）
- [ ] **P2** 桥 API：pose/map 信号 + 命令 handle + peer 事件（验证：Godot 显示真实车 pose）
- [ ] **P3** Godot 拆除 WebSocket 栈，切换到桥（验证：群发 Goto 跑通）
- [ ] **P4** e2e + 断线重连验证（验证：拔网线 → 自动恢复）

## 涉及文件

**Rust 侧（Orion 仓库，`/Workspace/Orion/`，不在 Pictor 工作区）**：
- 加无头模式（不启动 TUI）/ 命令 request-response 路由（复用 `parse_orion_frame` + `robot_cmd_tx`）/ 新增桥 crate / `WebSocket/server.rs` 退役

**Godot 侧（Pictor）**：
- 删：`src/websocket/` 整套（client / manager / protocol）
- 删：`src/renderer_2d/map_data_2d.gd` / `map_accumulator.gd` / `chunk_data_2d.gd`（逻辑移走）
- 保留：`renderer_2d`（渲染）、`ui/`、`control/`、`camera/`、`event_bus.gd`（改由桥发信号）
- 新增：GDExtension 桥（Rust cdylib + `.gdextension` 注册）

## 依赖

- 车端 orion-robot：数据路径已就绪（mDNS + gossipsub）；命令路径需加 request-response 接收路由
- task 17（STT）/ task 16（LLM）：并入逻辑层，与桥共用 GDExtension 脚手架
- 多车地图一致性（CRDT 调研）：与"地图合并放 Rust"耦合，需确认 scope

## 待办

- [x] 架构收敛（逻辑/表现分离 + 移除 WS）
- [x] 设计文档 `docs/pictor_pleiades_integration.md`
- [ ] P0-P4 实施
