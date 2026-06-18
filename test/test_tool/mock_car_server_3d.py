#!/usr/bin/env python3
"""
mock_car_server_3d.py — 3D 小车端模拟器
发送多层体素 (gy 0~2)，3D pose (含 y 高度)，3D 路径。
"""

import asyncio
import json
import math
import signal
import time

import websockets
from websockets.asyncio.server import serve

HOST = "0.0.0.0"
PORT = 9090
POSE_HZ = 10.0


def build_voxel_world(size: int = 20) -> list[dict]:
    """20×20 网格，地面全空闲(gy=0)，(1,1)两格高柱，(5,3~5)矮墙"""
    voxels = []
    for gx in range(size):
        for gz in range(size):
            voxels.append({"gx": gx, "gy": 0, "gz": gz, "state": 1, "conf": 1.0})
    # Pillar at (1,1), gy=1 and gy=2
    for gy in [1, 2]:
        voxels.append({"gx": 1, "gy": gy, "gz": 1, "state": 2, "conf": 1.0})
    # Wall at gx=5, gz in [3,5], gy=1
    for gz in range(3, 6):
        voxels.append({"gx": 5, "gy": 1, "gz": gz, "state": 2, "conf": 1.0})
    return voxels


def build_path() -> list[dict]:
    """从 (10,0,10) 向北螺旋上升"""
    points = []
    for i in range(20):
        t = i / 19.0
        points.append({"x": 10.0 + 3.0 * math.sin(t * 4.0), "y": t * 3.0, "z": 10.0 - 5.0 * t})
    return points


class CarState:
    def __init__(self):
        self.x = 10.0
        self.y = 0.0
        self.z = 10.0
        self.yaw = -math.pi / 2.0
        self.pitch = 0.0
        self.vx = 0.0
        self.vy = 0.0
        self.vz = 0.0
        self.forward = False
        self.backward = False
        self.turn_left = False
        self.turn_right = False
        self.ascend = False   # Q 上升
        self.descend = False  # E 下降
        self.estop = False

    def update(self, dt: float):
        if self.estop:
            self.vx = self.vy = self.vz = 0.0
            return

        speed = 2.0
        turn_rate = math.radians(90)
        climb_rate = 1.0

        target_v = 0.0
        if self.forward:
            target_v = speed
        elif self.backward:
            target_v = -speed

        if self.turn_left:
            self.yaw -= turn_rate * dt
        if self.turn_right:
            self.yaw += turn_rate * dt

        self.vy = 0.0
        if self.ascend:
            self.vy = climb_rate
        elif self.descend:
            self.vy = -climb_rate

        self.vx = target_v * math.cos(self.yaw)
        self.vz = target_v * math.sin(self.yaw)

        self.x += self.vx * dt
        self.y += self.vy * dt
        self.z += self.vz * dt

    def handle_cmd(self, cmd: str):
        match cmd:
            case "forward":    self.forward = True
            case "backward":   self.backward = True
            case "spin_left":  self.turn_left = True
            case "spin_right": self.turn_right = True
            case "stop":
                self.forward = self.backward = False
                self.turn_left = self.turn_right = False
                self.ascend = self.descend = False
                self.estop = False

    def to_dict(self) -> dict:
        return {
            "type": "pose",
            "ts": time.time(),
            "x": round(self.x, 3),
            "y": round(self.y, 3),
            "z": round(self.z, 3),
            "yaw": round(self.yaw, 3),
            "pitch": round(self.pitch, 3),
            "vx": round(self.vx, 3),
            "vy": round(self.vy, 3),
            "vz": round(self.vz, 3),
        }


async def handler(websocket):
    print(f"[+] 3D client connected: {websocket.remote_address}")
    car = CarState()
    voxel_world = build_voxel_world(20)
    path = build_path()

    await websocket.send(json.dumps({"type": "voxel_full", "ts": time.time(), "voxels": voxel_world}))
    print(f"  → voxel_full: {len(voxel_world)} cells (multi-layer)")

    await websocket.send(json.dumps({"type": "path", "ts": time.time(), "points": path}))
    print(f"  → path: {len(path)} points (3D spiral)")

    pose_interval = 1.0 / POSE_HZ
    last_pose_time = 0.0
    pose_count = 0

    async def recv_loop():
        async for msg in websocket:
            try:
                data = json.loads(msg)
                if data.get("cmd"):
                    car.handle_cmd(data["cmd"])
                    print(f"  ← cmd: {data['cmd']}")
            except json.JSONDecodeError:
                print(f"  ← bad json: {msg[:50]}")

    recv_task = asyncio.create_task(recv_loop())

    try:
        while True:
            now = time.time()
            dt = min(now - last_pose_time if last_pose_time else pose_interval, 0.1)
            last_pose_time = now
            car.update(dt)
            pose = car.to_dict()
            await websocket.send(json.dumps(pose))
            pose_count += 1
            if pose_count % 10 == 0:
                print(f"  → pose #{pose_count}: x={pose['x']:.2f}, y={pose['y']:.2f}, z={pose['z']:.2f}, yaw={pose['yaw']:.2f}")
            await asyncio.sleep(pose_interval)
    except websockets.exceptions.ConnectionClosed:
        print(f"[-] client disconnected: {websocket.remote_address}")
    finally:
        recv_task.cancel()


async def main():
    stop = asyncio.Event()

    def _sig_handler(signum, frame):
        print("\n[!] shutting down...")
        stop.set()

    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)

    async with serve(handler, HOST, PORT):
        print(f"Mock Car Server 3D listening on ws://{HOST}:{PORT}")
        print("Controls: WASD + Q/E ascend/descend + Space estop")
        await stop.wait()


if __name__ == "__main__":
    asyncio.run(main())
