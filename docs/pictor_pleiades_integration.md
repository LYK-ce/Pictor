# Pictor × Pleiades 集成设计（逻辑与表现分离）

> 创建日期：2026-08-15
> 状态：🟡 草案（架构已收敛，待拍板边界问题）
> 前身：task_23（WebSocket 重连）—— 本方案使其作废

---

## 1. 背景与动机

真实部署中，车端 Wi-Fi 漫游（AP 切换）会触发 NetworkManager 重新激活接口 + 重跑 DHCP，导致 L3 地址被摘，**所有 TCP 连接被杀**（SSH / WebSocket / VNC 实测均断，`journalctl` 日志已实锤）。

而车端已有的 **libp2p P2P 网络**（`Orion/` Rust 项目，`libp2p 0.56 + tcp + mdns`）在同样的漫游中**不断线**——原因是 `swarm_events.rs` 里 mDNS 发现后自动 `dial` 重连：

```rust
mdns::Event::Discovered(peers) => {
    for (peer_id, addr) in peers {
        if peer_id != self.local_peer_id {
            self.swarm.behaviour_mut().kademlia.add_address(&peer_id, addr.clone());
            if let Err(e) = self.swarm.dial(addr.clone()) { /* 主动重拨 */ }
        }
    }
}
```

**结论**：与其给 Pictor 的 WebSocket 打重连补丁（task_23），不如让 Pictor 直接接入已有的、天生抗断的 libp2p 网络，并彻底移除 WebSocket。

---

## 2. 架构原则：逻辑与表现分离

类比游戏开发：**Pleiades = 游戏服务器（逻辑），Godot = 客户端（表现）**。两者通过一个薄薄的桥（GDExtension）通信，逻辑层完全不感知表现层的存在。

```
┌─────────────────────────────────────────────────────────┐
│                    Godot 进程（单进程）                    │
│                                                         │
│  ┌───────────────┐   信号 / 方法调用   ┌──────────────┐  │
│  │  Godot 表现层  │ ◄─────────────────► │ Pleiades 逻辑层│  │
│  │  (帧循环)      │   GDExtension 桥    │  (后台 tokio) │  │
│  └───────────────┘                     └──────┬───────┘  │
│   渲染/UI/相机/输入                           │ libp2p   │
└──────────────────────────────────────────────┼──────────┘
                                               │ mDNS/gossipsub
                                    ┌──────────┴──────────┐
                                    │ 车们 (orion-robot)   │
                                    │ mDNS 自动发现 + 加入 │
                                    └─────────────────────┘
```

---

## 3. 职责划分

### Pleiades（逻辑层）—— 全部网络逻辑

| 职责 | 现状 | 目标位置 |
|---|---|---|
| libp2p swarm / mDNS 自动发现加入 | ✅ 已实现（`Network/`） | 保持 |
| gossipsub pose/map 广播 | ✅ 已实现（`TOPIC_ROBOT_POSE/MAP`） | 保持 |
| peer_id 身份 + peer 管理 | ✅ 已实现（`PeerManagement/`） | 保持 |
| ORION 协议编解码 | ✅ 已实现（`Robot/core/protocol`） | 保持 |
| 多车地图一致性/合并 | ⏳ 调研中（CRDT 调研报告） | 放 Pleiades |
| LLM 指令解析 / STT 推理 | ⏳ task_16/17 | 放 Pleiades（有 ML 引擎） |

### Godot（表现层）—— 只负责呈现

| 职责 | 现状 |
|---|---|
| 2D 地图渲染（TileMapLayer，log-odds → tile） | `renderer_2d/` 保持 |
| 车辆 Sprite / 相机 / UI 面板 / 缩放 | 保持 |
| 输入（WASD / 鼠标 Goto / 文本框） | 保持，但产出的是"指令"，交桥下发给逻辑层 |

### 桥（GDExtension）—— 逻辑与表现的接缝

- **逻辑 → 表现**（事件/数据）：`pose_received` / `map_updated` / `peer_connected` / `peer_disconnected` / `cmd_result`
- **事件机制**：Rust 侧 `EventBus`（`Src/EventBus/`）发布 → 桥订阅 → `sync_to_main_thread` 排到主线程 → 发 Godot 信号 → GDScript `connect` 接收（与现有 `EventBus` Autoload 模式一致）
- **表现 → 逻辑**（命令/查询）：`send_manual(peer_id, action)` / `send_task_set(members, missions)` / `get_peers()`

