# Task 26: GPS 卫星地图背景（高德瓦片在线加载）

> 创建日期：2026-08-30
> 状态：✅ 方案已定（待实现）—— 先独立实现 GPSMap 模块并单测，暂不接入主场景
> 范围：给 Pictor 增加在线卫星地图背景层 —— 启动时给定一个经纬度，拉取周围一小片高德卫星瓦片拼接显示
> 用途：内部测试，不商用

---

## 一、背景

当前 Pictor 的地图是小车端经 Orion 协议推送的 log-odds 占用栅格地图（SLAM 结果），无真实地理参照。需求：启动时给定一个 WGS-84 经纬度坐标，在线拉取该点周围一小片高德卫星影像作为背景底图，与现有车辆位姿渲染叠加。

## 二、核心结论

- 卫星影像无法本地生成，必须联网从第三方瓦片服务拉取（切片图片，Web 墨卡托投影，256×256/张）。
- 数据源选 **高德地图**（国内访问快、内部测试免 key、图源清晰）。
- 高德瓦片 URL（Web 端内部接口，非官方公开 API，内部测试可接受，但可能变动）：
  - 卫星影像（纯图）：`style=6`（webst 域名）
  - 矢量街道图（大字版，注记抽稀）：`style=7`
  - 路网标注层（叠加卫星图用）：`style=8`
  - 大字版（注记未抽稀、无图标）：`style=9`
  - 大字版（注记抽稀，另一变体）：`style=10`
- `style` 取值共 6/7/8/9/10 五个；⚠️ 注意「不同域名规律不一致」（webrd 与 wprd/webst 含义不同）。
- 本项目只用：卫星底图 `style=6`；如需「卫星 + 路网标注」= `style=6` + `style=8` 两层叠加。
- 另有 `ltype` 参数可精细控制显示地块/路网/注记（本项目用不到）。

## 三、关键技术点

### 3.1 坐标系（🔴 最重要）

高德使用 **GCJ-02（火星坐标）**，与 GPS 的 WGS-84 在中国大陆偏移约几百米。必须：

```
WGS-84 经纬度 → GCJ-02 转换 → 瓦片坐标 (z, x, y)
```

跳过转换会导致整图偏移几百米、与真实位置对不上。

### 3.2 瓦片坐标换算

- Web 墨卡托投影（与标准 slippy map 一致），但输入是 GCJ-02 经纬度。
- 标准公式：`lon → x`、`lat → y`（z 级，256 像素/瓦片）。

### 3.3 范围控制（当前只需一个 Chunk）

本次实验仅需约 128m×128m（一个 Chunk）范围，暂**不做滑动窗口**：启动时一次性加载该范围（z=18 约 1~4 张瓦片）即可。滑动窗口留待未来跑大范围时再升级。

### 3.4 实测结论（2026-08-30 验证）

- ✅ 高德卫星瓦片 URL **可直接下载**：`curl` 实测 HTTP 200，无需 API key、无需特殊 header（`access-control-allow-origin: *`）。
- 瓦片实际是 **256×256 的 JPEG**（content-type: image/jpeg，URL 无扩展名）。
- GCJ-02 偏移实测（北京天安门）：WGS-84 (116.3975, 39.9087) → GCJ-02 (116.403744, 39.910103)，偏移 **≈693m 东 / 156m 北**（印证必须做坐标转换）。
- zoom 与地面尺寸（北京纬度 39.9°N，cos≈0.767）：

| zoom | 一张瓦片地面尺寸 | 与 128m Chunk 关系 |
|---|---|---|
| 17 | ~234m | 太大（1 张盖 2 个 chunk） |
| **18** | **~117m** | ✅ 最接近（≈1 张/Chunk） |
| 19 | ~59m | 太小（需 2×2=4 张/Chunk） |

> 结论：**zoom 建议 18**，一张瓦片约 117m，最贴近 128m 的 Chunk。

## 四、实施方案（架构已确认）

### 4.1 节点结构

```
main.tscn
└── GPSMap (Node2D，独立节点，与 Renderer2D/Renderer3D 平级，放在最底层)
    ├── chunk_0_0 (Sprite2D)   ← 第 (0,0) 个 chunk 的卫星图
    ├── chunk_1_0 (Sprite2D)
    └── ...
```

