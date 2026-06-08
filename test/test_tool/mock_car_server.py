#!/usr/bin/env python3
"""
mock_car_server.py — 小车端模拟器
模拟 Pleiades 发送 pose / voxel / path，接收 ctrl 指令。
"""

import asyncio
import json
import math
import signal
import time

import websockets
from websockets.asyncio.server import serve

HOST = "0.0.0.0"
PORT = 9002
POSE_HZ = 10.0  # pose 发送频率

# ─── 模拟地图数据 ────────────────────────────────────────────

def build_voxel_world(size: int = 20) -> list[dict]:
    """生成 size×size 网格，全为空闲，仅 (1,1) 处有一个障碍物"""
    voxels = []
    for gx in range(size):
        for gz in range(size):
            is_obstacle = (gx == 1 and gz == 1)
            voxels.append({
                "gx": gx,
                "gy": 0,
                "gz": gz,
                "state": 2 if is_obstacle else 1,
                "conf": 1.0,
            })
    return voxels


def build_path() -> list[dict]:
    """从 (0,0) 到 (5,5) 的直线路径"""
    points = []
    for i in range(10):
        t = i / 9.0
        points.append({"x": 5.0 * t, "z": 5.0 * t})
    return points


# ─── 小车状态机 ──────────────────────────────────────────────

class CarState:
    def __init__(self):
        self.x = 0.0
        self.y = 0.0
        self.z = 0.0
        self.yaw = 0.0
        self.vx = 0.0
        self.vz = 0.0
        # 控制状态
        self.forward = False
        self.backward = False
        self.turn_left = False
        self.turn_right = False
        self.estop = False

    def update(self, dt: float):
        if self.estop:
            self.vx = 0.0
            self.vz = 0.0
            return

        speed = 2.0
        turn_rate = math.radians(90)

        target_v = 0.0
        if self.forward:
            target_v = speed
        elif self.backward:
            target_v = -speed

        if self.turn_left:
            self.yaw -= turn_rate * dt
        if self.turn_right:
            self.yaw += turn_rate * dt

        self.vx = target_v * math.cos(self.yaw)
        self.vz = target_v * math.sin(self.yaw)

        self.x += self.vx * dt
        self.z += self.vz * dt

    def handle_ctrl(self, ctrl: dict):
        key = ctrl.get("key", "")
        action = ctrl.get("action", "")
        pressed = action == "press"
        match key:
            case "w":      self.forward = pressed
            case "s":      self.backward = pressed
            case "a":      self.turn_left = pressed
            case "d":      self.turn_right = pressed
            case "space":  self.estop = pressed

    def to_dict(self) -> dict:
        return {
            "type": "pose",
            "ts": time.time(),
            "x": round(self.x, 3),
            "y": self.y,
            "z": round(self.z, 3),
            "yaw": round(self.yaw, 3),
            "vx": round(self.vx, 3),
            "vz": round(self.vz, 3),
        }


# ─── 客户端 handler ──────────────────────────────────────────

async def handler(websocket):
    print(f"[+] client connected: {websocket.remote_address}")
    car = CarState()
    voxel_world = build_voxel_world(10)
    path = build_path()

    # 发送全量地图
    await websocket.send(json.dumps({
        "type": "voxel_full",
        "ts": time.time(),
        "voxels": voxel_world,
    }))
    print(f"  → voxel_full: {len(voxel_world)} cells")

    # 发送路径
    await websocket.send(json.dumps({
        "type": "path",
        "ts": time.time(),
        "points": path,
    }))
    print(f"  → path: {len(path)} points")

    # 接收 + 发送循环
    pose_interval = 1.0 / POSE_HZ
    last_pose_time = 0.0
    pose_count = 0

    async def recv_loop():
        """接收 ctrl 指令"""
        nonlocal car
        async for msg in websocket:
            try:
                data = json.loads(msg)
                if data.get("type") == "ctrl":
                    car.handle_ctrl(data)
                    print(f"  ← ctrl: {data.get('key')} {data.get('action')}")
                    if data.get("key") == "space":
                        print("  🛑 ESTOP!")
            except json.JSONDecodeError:
                print(f"  ← bad json: {msg[:50]}")

    # 并行：接收 + 定时发送
    recv_task = asyncio.create_task(recv_loop())

    try:
        while True:
            now = time.time()
            dt = min(now - last_pose_time if last_pose_time else pose_interval, 0.1)
            last_pose_time = now

            car.update(dt)
            pose = car.to_dict()
            await websocket.send(json.dumps(pose))

            # 每 10 条打印一次位置（减少刷屏）
            pose_count += 1
            if pose_count % 10 == 0:
                print(f"  → pose #{pose_count}: x={pose['x']:.2f}, z={pose['z']:.2f}, yaw={pose['yaw']:.2f}, vx={pose['vx']:.2f}, vz={pose['vz']:.2f}")

            await asyncio.sleep(pose_interval)

    except websockets.exceptions.ConnectionClosed:
        print(f"[-] client disconnected: {websocket.remote_address}")
    finally:
        recv_task.cancel()


# ─── main ────────────────────────────────────────────────────

async def main():
    # 优雅退出
    stop = asyncio.Event()

    def _sig_handler(signum, frame):
        print("\n[!] shutting down...")
        stop.set()

    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)

    async with serve(handler, HOST, PORT):
        print(f"Mock Car Server listening on ws://{HOST}:{PORT}")
        print("Press Ctrl-C to stop\n")
        await stop.wait()


if __name__ == "__main__":
    asyncio.run(main())
