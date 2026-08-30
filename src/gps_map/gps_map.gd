## Presented by KeJi
## Date ： 2026-08-30
##
## GPSMap — 高德卫星地图背景层（在线瓦片加载）
## 给定 WGS-84 经纬度，拉取高德卫星瓦片，贴到 Sprite2D。
## 首版：单瓦片（z=18），锚点 (64,64) 米对齐，暂未接入主场景。
class_name GPSMap
extends Node2D


# ============ 常量 ============

const DEFAULT_LAT := 40.0875            # 默认纬度（北纬 40°5'15''）
const DEFAULT_LON := 116.220278         # 默认经度（东经 116°13'13''）
const ANCHOR_XY := Vector2(64.0, 64.0)  # 锚点 game 坐标（米）
const ZOOM := 18                        # 瓦片 zoom 级别
const PIXELS_PER_METER := 32.0          # 1 米 = 32 像素（沿用 CoordUtils）
const TILE_SIZE_PX := 256               # 瓦片原图像素


# ============ 节点引用 ============

@onready var _http: HTTPRequest = $HTTPRequest
@onready var _chunk: Sprite2D = $Tiles/chunk_0_0


# ============ 状态 ============

var _anchor_gcj: Vector2     # GCJ-02 锚点 (lon, lat)
var _current_tile: Vector2i  # 当前请求的瓦片坐标


func _ready() -> void:
	_http.request_completed.connect(_on_request_completed)
	# 临时：测试用，直接拉默认坐标（测试通过后删除该调用）
	load_satellite(DEFAULT_LAT, DEFAULT_LON)


# ============ 对外 API ============

## 主入口：给定 WGS-84 经纬度，拉取对应卫星图并贴到 Sprite2D
func load_satellite(lat: float, lon: float) -> void:
	_anchor_gcj = _wgs84_to_gcj02(lon, lat)
	_current_tile = _lonlat_to_tile(_anchor_gcj.x, _anchor_gcj.y, ZOOM)
	var url := _build_tile_url(_current_tile.x, _current_tile.y, ZOOM)
	print("[GPSMap] load_satellite: lat=%f lon=%f -> tile(%d,%d)" % [lat, lon, _current_tile.x, _current_tile.y])
	var err := _http.request(url)
	if err != OK:
		push_error("[GPSMap] HTTP 请求失败: %d" % err)


# ============ 坐标转换 ============

## WGS-84 → GCJ-02（火星坐标），标准偏移算法
func _wgs84_to_gcj02(lon: float, lat: float) -> Vector2:
	if not _in_china(lon, lat):
		return Vector2(lon, lat)
	var dlat := _transform_lat(lon - 105.0, lat - 35.0)
	var dlon := _transform_lon(lon - 105.0, lat - 35.0)
	var radlat := deg_to_rad(lat)
	var magic := sin(radlat)
	magic = 1.0 - 0.00669342162296594323 * magic * magic
	var sqrt_magic := sqrt(magic)
	dlat = (dlat * 180.0) / ((6378245.0 * (1.0 - 0.00669342162296594323)) / (magic * sqrt_magic) * PI)
	dlon = (dlon * 180.0) / (6378245.0 / sqrt_magic * cos(radlat) * PI)
	return Vector2(lon + dlon, lat + dlat)


func _in_china(lon: float, lat: float) -> bool:
	return lon >= 72.004 and lon <= 137.8347 and lat >= 0.8293 and lat <= 55.8271


func _transform_lat(x: float, y: float) -> float:
	var ret := -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
	ret += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
	ret += (20.0 * sin(y * PI) + 40.0 * sin(y / 3.0 * PI)) * 2.0 / 3.0
	ret += (160.0 * sin(y / 12.0 * PI) + 320.0 * sin(y * PI / 30.0)) * 2.0 / 3.0
	return ret


func _transform_lon(x: float, y: float) -> float:
	var ret := 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
	ret += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
	ret += (20.0 * sin(x * PI) + 40.0 * sin(x / 3.0 * PI)) * 2.0 / 3.0
	ret += (150.0 * sin(x / 12.0 * PI) + 300.0 * sin(x / 30.0 * PI)) * 2.0 / 3.0
	return ret


## GCJ-02 经纬度 → 瓦片坐标（Web 墨卡托，XYZ 从上往下）
func _lonlat_to_tile(lon: float, lat: float, z: int) -> Vector2i:
	var n := float(1 << z)
	var x := floori((lon + 180.0) / 360.0 * n)
	var lat_rad := deg_to_rad(lat)
	var y := floori((1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0 * n)
	return Vector2i(x, y)


## 瓦片坐标 → 经纬度（逆变换，返回瓦片左上角）
func _tile_to_lonlat(tile_x: int, tile_y: int, z: int) -> Vector2:
	var n := float(1 << z)
	var lon := tile_x / n * 360.0 - 180.0
	var lat := rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * tile_y / n))))
	return Vector2(lon, lat)


# ============ URL 构造 ============

## 构造高德卫星瓦片 URL（style=6）
func _build_tile_url(x: int, y: int, z: int) -> String:
	return "https://webst01.is.autonavi.com/appmaptile?style=6&x=%d&y=%d&z=%d" % [x, y, z]


# ============ 下载回调 ============

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("[GPSMap] 下载失败 result=%d code=%d" % [result, response_code])
		return
	var img := Image.new()
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err != OK:
		push_error("[GPSMap] 图片解码失败 err=%d" % err)
		return
	_chunk.texture = ImageTexture.create_from_image(img)
	var t := _compute_tile_transform(_current_tile.x, _current_tile.y, ZOOM)
	_chunk.position = t["position"]
	_chunk.scale = t["scale"]
	print("[GPSMap] 瓦片就绪 %dx%d position=%s scale=%s" % [img.get_width(), img.get_height(), str(t["position"]), str(t["scale"])])


# ============ 坐标对齐 ============

## 计算瓦片 Sprite2D 的 position 与 scale（锚点 (64,64) 对齐）
func _compute_tile_transform(tile_x: int, tile_y: int, z: int) -> Dictionary:
	var top_left := _tile_to_lonlat(tile_x, tile_y, z)             # 西北角
	var bottom_right := _tile_to_lonlat(tile_x + 1, tile_y + 1, z) # 东南角
	var center_lon := (top_left.x + bottom_right.x) / 2.0
	var center_lat := (top_left.y + bottom_right.y) / 2.0
	var cos_lat := cos(deg_to_rad(_anchor_gcj.y))
	# 中心相对锚点的米偏移
	var dx := (center_lon - _anchor_gcj.x) * 111320.0 * cos_lat
	var dy := (center_lat - _anchor_gcj.y) * 110540.0
	# game 坐标（米）：锚点 (64,64)，北 = -y
	var pos_m := Vector2(ANCHOR_XY.x + dx, ANCHOR_XY.y - dy)
	var position := pos_m * PIXELS_PER_METER
	# 瓦片地面尺寸（米）
	var tile_w_m := (bottom_right.x - top_left.x) * 111320.0 * cos_lat
	var tile_h_m := (top_left.y - bottom_right.y) * 110540.0
	var scale := Vector2(tile_w_m * PIXELS_PER_METER / TILE_SIZE_PX, tile_h_m * PIXELS_PER_METER / TILE_SIZE_PX)
	return {"position": position, "scale": scale}
