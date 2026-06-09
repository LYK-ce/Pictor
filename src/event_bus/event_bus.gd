extends Node
## Present by KeJi
## Date: 2026-06-08
##
## EventBus — 全局事件总线（Autoload 单例）
## 所有跨组件通信的唯一通道。组件只认识 EventBus，彼此零引用。

signal pose_received(pose: Dictionary)
signal voxel_received(voxels: Array, is_full: bool)
signal path_received(points: Array)
signal ctrl_send(ctrl: Dictionary)
signal zoom_changed(zoom: float)
