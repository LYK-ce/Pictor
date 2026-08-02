# wb_18_control

## meta
- task: task_18_control
- start: 2026-07-31
- end: 2026-08-02
- status: completed

## changes
- app_state: selected_id → selected_ids[] + manual_target + 兼容 getter
- vehicle_panel: 三态边框 (NORMAL/MANUAL/AUTO 橙/绿/灰)，移除 TakeControl 按钮，+Mode Label，mode_toggled 信号
- vehicle_panel_manager: Ctrl+点多选 + Manual 复选框互斥切换
- input_handler: 改装 ManualHandler（键盘 WASD → cmd_send(manual_target)，删 ctrl_input 中转）
- auto_handler (新): 右键 Goto 广播 selected_ids + PendingAction 瞬态状态机
- control_master.gd: 删除（逻辑拆分到两 handler）
- input_indicator: 重写为 goto 点击闪烁（goto_issued 信号，0.2s 保持 + 0.4s 淡出）
- event_bus: +goto_issued(x,y)；mode_transited 保留（Camera 仍依赖）

## 关键决策
- 手动/自动完全分离：ManualHandler + AutoHandler，ControlMaster 纯容器
- Goto 散布（车端偏移）暂缓
- Patrol/Stop 瞬态命令扩展点已预留（_pending_action）
