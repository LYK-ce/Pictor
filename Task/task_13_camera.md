# Task 13: Camera

## 目标

将 Camera2D 从 Vehicle2D 上分离，作为独立组件开发。

## 设计决策

- Camera2D 挂载在 Main 节点下作为子组件，不再跟随 Vehicle2D
- Camera 提供控制方式用于移动/缩放/跟踪等操作

### 移动：鼠标中键拖拽

- 中键按下 → 记录起始鼠标位置 + Camera 当前位置
- 拖拽中 → `camera.position = 起始位置 - 鼠标偏移 / zoom`
- 除以 zoom 保证放大缩小时拖拽手感一致（抓住拖动）
- 中键释放 → 停止拖拽
- 使用 `_unhandled_input`，避免 UI 拦截

### 移动：边缘滚动

- 屏幕四边各留 20px 触发区，鼠标贴边即滚动
- `_process` 中每帧检测，4 行浮点比较，开销极低
- `position += dir * speed * delta / zoom`，除以 zoom 保证速度恒定

### 跟踪车辆

- 后续由人工处理，agent 暂不实现

### 边界限制

- Camera2D 内置 `limit_left/right/top/bottom`，需要时 `@export` 配置即可
- 当前地图不大，暂不限制

### 缩放
- 滚轮缩放：在 Camera 脚本中实现
- zoom_slider UI 组件：后续由人工添加到 UI，agent 暂不处理

## 实施步骤

### 1. 移除 Vehicle2D 上的 Camera2D
- [x] 从 `vehicle_2d.tscn` 中删除 Camera2D 子节点

### 2. 创建 Camera 组件
- [x] 新建 `src/camera/` 目录
- [x] 创建 `camera_2d.gd` 脚本 + `camera_2d.tscn` 场景
- [x] Camera 挂载在 Main 下，作为独立子组件
- [x] 实现移动：中键拖拽 + 边缘滚动
- [x] 实现滚轮缩放（以鼠标为中心）
- [ ] 跟踪车辆（人工处理）
- [ ] zoom_slider UI（人工处理）

## 依赖

- EventBus (task_2)

## 状态

- [x] 1. 移除 Camera2D
- [x] 2. 创建 Camera 组件
- [x] 3. 中键拖拽
- [x] 4. 边缘滚动
- [x] 5. 滚轮缩放
- [ ] 6. 跟踪车辆（人工）
- [ ] 7. zoom_slider（人工）