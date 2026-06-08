# wb_1_main

## meta
- task: task_1_main
- start: 2026-06-08
- end: 2026-06-08
- status: done

## created
- src/main/main.gd — _ready() instantiates WS + IH + optional Renderer
- src/main/main.tscn — minimal scene
- test/main/test_main.gd — 6 asserts, all pass

## findings
- Main scene with 2 children: WebSocketClient + InputHandler (Renderer not yet)
- WebSocketClient connects to mock server → receives voxel_full(100) + path(10) + pose streaming
- Input.parse_input_event() works in headless for feeding keyboard
- InputHandler → EventBus.ctrl_send → WebSocketClient pending queue → verified
- Full loop: mock car → WS → EventBus → IH → EventBus → WS pending ✅

## test results
```
ALL 6 TESTS PASSED ✓
  ✓ WebSocketClient instantiated
  ✓ InputHandler instantiated
  ✓ voxel_full received: 100 cells
  ✓ path received: 10 points
  ✓ pose received: 2 msgs
  ✓ ctrl sent via EventBus
```

## server side log
```
[+] client connected
  → voxel_full: 100 cells
  → path: 10 points
  ← ctrl: w press
  ← ctrl: space press
  🛑 ESTOP!
[-] client disconnected
```

## deps resolved
- task_2, task_3, task_4, task_5
