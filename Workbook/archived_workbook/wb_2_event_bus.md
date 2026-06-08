# wb_2_event_bus

## meta
- task: task_2_event_bus
- start: 2026-06-08
- end: 2026-06-08
- status: done

## created
- src/event_bus/event_bus.gd — 4 signals, extends Node, zero logic
- test/event_bus/test_event_bus.gd — 5 cases, 11 asserts, all pass
- project.godot: autoload + renderer mode config

## findings
- `--script` mode does NOT load Autoloads → test scripts must manually instantiate
- GDScript 2.0 lambdas capturing local vars do NOT fire as signal callbacks → use member funcs
- `emit()` is synchronous; callback fires before next line
- Node signals require node to be in scene tree (`root.add_child`)

## test results
```
ALL 11 TESTS PASSED ✓
  [1] emit → callback invoked
  [2] ts matches, x matches, yaw matches
  [3] voxel count matches, is_full=true, state matches
  [4] key=w, action=press
  [5] subscriber A called, subscriber B called
```

## deps resolved
- none (standalone)