- `GPSMap` 继承 `Node2D`，独立场景/节点，**不隶属于** Renderer2D/Renderer3D。
- 下挂 `Sprite2D`，命名 `chunk_{cx}_{cy}`（用户口头称 chunk00；因 chunk 是二维坐标，故用二维命名，待确认）。
- 渲染层级：GPSMap 在最底层，Renderer2D 半透明 TileMap + 车辆 Sprite 叠在其上。

### 4.2 GPSMap 对外 API（供 main.gd 主场景调用）

| 接口 | 说明 |
|---|---|
| `set_origin(lat, lon)` | 设置锚点经纬度（WGS-84），作为对齐 game 坐标的原点 |
| `load_area(lat, lon, size_m)` | 加载以某点为中心、边长 size_m 的正方形区域卫星图 |
| `clear()` | 清空所有卫星图 |

### 4.3 内部实现步骤

| # | 步骤 | 说明 |
|---|---|---|
| 1 | WGS-84 → GCJ-02 转换 | 标准偏移算法（已实测验证）—— **放 GPS 模块内部**（仅本模块使用，不放 utils/coords.gd） |
| 2 | GCJ-02 → 瓦片坐标 (z/x/y) | Web 墨卡托投影 |
| 3 | 下载瓦片 | `HTTPRequest` 异步 GET 高德瓦片 URL |
| 4 | 拼接 + 显示 | 拼成 chunk 图 → `Sprite2D`（命名 `chunk_0_0`） |

> 代码全部放 `src/gps_map/`（目录已建）。
> 首版：独立实现 + 单独测试 GPSMap 节点，暂不接入 main.tscn。

### 4.4 坐标对齐约定（已定）

- 范围：一个瓦片（z=18，约 117m）够用。
- 锚点：基站初始经纬度（WGS-84）对齐到 game 坐标 **(64, 64)** 米 —— 基站位于卫星图正中心。
- 卫星图围绕 (64, 64) 居中展开；车 SLAM 起点 (0,0) 也对应 (64, 64)。
- 卫星图 / SLAM 地图 / 车辆三者通过 game 坐标（米，32px/m）统一对齐。
- 航向基准：**正北 = 0°**（Godot 2D 中 -y = 北、+x = 东）。偏航补偿由车端处理，终端不负责。
- 默认基站坐标（内部测试默认值）：**北纬 40°5'15''、东经 116°13'13''** = 十进制 `(lat=40.0875, lon=116.220278)`，GCJ-02 ≈ `(116.226360, 40.088740)`，z=18 瓦片 `(215705, 99157)`。

## 五、决策汇总（已全部确定 ✅）

1. zoom 级别：**z=18**（一张瓦片约 117m）。
2. 图源样式：**style=6 纯卫星影像**。
3. 锚点：基站（车）位于卫星图正中心，game 坐标 **(64, 64)** 米。
4. Sprite2D 命名：二维 **`chunk_{cx}_{cy}`**（首个为 `chunk_0_0`）。

## 六、验收标准（首版）

- 单独运行 `gps_map` 场景 → 自动用默认坐标拉取并显示卫星图。
- `chunk_0_0`（Sprite2D）正确显示卫星图，锚点 (64,64) 落在瓦片正确位置。
- 不依赖商用 key，内部测试可用。
- （接入主场景、叠加 log-odds 地图为后续阶段，首版不做）

---

## 七、实现规格说明书

### 7.1 涉及文件

| 文件 | 类型 | 说明 |
|---|---|---|
| `src/gps_map/gps_map.gd` | 脚本 | GPSMap 主脚本（Node2D），全部核心逻辑 |
| `src/gps_map/gps_map.tscn` | 场景 | GPSMap 场景：Node2D + HTTPRequest + Tiles + Sprite2D |

### 7.2 文件结构

```
src/gps_map/
├── gps_map.gd    ← GPSMap 主脚本（Node2D）
└── gps_map.tscn  ← GPSMap 场景
```

### 7.3 场景结构

