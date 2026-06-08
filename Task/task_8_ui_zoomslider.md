# Task 8: UI + ZoomSlider

## 目标

创建 UI 系统框架及首个 UI 组件——缩放滑块。UI 通过 EventBus 与 Renderer 通信，完全解耦。

## 文件位置

```
src/ui/
├── ui.gd                   # UI 父容器（CanvasLayer），挂载子 UI 组件
├── ui.tscn
├── zoom_slider/
│   ├── zoom_slider.gd      # 缩放滑块
│   └── zoom_slider.tscn
```

## 场景结构

```
Main (Node)
├── ...
└── UI (CanvasLayer, ui.gd)
    └── ZoomSlider (zoom_slider.tscn)
        ├── Panel          ← 半透明背景
        ├── VSlider        ← 缩放滑块 0.5~4.0
        └── Label          ← "Zoom: 1.0x"
```

## 通信链路

```
ZoomSlider 拖动
    → EventBus.zoom_changed.emit(value)

Renderer._ready()
    → EventBus.zoom_changed.emit(1.0)       ← 初始值

Renderer._on_zoom(z):
    2D: Camera2D.zoom = Vector2(z, z)
    3D: 待定
```

初始 zoom 由 Renderer 主动发出，ZoomSlider 被动同步滑块位置，互不引用。

## EventBus 新增

```gdscript
signal zoom_changed(zoom: float)
```

## ZoomSlider

- 锚定右上角
- VSlider：范围 0.5 ~ 4.0，步长 0.1，默认 1.0
- Label：显示当前值，格式 "Zoom: 1.0x"
- `_ready()`：`EventBus.zoom_changed.connect(_on_zoom)` → 同步 slider.value
- `_on_value_changed(v)`：`EventBus.zoom_changed.emit(v)` + 更新 Label
- 不持有任何组件引用，只认 EventBus

## UI 父容器

- 继承 `CanvasLayer`
- `_ready()`：实例化 ZoomSlider 并 add_child
- 后续其他 UI 组件（小地图、状态栏等）均挂载于此

## 实施步骤

1. 更新 `event_bus.gd`，新增 `zoom_changed` 信号
2. 创建 `zoom_slider.gd` + `zoom_slider.tscn`
3. 创建 `ui.gd` + `ui.tscn`
4. 更新 `renderer_2d.gd`：订阅 `zoom_changed`，设置 Camera2D.zoom
5. 更新 `main.gd`：实例化 UI

## 测试

- 文件：`test/ui/test_zoom_slider.gd`
- 运行：`godot --headless --display-driver headless --path . --script test/ui/test_zoom_slider.gd`

### 测试用例

1. **滑块 emit zoom**：设置 value → EventBus.zoom_changed emit 正确值
2. **Renderer 接收 zoom**：emit zoom_changed → Camera2D.zoom 更新
3. **初始值同步**：Renderer._ready → emit zoom_changed(1.0) → 滑块同步到 1.0

## 依赖

- [x] EventBus (task_2)
- [x] Renderer2D (task_6)

## 状态

- [ ] 待开始
