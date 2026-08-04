## Presented by KeJi
## Date ： 2026-08-04
##
## Util — 工具箱容器：聚合所有工具节点（LLM/STT...），
## 调用方只需引用本节点即可访问全部工具。
## 用法：@export var util: Util（场景面板拖入）→ util.llm.generate_cmds(...)

class_name Util
extends Node

## LLM 工具：自然语言 → cmd 指令数组
@onready var llm: LLM = $LLM
