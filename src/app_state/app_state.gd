## Presented by KeJi
## Date ： 2026-07-28
##
## AppStateResource — 全局共享状态 Resource
## 消费者通过 @export var app_state: AppStateResource 声明依赖，
## 所有组件拖同一个 .tres 文件即共享同一份数据。

class_name AppStateResource
extends Resource

enum Mode { NONE, FOLLOW, GOTO }

## 当前选中的车辆 ID，空字符串 = 无选中，变化时 emit selection_changed
var selected_id := "":
	set(value):
		if selected_id != value:
			selected_id = value
			EventBus.selection_changed.emit(value)

## 当前交互模式，变化时 emit mode_transited
var mode := Mode.NONE:
	set(value):
		if mode != value:
			mode = value
			EventBus.mode_transited.emit(value)
