extends Node
## Present by KeJi
## Date: 2026-06-08
## Modified Date ： 2026-10-29
##
## Main — 项目入口。MapData2D + Renderer2D + KernelBridge + WsCommandServer + VehiclePanelManager 已挂在 tscn 中。
## WS 命令通道（task_40 Step 3）：参数解析只在 `WsCommandServer` 里做一份，这里只回显结果。


func _ready() -> void:
	print("[Main] ready: ", get_child_count(), " children")
	var ws := get_node_or_null("WsCommandServer")
	if ws == null:
		return
	var port: int = ws.GetListenPort()
	if port > 0:
		print("[Main] WS 命令通道: %s:%d" % [ws.GetBindAddress(), port])
	else:
		print("[Main] WS 命令通道: 未启用（需要 -- --ws-port=<port>）")
