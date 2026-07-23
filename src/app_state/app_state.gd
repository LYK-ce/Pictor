## Presented by KeJi
## Date ： 2026-07-23
##
## AppStateResource — 全局共享状态 Resource
## 消费者通过 @export var app_state: AppStateResource 声明依赖，
## 所有组件拖同一个 .tres 文件即共享同一份数据。

class_name AppStateResource
extends Resource

## 当前选中的车辆 ID，空字符串 = 无选中
var selected_id := ""
