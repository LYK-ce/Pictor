# wb_3_input_handler

## meta
- task: task_3_input_handler
- start: 2026-06-08
- end: 2026-06-08
- status: done

## created
- src/input_handler/input_handler.gd — _input() + _make_ctrl(), get_node(/root/EventBus)
- test/input_handler/test_input.gd — 6 cases, 19 asserts, all pass

## findings
- `get_node("/root/EventBus")` works in both autoload and manual-test modes — better than global `EventBus` ref
- `InputEventKey` can be constructed programmatically and passed to `_input()` directly
- `echo` field on InputEventKey correctly simulates OS key repeat

## design note
Switched from `EventBus.ctrl_send.emit()` (autoload global) to `get_node("/root/EventBus").ctrl_send.emit()`
because `--script` mode does not register autoloads. The new form works in both environments.

## test results
```
ALL 19 TESTS PASSED ✓
  [1] _make_ctrl: type/ctrl, key/w, action/press
  [2] press→press, release→release
  [3] w,s,a,d,space all mapped
  [4] echo ignored
  [5] ENTER ignored
  [6] W press/release + Space: 6 asserts
```

## deps resolved
- task_2 (EventBus)
