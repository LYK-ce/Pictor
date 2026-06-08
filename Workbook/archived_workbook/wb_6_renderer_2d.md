# wb_6_renderer_2d

## meta
- task: task_6_renderer_2d
- start: 2026-06-08
- end: 2026-06-08
- status: done

## created
- map_container_2d.gd + tscn — Dict storage + TileMapLayer rendering
- vehicle_marker_2d.gd + tscn — _draw() triangle + Camera2D
- path_line_2d.gd + tscn — Line2D path display
- renderer_2d.gd + tscn — parent, EventBus subscriptions → child dispatch
- tests: 12 (map) + 5 (vehicle) + 3 (path) = 20 asserts, all pass

## findings
- TileSet + TileSetAtlasSource created at runtime with Image.create() + ImageTexture
- GDScript 2.0 `==` on float fails due to precision → use `is_equal_approx()`
- Camera2D on VehicleMarker2D gives free camera follow
- scene with `instance=` (PackedScene) requires load_steps count + instance attr

## test results
```
MapContainer2D:   12/12 ✓
VehicleMarker2D:   5/5 ✓
PathLine2D:         3/3 ✓
─────────────────────────
Total:             20/20 ✓
```

## deps resolved
- task_2 EventBus
- docs/map_coordinate_2d.md, docs/renderer_2d.md
