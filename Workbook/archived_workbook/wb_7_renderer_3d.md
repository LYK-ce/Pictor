# wb_7_renderer_3d

## meta
- task: task_7_renderer_3d
- start: 2026-06-08
- end: 2026-06-08
- status: done

## created
- src/utils/coords.gd — added `real_to_game_3d()`
- src/renderer_3d/{map_container,vehicle_marker,path_line,renderer}_3d.gd + tscn
- test/renderer_3d/{test_map_container,test_vehicle_marker,test_path_line}.gd
- tests: 4+4+2 = 10/10 pass

## findings
- `class_name CoordUtils` not available in `--script` headless → use inline const SCALE=16.0
- MultiMeshInstance3D with instance_count + set_instance_transform() works well
- `queue_free()` needs `await process_frame` to take effect
- PathLine3D uses ImmediateMesh PRIMITIVE_LINES per-frame rebuild
- CameraRig deferred (needs mouse input, can't test headless)

## deps resolved
- task_2 EventBus, task_6 Renderer2D (reference)
