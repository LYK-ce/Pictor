# wb_4_websocket_client

## meta
- task: task_4_websocket_client
- start: 2026-06-08
- end: 2026-06-08
- status: done

## created
- src/websocket_client/websocket_client.gd — WS client with reconnect, JSON dispatch
- src/websocket_client/websocket_client.tscn — minimal scene
- test/websocket_client/test_websocket.gd — 7 cases, 15 asserts, all pass
- project.godot: [websocket] config section

## findings
- Godot WebSocket is poll-based (`_process` + `poll()`), not event-driven
- `_on_message()` works standalone → testable without real connection
- ctrl_send queues to `_pending_messages` when disconnected
- Each `_make_ws()` triggers `_ready()` → `_connect()` → harmless `[WS] connecting` log

## test results
```
ALL 15 TESTS PASSED ✓
  [1] pose dispatch: x=1.5, yaw=0.785
  [2] voxel_full: count=2, is_full=true, state=1
  [3] voxel_delta: count=1, is_full=false
  [4] path: 3 points, last x=3
  [5] bad JSON: no emit
  [6] unknown type: no emit
  [7] ctrl → pending queue: key=w
```

## deps resolved
- task_2 (EventBus)
- docs/protocol.md
