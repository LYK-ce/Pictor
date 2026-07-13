#!/usr/bin/env python3
"""
mock_vehicle.py — 2D 小车模拟器
启动后等待 Godot 连接，连接后发送一次 map_full 地图数据。
"""

import asyncio
import json
import signal
import time

import websockets
from websockets.asyncio.server import serve

HOST = "0.0.0.0"
PORT = 9090
MAP_SIZE = 50  # 测试用，缩小避免大消息断开


def build_map(size: int = MAP_SIZE) -> list[dict]:
    """生成 size×size 网格，随机障碍物"""
    import random
    random.seed(42)
    voxels = []
    for gx in range(size):
        for gy in range(size):
            is_wall = random.random() < 0.05  # 5% 概率为墙
            voxels.append({
                "gx": gx,
                "gy": gy,
                "gz": 0,
                "state": 1 if is_wall else 0,  # 0=可通行 1=不可通行
                "conf": 1.0,
            })
    return voxels


async def handler(websocket):
    addr = websocket.remote_address
    print(f"[+] client connected: {addr}")

    # 生成地图
    print("[*] building map...")
    voxels = build_map(MAP_SIZE)
    print(f"[*] map size: {len(voxels)} cells, ~{sum(1 for v in voxels if v['state']==1)} walls")

    # 发送 map_full
    msg = json.dumps({
        "type": "map_full",
        "ts": time.time(),
        "voxels": voxels,
    })
    print(f"[→] sending map_full ({len(msg)} bytes)")
    await websocket.send(msg)
    print(f"[✓] map_full sent, done")

    # 保持连接，不做其他操作
    print("[*] keeping connection alive (Ctrl-C to quit)")
    try:
        await websocket.wait_closed()
    except Exception:
        pass
    print(f"[-] client disconnected: {addr}")


async def main():
    stop = asyncio.Event()

    def _sig_handler(signum, frame):
        print("\n[!] shutting down...")
        stop.set()

    signal.signal(signal.SIGINT, _sig_handler)
    signal.signal(signal.SIGTERM, _sig_handler)

    async with serve(handler, HOST, PORT):
        print(f"Mock Vehicle Server listening on ws://{HOST}:{PORT}")
        print("Waiting for Godot to connect...\n")
        await stop.wait()


if __name__ == "__main__":
    asyncio.run(main())
