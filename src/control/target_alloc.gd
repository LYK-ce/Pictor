## Presented by KeJi
## Created Date ： 2026-10-27
## Modified Date ： 2026-10-27
##
## TargetAlloc — 地面站逐车算点（task_36 §12.7.5）
## 协同已从车端上移到指挥层（§十一 #27）：车端不做任何分配，地面站逐车算出各自目标点、
## 逐车单独发帧，每帧 missions[0] 就是"该车自己的点"。
##
## ⚠️ 坐标系以协议为准（docs/orion_protocol.md §5）：世界坐标 x 东、y 南，单位米；
##    yaw 顺时针为正、0 = +x 东。不要照 auto_handler.gd / llm.gd 旧文案的
##    "0=正北、90=正东"去算偏移，否则落点整体偏 90°。
## ⚠️ RTK：VehicleRegistry 只存 {name, x, y, yaw, node_type}，**不存 rtk_fixed**
##    （虽然 ORION_POSE 自带该字节、UI 面板也显示它）。将来若落点精度依赖 RTK 固定解，
##    需要先在 VehicleRegistry._on_pose 里补存 rtk_fixed，再在这里加门控。
##
## 用法：
##   var gate := TargetAlloc.filter_placeable(app_state.selected_ids, vehicle_registry.vehicles)
##   var pts := TargetAlloc.compute_targets(gate.ok, anchor, "goto")
##   for id in pts:
##       EventBus.cmd_send.emit([id] as Array[String],
##           MessageBuilder.build_auto_push_goto(pts[id].x, pts[id].y))

class_name TargetAlloc
extends RefCounted

## 判"没有位姿"的阈值（米）：注册时 x/y 初值恰为 0，收到首帧 ORION_POSE 后才会变
const POS_EPS := 0.001


## 位姿健全性门控：x、y 都接近 0 的车视为"尚未收到位姿"，不参与算点。
## 依据：VehicleRegistry._on_vehicle_registered 把新车初始化为 (0.0, 0.0)，
##      刚注册还没收到第一帧 ORION_POSE 的车就是这个值；算进去会分到原点附近。
## 代价：恰好停在原点 (0, 0) 的车会被误拒 —— 原点离常规作业区较远，可接受。
## 返回：{ "ok": Array[String] 可参与算点, "rejected": Array[String] 无位姿 / 未注册 }
static func filter_placeable(targets: Array[String], vehicles: Dictionary) -> Dictionary:
	var ok_ids: Array[String] = []
	var rejected: Array[String] = []
	for id in targets:
		var v = vehicles.get(id, {})
		if not (v is Dictionary):
			rejected.append(id)
			continue
		var px := absf(float(v.get("x", 0.0)))
		var py := absf(float(v.get("y", 0.0)))
		if px < POS_EPS and py < POS_EPS:
			rejected.append(id)
			continue
		ok_ids.append(id)
	return {"ok": ok_ids, "rejected": rejected}


## 逐车算点 —— **占位实现：所有车去同一锚点**（task_36 §12.7.5）。
## 参数：
##   targets — 已过 filter_placeable 的 vehicle_id 列表
##   anchor  — 锚点世界坐标（米；x 东 / y 南）
##   shape   — 形状提示："goto" / "circle"（仅供将来的铺开算法使用；占位实现忽略）
## 返回：{ vehicle_id: Vector2 }（anchor 原样复制给每辆车）
## TODO(task_36 §12.7.5)：封控需求明确后替换为真正的分配（按形状铺开 / 按序号偏移 / 按 peer 排序）。
##   替换时**只改本函数**，auto_handler 与协议都不用再动。占位实现不是正式算法。
static func compute_targets(targets: Array[String], anchor: Vector2, shape: String) -> Dictionary:
	var out := {}
	for id in targets:
		out[id] = anchor
	return out