---

## 4. 关键技术决策

| 决策 | 结论 |
|---|---|
| 通信方式 | ✅ 纯 libp2p，**移除 WebSocket**（车端 `WebSocket/server.rs` 遥控通道退役，Godot 侧 `websocket/` 整套删除） |
| 进程模型 | ✅ GDExtension **内嵌**（单进程多线程，无本地 IPC） |
| 无头模式 | ✅ Pleiades 增加无头模式：不启动 TUI（`Src/TUI/` 独立模块），状态改由桥导出 |
| 嵌入范围 | ✅ 保留全部功能（ML/API/VM 照常），仅无头化（不启动 TUI） |
| 线程模型 | ✅ 后台 `std::thread` 起 tokio runtime 跑 swarm；数据全走信号（地图 PackedByteArray / 位姿 Dictionary），事件经 `sync_to_main_thread` 排到主线程发信号 |
| 车端改动 | 数据路径零改动（gossipsub 已在广播）；命令路径新增 request-response 接收路由（复用 parse_orion_frame + robot_cmd_tx） |

---

## 5. 数据流

```
车 (orion-robot)
  └─ gossipsub 广播 pose/map ──► 终端 Pleiades swarm（后台 tokio）
                                    ├─ pose → 环形缓冲 → Godot _process 逐帧 drain → Sprite 更新
                                    ├─ map  → 同上 → TileMapLayer 重绘
                                    └─ peer 事件 → sync_to_main_thread 信号 → UI 面板
Godot 输入（WASD/Goto/文本）
  └─ 桥方法调用 ──► Pleiades ── libp2p ──► 车
```

- **上行（车→终端）**：gossipsub 广播，订阅即得，免费获得。
- **下行（终端→车）**：✅ 已定（2026-08-15 拍板）——request-response 单播。终端按 peer_id 单点发送命令，车端收到转 robot_cmd_tx。

---

## 6. 待拍板边界问题

1. **地图合并逻辑放哪**：`map_data_2d.gd` 的多车聚合（accumulate / log-odds 合并）是"逻辑"还是"表现"？倾向放 Pleiades（与车端 grid.rs 同构、配合 CRDT 调研），Godot 只做"log-odds → tile"的渲染。但这与"多车地图一致性"调研耦合，需确认 scope。
2. ~~**命令下发通道**~~ ✅ 已定：request-response 单播（2026-08-15 拍板）。在现有 request-response 协议加机器人控制命令类型，车端收到转 robot_cmd_tx。
3. **LLM/STT 归属**：`llm.gd`（HTTP 调 DeepSeek）是否一并迁入 Pleiades（它已有 candle/ML 引擎 + axum API）？倾向迁入，Godot 只发文本、收解析后命令。
4. **坐标变换归属**：`CoordUtils`（真实世界↔游戏像素）倾向留在 Godot（纯表现层换算），不在桥上传递。

---

## 7. 分阶段计划

| 阶段 | 内容 | 验证点 |
|---|---|---|
| P0 | GDExtension 骨架：起 tokio + swarm，订阅 pose 打日志 | headless 打印车端 pose |
| P1 | 抽网络内核 crate + Pleiades 无头模式（feature-gate ML/TUI） | 车端/终端共用编译通过 |
| P2 | 桥 API：pose/map 订阅 + 命令下发 + peer 事件 | Godot 显示真实车 pose |
| P3 | Godot 拆除 WebSocket 栈，切换到桥 | 群发 Goto 跑通 |
| P4 | e2e + 断线重连验证 | 拔网线 → 自动恢复（应天然通过） |

---

## 8. 与现有任务的关系

- **task_23（WebSocket 重连）**：本方案使其**作废**，建议标记 superseded。
- **task_17（STT）/ task_16（LLM）**：并入"Pleiades 逻辑层"，与桥共用 GDExtension 脚手架。
- **多车地图一致性调研**：与边界问题 1 耦合，需确定是否纳入本方案 scope。