```
GPSMap (Node2D, gps_map.gd)
├── HTTPRequest (下载瓦片)
└── Tiles (Node2D 容器)
    └── chunk_0_0 (Sprite2D, 卫星图瓦片)
```

### 7.4 Function 规格

| Function | 输入 | 功能 | 输出 |
|---|---|---|---|
| `load_satellite(lat: float, lon: float)` | WGS-84 经纬度（十进制度） | **主入口**：GCJ-02 转换 → 瓦片坐标 → 下载瓦片 → 贴到 Sprite2D | void（异步） |
| `_wgs84_to_gcj02(lon: float, lat: float)` | WGS-84 经纬度 | 火星坐标转换（标准偏移算法，仅内部用） | `Vector2`(GCJ-02 经度, 纬度) |
| `_lonlat_to_tile(lon: float, lat: float, z: int)` | GCJ-02 经纬度 + zoom | Web 墨卡托投影 → 瓦片坐标 | `Vector2i`(瓦片 x, y) |
| `_build_tile_url(x: int, y: int, z: int)` | 瓦片坐标 + zoom | 构造高德瓦片 URL（style=6） | `String` |
| `_on_request_completed(result, code, headers, body)` | HTTPRequest 回调参数 | 下载完成 → 解码 JPEG → `ImageTexture` → 贴 Sprite2D | void |
| `_compute_tile_transform(tile_x, tile_y, z)` | 瓦片坐标 + zoom | 算瓦片的 position/scale（锚点对齐） | `Dictionary`{position: Vector2, scale: Vector2} |

### 7.5 详细实施步骤

1. 建 `gps_map.gd`（`extends Node2D`），文件头归属注释。
2. 建 `gps_map.tscn`：根 Node2D + HTTPRequest + Tiles(Node2D) + chunk_0_0(Sprite2D)。
3. 实现 `_wgs84_to_gcj02`：标准 GCJ-02 偏移算法（已实测验证）。
4. 实现 `_lonlat_to_tile`：Web 墨卡托投影公式。
5. 实现 `_build_tile_url`：拼 URL（style=6、webst 域名、z=18）。
6. 实现 `load_satellite`：串联上述步骤，发起 `HTTPRequest` 下载。
7. 实现 `_on_request_completed`：body → `Image` → `ImageTexture` → 赋给 `chunk_0_0.texture`。
8. 实现 `_compute_tile_transform`：瓦片经纬度范围 → game 坐标（米）→ position/scale，锚点 (64,64) 对齐。
9. `_ready()` 里调用 `load_satellite(DEFAULT_LAT, DEFAULT_LON)`（**临时**，测试通过后删掉该默认调用）。

### 7.6 坐标对齐数学

- 单位：game 世界 1 米 = 32 像素（沿用 `CoordUtils`）。
- 锚点：WGS-84 `(lat0=40.0875, lon0=116.220278)` → game 坐标 **(64, 64) 米**。
- 经纬度 → 米（相对锚点，平面近似，范围 ~117m 可忽略曲率）：
  - `Δx（东,米）= (lon - lon0) × 111320 × cos(lat0)`
  - `Δy（北,米）= (lat - lat0) × 110540`
- 瓦片经纬度范围（瓦片坐标逆变换）：
  - `lon = x / 2^z × 360 − 180`
  - `lat = atan(sinh(π × (1 − 2y / 2^z))) × 180/π`
- 北 = -y 方向：`game_y = 64 − Δy（北向为正，Godot y 轴向下）`。
- Sprite2D 摆放：`position = 瓦片中心 game 米坐标 × 32`；`scale = 瓦片地面尺寸（米）× 32 / 256`。

### 7.7 常量

| 常量 | 值 | 说明 |
|---|---|---|
| `DEFAULT_LAT` | `40.0875` | 默认纬度（北纬 40°5'15''） |
| `DEFAULT_LON` | `116.220278` | 默认经度（东经 116°13'13''） |
| `ANCHOR_XY` | `Vector2(64, 64)` | 锚点 game 坐标（米） |
| `ZOOM` | `18` | 瓦片 zoom 级别 |
| `PIXELS_PER_METER` | `32.0` | 像素/米 |
| `TILE_SIZE_PX` | `256` | 瓦片原图像素 |
