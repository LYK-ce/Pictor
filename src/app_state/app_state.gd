## Presented by KeJi
## Date ： 2026-07-28
##
## AppStateResource — 全局共享状态 Resource
## 消费者通过 @export var app_state: AppStateResource 声明依赖，
## 所有组件拖同一个 .tres 文件即共享同一份数据。

class_name AppStateResource
extends Resource

enum Mode { NONE, FOLLOW, GOTO }

## 多选车辆 ID 列表，Goto/LLM 命令广播给这些车
var selected_ids: Array[String] = []

## 兼容旧代码的单车 ID（取 selected_ids 第一辆，空数组返回 ""）
var selected_id: String:
	get: return selected_ids[0] if selected_ids.size() > 0 else ""
## 当前交互模式，变化时 emit mode_transited
var mode := Mode.NONE:
	set(value):
		if mode != value:
			mode = value
			EventBus.mode_transited.emit(value)
