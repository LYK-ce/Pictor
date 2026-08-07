class_name ChunkData2D
extends Resource
## Present by KeJi
## Date: 2026-07-11
##
## ChunkData2D — 256×256 网格的 PackedByteArray 存储
## cells[index] = 0 → 可通行, 100 → 不可通行, 255 → 未知

@export var cells: PackedByteArray
