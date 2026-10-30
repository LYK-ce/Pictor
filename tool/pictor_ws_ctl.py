#!/usr/bin/env python3
# Presented by KeJi
# Created Date ： 2026-10-29
# Modified Date ： 2026-10-29
#
# pictor_ws_ctl.py — Pictor WS 命令通道的 Python 控制脚本（task_40 Step 3 / 任务文档 §四）
#
# 定位：外部 Python 进程通过 Pictor 下发 `TASK_SET` / 模式、读回 `pose` / `peer_*`，
#       **不需要懂 ORION 字节**（编解码全在 Pictor 的 `src/kernel/ws_command_server.gd`）。
#
# ⚠️ `ack` 只代表「已交给 kernel」，**不代表车端收到**（任务文档 §四.5）：
#   本脚本判"到达"只用上行事件（`pose` 的 `valid` / `gx` / `gy`），双信号判定：
#     (a) 先见到 `valid==1`，再连续 N 帧 `valid==0`          → arrival_signal="valid_zero"
#     (b) 连续 N 帧 `hypot(x-target_x, y-target_y) <= tol`    → arrival_signal="converge"
#   另加一条合理性闸门：到达时终点误差 `final_err_m <= 2.0`（防"假到达"，不替代双信号）。
#
# 用法：
#   python3 Pictor/tool/pictor_ws_ctl.py vehicles [--port 9100] [--json]
#   python3 Pictor/tool/pictor_ws_ctl.py wait   --target ugv_1 [--timeout 40]
#   python3 Pictor/tool/pictor_ws_ctl.py task   --target ugv_1 --x 70 --y 64 [--tol 0.3] [--frames 3]
#   python3 Pictor/tool/pictor_ws_ctl.py follow --target uav_1 [--x 0 --y 0] [--type 2] [--watch 45]
#   python3 Pictor/tool/pictor_ws_ctl.py monitor [--seconds 10] [--pose-hz 2] [--events pose,peer]
#
# `follow` 走 type=2（仅 WS 入口；`x`/`y` 在 Follow 语义下预留填 0）；
# `--type 3` 只作「未知类型仍被降级」的探针（Pictor 会降级成 0 并告警）。
#
# 退出码：0 = 断言通过；1 = 断言失败；2 = 环境错误（连不上 / 无 websockets / 参数非法）。
#
# 依赖：`websockets`（见同目录 requirements.txt；本机 15.0.1）+ 标准库。

import argparse
import asyncio
import json
import math
import struct
import sys
import time

try:
    import websockets
except ImportError:  # 环境错误 → 退出码 2（不让 traceback 冒充断言失败）
    print("缺少依赖 websockets（pip install -r Pictor/tool/requirements.txt）", file=sys.stderr)
    sys.exit(2)

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_ENV = 2

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 9100
DEFAULT_POSE_HZ = 2.0          # §八 #5
DEFAULT_EVENTS = "pose,peer"   # §八 #5
DEFAULT_TOL_M = 0.3
DEFAULT_FRAMES = 3
DEFAULT_TIMEOUT_S = 120.0
DEFAULT_REGISTER_TIMEOUT_S = 40.0   # mDNS 发现窗口（plan P5 step 5 同量级）
DEFAULT_CONNECT_TIMEOUT_S = 5.0
PING_INTERVAL_S = 10.0
# 到达时终点误差闸门（防"假到达"；不替代双信号，见文件头）。
FINAL_ERR_GATE_M = 2.0

KNOWN_EVENTS = ("pose", "peer", "map_delta", "map_full")

# ─── mission type（task_40 Step 4；与 `ProtocolDef` 同一套约定）─────────────
# 车端 `command_decode` 认 {0 Goto, 2 Follow}；Pictor 的 `Encode_Task_Set` 对 ∉{0,2}
# 的条目降级成 0 并告警。下面这些常量**只用于本地断言/日志**，真编码在 GDScript 侧。
MISSION_TYPE_GOTO = 0
MISSION_TYPE_FOLLOW = 2
SUPPORTED_MISSION_TYPES = (MISSION_TYPE_GOTO, MISSION_TYPE_FOLLOW)
FOLLOW_POSE_HZ = 10.0          # follow 的 pose 采样率（K3 要用 10 Hz 判"不打转"）
# type=2、x=y=0 的 TASK_SET payload 金标（与 GDScript 单测同一枚）
FOLLOW_GOLDEN_HEX = "01020000000000000000"


class CtlError(Exception):
    """环境错误（连不上 / 连接中途断）→ 退出码 2。"""


class Client:
    """一个 WS 连接 + 一条读协程；ack 与事件在同一队列里按到达顺序消费。"""

    def __init__(self, url, connect_timeout=DEFAULT_CONNECT_TIMEOUT_S):
        self.url = url
        self.connect_timeout = connect_timeout
        self.ws = None
        self._queue = asyncio.Queue()
        self._reader_task = None
        self._pending = []
        self._next_id = 1

    async def connect(self):
        try:
            self.ws = await websockets.connect(
                self.url, open_timeout=self.connect_timeout, ping_interval=PING_INTERVAL_S
            )
        except (OSError, asyncio.TimeoutError, websockets.WebSocketException) as exc:
            raise CtlError("连不上 %s（%r）" % (self.url, exc))
        self._reader_task = asyncio.create_task(self._reader())
        return self

    async def _reader(self):
        try:
            async for raw in self.ws:
                try:
                    self._queue.put_nowait(json.loads(raw))
                except (json.JSONDecodeError, TypeError):
                    self._queue.put_nowait({"event": "<bad json>", "raw": str(raw)[:200]})
        except Exception:  # 连接被对端关掉 / 传输层错误：交给 next_msg 的 closed 标记
            pass
        finally:
            self._queue.put_nowait({"event": "<closed>"})

    async def close(self):
        if self._reader_task is not None:
            self._reader_task.cancel()
            self._reader_task = None
        if self.ws is not None:
            try:
                await self.ws.close()
            except Exception:
                pass
            self.ws = None

    def abort(self):
        """裸断（不握手 close 帧）：验证 Pictor 侧断连不崩（判据 5）。"""
        if self.ws is None:
            return
        try:
            self.ws.transport.abort()
        except Exception:
            pass

    async def next_msg(self, timeout):
        """取一条消息（先吃等待回执期间攒下的）；超时返回 None；连接关闭返回 {"event": "<closed>"}。"""
        if self._pending:
            return self._pending.pop(0)
        return await self._next_from_queue(timeout)

    async def _next_from_queue(self, timeout):
        """只从网络队列取（**不看 _pending**）。

        `cmd()` 必须用它：若先把事件塞回 _pending 再从中取，就会一直取回同一条事件、
        永远读不到后面的 ack（真机上是"2 台车 10 Hz 时新连接拿不到 ack"的根因）。
        """
        try:
            return await asyncio.wait_for(self._queue.get(), max(timeout, 0.001))
        except asyncio.TimeoutError:
            return None

    async def cmd(self, body, timeout=5.0):
        """发一条命令并等它的 ack（期间到达的事件留在 _pending 里不丢）。"""
        body = dict(body)
        if "id" not in body:
            body["id"] = self._next_id
            self._next_id += 1
        rid = body["id"]
        try:
            await self.ws.send(json.dumps(body, ensure_ascii=False))
        except Exception as exc:
            raise CtlError("发送失败（%r）" % (exc,))
        deadline = time.monotonic() + timeout
        while True:
            remain = deadline - time.monotonic()
            if remain <= 0:
                raise CtlError("等 ack(id=%s) 超时 %.1f s" % (rid, timeout))
            msg = await self._next_from_queue(remain)
            if msg is None:
                continue
            if msg.get("event") == "<closed>":
                raise CtlError("等待 ack 时连接被关闭")
            if "ack" in msg and int(msg.get("ack", -1)) == int(rid):
                return msg
            self._pending.append(msg)      # 期间到达的事件留到后面消费，不丢

    async def wait_event(self, name, timeout):
        """等某类事件（先吃 _pending 里的）。

        ⚠️ 不能"取出 → 不匹配 → 塞回 _pending"：下轮又会取回同一条，永远读不到后面的事件
        （`vehicles` 的 ack 与 event 同帧发，事件排在后面，就会假超时）。不匹配的先攒在 keep，
        退出时按原顺序放回 _pending。
        """
        deadline = time.monotonic() + timeout
        keep = []
        try:
            while True:
                remain = deadline - time.monotonic()
                if remain <= 0:
                    return None
                msg = self._pending.pop(0) if self._pending else await self._next_from_queue(remain)
                if msg is None:
                    continue
                if msg.get("event") == "<closed>":
                    raise CtlError("等待 event=%s 时连接被关闭" % name)
                if msg.get("event") == name:
                    return msg
                keep.append(msg)
        finally:
            if keep:
                self._pending = keep + self._pending


# ================================================================ 工具


def log(msg, quiet=False):
    if not quiet:
        print(msg, file=sys.stderr, flush=True)


def parse_csv(text):
    if text is None:
        return []
    return [x.strip() for x in str(text).split(",") if x.strip()]


def parse_float_list(text):
    out = []
    for item in parse_csv(text):
        try:
            out.append(float(item))
        except ValueError:
            raise CtlError("参数不是数值：%r" % item)
    return out


async def query_vehicles(client, timeout=5.0):
    """查一次车列表 → list[{name, vid, node_type}]（失败抛 CtlError）。"""
    ack = await client.cmd({"cmd": "vehicles"}, timeout)
    if not ack.get("ok", False):
        raise CtlError("vehicles 被拒：%s" % ack.get("error", "<无 error>"))
    msg = await client.wait_event("vehicles", timeout)
    if msg is None:
        raise CtlError("vehicles 没有返回列表")
    return msg.get("list", [])


def find_vehicle(rows, token):
    """按车名或 hex vid 解析 → (row, resolved_by)；找不到 → (None, "")。"""
    for row in rows:
        if str(row.get("vid", "")) == token:
            return row, "vid"
    for row in rows:
        if str(row.get("name", "")) == token:
            return row, "name"
    return None, ""


async def wait_registered(client, token, deadline_s):
    """轮询车列表直到 token（车名或 vid）出现；返回 (row, resolved_by)，超时 (None, "")。"""
    t0 = time.monotonic()
    while time.monotonic() - t0 < deadline_s:
        rows = await query_vehicles(client)
        row, how = find_vehicle(rows, token)
        if row is not None:
            return row, how
        await asyncio.sleep(0.5)
    return None, ""


async def maybe_abort(client, args):
    """P8 断连探针：拿到 handshake 后按 --close-after 到点裸断（abort）或 --close-abrupt 立即断。"""
    if not (args.close_abrupt or args.close_after is not None):
        return False
    delay = 0.0 if args.close_abrupt else max(0.0, float(args.close_after))
    if delay > 0:
        await asyncio.sleep(delay)
    client.abort()
    log("[ctl] 已按 --close-%s 裸断连接（不握手）" % ("abrupt" if args.close_abrupt else "after"), args.quiet)
    return True


def emit_json(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def expected_task_set_payload(missions):
    """按 ORION_TASK_SET 布局（1 + 9n，type u8 | x f32 BE | y f32 BE）复刻 payload。

    ⚠️ 这**不是协议实现**（真编码在 `src/websocket/protocol/orion_messages.gd`），
    只用来在这里断言"将要发出去的帧"符合预期、并把 hex 记进 `--json` 便于比对。
    降级规则与 `Encode_Task_Set` 一致：type ∉ {0,2} → 0（车端会丢，故本地先降级告警）。
    """
    out = bytearray([len(missions)])
    types, coerced = [], []
    for m in missions:
        t = m.get("type", MISSION_TYPE_GOTO)
        if isinstance(t, str):
            key = t.strip().lower()
            if key == "follow":
                t = MISSION_TYPE_FOLLOW
            elif key == "goto":
                t = MISSION_TYPE_GOTO
            else:
                t = MISSION_TYPE_GOTO
        else:
            try:
                t = int(t)
            except (TypeError, ValueError):
                t = MISSION_TYPE_GOTO
        co = t not in SUPPORTED_MISSION_TYPES
        wire = MISSION_TYPE_GOTO if co else t
        types.append(wire)
        coerced.append(co)
        out.append(wire & 0xFF)
        out += struct.pack(">f", float(m.get("x", 0.0)))
        out += struct.pack(">f", float(m.get("y", 0.0)))
    return {"hex": out.hex(), "len": len(out), "types": types, "coerced": coerced}


def fail_json(obj, code=EXIT_FAIL, quiet=False):
    emit_json(obj)
    log("[ctl] 失败：%s" % obj.get("error", obj), quiet)
    return code


# ================================================================ 子命令


async def cmd_vehicles(client, args):
    rows = await query_vehicles(client)
    if not args.quiet:
        log("[ctl] 已注册 %d 台车" % len(rows), args.quiet)
        for row in rows:
            log("  name=%-16s vid=%s node_type=%s"
                % (row.get("name", ""), row.get("vid", ""), row.get("node_type", "")), args.quiet)
    if args.json:
        emit_json({"ok": True, "count": len(rows), "list": rows})
    return EXIT_OK


async def cmd_wait(client, args):
    t0 = time.monotonic()
    row, how = await wait_registered(client, args.target, args.timeout)
    elapsed = round(time.monotonic() - t0, 3)
    ok = row is not None
    out = {
        "ok": ok,
        "target": args.target,
        "target_vid": row.get("vid", "") if ok else "",
        "resolved_by": how,
        "waited_s": elapsed,
    }
    if not ok:
        out["error"] = "target not registered: %s（%.1f s）" % (args.target, args.timeout)
        if args.json:
            return fail_json(out, EXIT_FAIL, args.quiet)
        log("[ctl] FAIL %s" % out["error"], args.quiet)
        return EXIT_FAIL
    log("[ctl] 已注册：%s (vid=%s, %s) 用时 %.2f s"
        % (args.target, out["target_vid"], how, elapsed), args.quiet)
    if args.json:
        emit_json(out)
    return EXIT_OK


async def cmd_task(client, args):
    t_start = time.monotonic()
    deadline = t_start + args.timeout
    # ① 等注册（车名或 hex vid）。等不到也照样发：让 Pictor 给出明确失败（判据 5，不静默）。
    reg_window = min(args.register_timeout, max(1.0, args.timeout * 0.5))
    row, how = await wait_registered(client, args.target, reg_window)
    target_vid = str(row.get("vid", "")) if row is not None else ""
    log("[ctl] 目标 %s → vid=%s（resolved_by=%s）" % (args.target, target_vid, how or "<未注册>"),
        args.quiet)

    # ② 订阅 pose（发前就要开，才能拿到"发前快照"）
    targets = args.targets or [args.target]
    ack = await client.cmd({"cmd": "subscribe", "events": ["pose"],
                            "pose_hz": args.pose_hz, "targets": targets})
    if not ack.get("ok", False):
        return fail_json({"ok": False, "ack_ok": False, "target": args.target,
                          "error": "subscribe 被拒：%s" % ack.get("error", "<无 error>")},
                         EXIT_FAIL, args.quiet)

    # ③ 发前快照（gx/gy/valid；等不到就没有"变化"证据，判据会因此为 FAIL）
    pre = await client.wait_event("pose", min(10.0, max(1.0, deadline - time.monotonic())))
    first_pose = pre or {}
    have_pre = pre is not None
    pre_key = (first_pose.get("gx"), first_pose.get("gy")) if have_pre else (None, None)
    log("[ctl] 发前快照 x=%.2f y=%.2f valid=%s gx=%s gy=%s"
        % (float(first_pose.get("x", 0.0)), float(first_pose.get("y", 0.0)),
           first_pose.get("valid"), first_pose.get("gx"), first_pose.get("gy")), args.quiet)

    # ④ 模式（默认不发：sim 默认就是 Auto，§八 / plan §1.3）
    if args.mode and args.mode != "none":
        mack = await client.cmd({"cmd": "mode", "targets": targets, "to": args.mode})
        if not mack.get("ok", False):
            return fail_json({"ok": False, "ack_ok": False, "target": args.target,
                              "error": "mode 被拒：%s" % mack.get("error", "<无 error>")},
                             EXIT_FAIL, args.quiet)
        log("[ctl] mode → %s 已下发（ack 生效）" % args.mode, args.quiet)

    # ⑤ 发 task_set（missions[0] 就是这台车自己的点；一帧一车）
    mission = {"type": 0, "x": float(args.x), "y": float(args.y)}
    sent_at = time.time()
    ack = await client.cmd({"cmd": "task_set", "targets": targets, "missions": [mission]})
    ack_ok = bool(ack.get("ok", False))
    if not ack_ok:
        out = {
            "ok": False, "ack_ok": False, "target": args.target,
            "target_vid": target_vid, "resolved_by": how,
            "error": ack.get("error", "<无 error>"),
            "sent_at": sent_at, "mission": mission,
        }
        # 未注册车：这就是判据 5 要求的"明确失败"，退出码 1（不是静默成功）
        return fail_json(out, EXIT_FAIL, args.quiet)
    log("[ctl] task_set 已交给 kernel（ack.id=%s；⚠ 不等于车端收到）" % ack.get("ack"), args.quiet)

    # ack 通过说明 Pictor 侧解析到了车 ⇒ 若之前没等到注册，这里补一次解析（拿 vid 过滤 pose）
    if not target_vid:
        row, how = await wait_registered(client, args.target, 5.0)
        target_vid = str(row.get("vid", "")) if row is not None else ""
        if target_vid:
            sack = await client.cmd({"cmd": "subscribe", "events": ["pose"],
                                     "pose_hz": args.pose_hz, "targets": [args.target]})
            log("[ctl] 补订阅 targets=[%s] ack_ok=%s" % (args.target, sack.get("ok")), args.quiet)

    # ⑥ 收 pose → 判到达（双信号 + 终点误差闸门）
    seen_active = False
    consec_zero = 0
    consec_near = 0
    sub_target_seq = 0
    poses = []
    arrival_signal = ""
    arrival_s = None
    final_err = float("inf")
    while time.monotonic() < deadline:
        msg = await client.next_msg(max(0.05, deadline - time.monotonic()))
        if msg is None:
            continue
        if msg.get("event") == "<closed>":
            raise CtlError("判到达期间连接被关闭")
        if msg.get("event") != "pose":
            continue
        if target_vid and str(msg.get("vid", "")) != target_vid:
            continue
        poses.append(msg)
        key = (msg.get("gx"), msg.get("gy"))
        if have_pre and key != pre_key:
            sub_target_seq += 1
            pre_key = key
        err = math.hypot(float(msg.get("x", 0.0)) - float(args.x),
                         float(msg.get("y", 0.0)) - float(args.y))
        if err <= float(args.tol):
            consec_near += 1
        else:
            consec_near = 0
        if int(msg.get("valid", 0)) == 1:
            seen_active = True
            consec_zero = 0
        elif seen_active:
            consec_zero += 1
        if seen_active and consec_zero >= args.frames:
            arrival_signal = "valid_zero"
            final_err = err
            arrival_s = round(time.monotonic() - t_start, 3)
            break
        if consec_near >= args.frames:
            arrival_signal = "converge"
            final_err = err
            arrival_s = round(time.monotonic() - t_start, 3)
            break

    pose_frames = len(poses)
    out = {
        "ok": False,
        "ack_ok": True,
        "target": args.target,
        "target_vid": target_vid,
        "resolved_by": how,
        "sent_at": sent_at,
        "mission": mission,
        "pre_pose": first_pose,
        "sub_target_changed": sub_target_seq > 0,
        "sub_target_seq": sub_target_seq,
        "arrival_signal": arrival_signal,
        "arrival_s": arrival_s,
        "final_err_m": None if arrival_signal == "" else round(final_err, 3),
        "pose_frames": pose_frames,
        "poses": poses[-40:],
    }
    if arrival_signal == "":
        out["error"] = ("%.1f s 内未判到到达（poses=%d，tol=%.2f m，frames=%d）"
                        % (args.timeout, pose_frames, float(args.tol), args.frames))
        out["last_err_m"] = round(final_err, 3) if pose_frames else None
        log("[ctl] FAIL %s" % out["error"], args.quiet)
        if args.json:
            emit_json(out)
            return EXIT_FAIL
        return EXIT_FAIL
    if final_err > FINAL_ERR_GATE_M:
        out["error"] = "到达信号 %s 但终点误差 %.2f m > %.1f m（判为假到达）" % (
            arrival_signal, final_err, FINAL_ERR_GATE_M)
        log("[ctl] FAIL %s" % out["error"], args.quiet)
        if args.json:
            emit_json(out)
            return EXIT_FAIL
        return EXIT_FAIL
    if not out["sub_target_changed"]:
        out["error"] = "pose.sub_target 未变化（gx/gy 与发前快照相同），任务没进决策链"
        log("[ctl] FAIL %s" % out["error"], args.quiet)
        if args.json:
            emit_json(out)
            return EXIT_FAIL
        return EXIT_FAIL
    out["ok"] = True
    log("[ctl] 到达：signal=%s arrival=%.2f s final_err=%.2f m poses=%d → %s"
        % (arrival_signal, float(arrival_s), final_err, pose_frames, args.target), args.quiet)
    if args.json:
        emit_json(out)
    return EXIT_OK


async def cmd_follow(client, args):
    """发一帧 `TASK_SET`（默认 type=2 Follow），断言帧布局，并可 `--watch N` 秒采样 pose。

    Follow 语义下 `x`/`y` 预留填 0（任务文档 §五.6：不改 Follow{x,y} 语义）。
    `--type 3` 只作判据 4 的探针：本地先按同一规则算出"Pictor 会降级成 0"，再发出去比对。
    """
    t_start = time.monotonic()
    reg_window = min(args.register_timeout, max(1.0, args.timeout * 0.5))
    row, how = await wait_registered(client, args.target, reg_window)
    target_vid = str(row.get("vid", "")) if row is not None else ""
    log("[ctl] 目标 %s → vid=%s（resolved_by=%s）"
        % (args.target, target_vid, how or "<未注册>"), args.quiet)

    targets = args.targets or [args.target]
    mission = {"type": int(args.type), "x": float(args.x), "y": float(args.y)}
    spec = expected_task_set_payload([mission])
    type_on_wire = spec["types"][0]
    coerced = bool(spec["coerced"][0])
    if coerced:
        log("[ctl] 注意：--type %s 不在 {0,2} → Pictor 会降级成 0 并告警（判据 4 的探针）"
            % args.type, args.quiet)

    out = {
        "ok": False,
        "cmd": "follow",
        "target": args.target,
        "target_vid": target_vid,
        "resolved_by": how,
        "mission": mission,
        "payload_hex": spec["hex"],
        "payload_len": spec["len"],
        "type_on_wire": type_on_wire,
        "coerced": coerced,
    }

    # ① 先订阅 pose（--watch 采样要用；发前开，避免丢首帧）
    ack = await client.cmd({"cmd": "subscribe", "events": ["pose"],
                            "pose_hz": args.pose_hz, "targets": targets})
    if not ack.get("ok", False):
        out["error"] = "subscribe 被拒：%s" % ack.get("error", "<无 error>")
        return fail_json(out, EXIT_FAIL, args.quiet)

    # ② 模式（默认不发：sim 默认就是 Auto）
    if args.mode and args.mode != "none":
        mack = await client.cmd({"cmd": "mode", "targets": targets, "to": args.mode})
        if not mack.get("ok", False):
            out["error"] = "mode 被拒：%s" % mack.get("error", "<无 error>")
            return fail_json(out, EXIT_FAIL, args.quiet)
        log("[ctl] mode → %s 已下发（ack 生效）" % args.mode, args.quiet)

    # ③ 本地帧布局断言（不合规就不发，避免把错帧算到 Pictor 头上）
    bad = []
    if spec["len"] != 1 + 9 * 1:
        bad.append("payload_len=%d（期望 %d）" % (spec["len"], 1 + 9))
    if int(spec["hex"][0:2], 16) != 1:
        bad.append("mission_count=%s（期望 1）" % spec["hex"][0:2])
    if int(spec["hex"][2:4], 16) != type_on_wire:
        bad.append("type 字节=%s（期望 %d）" % (spec["hex"][2:4], type_on_wire))
    if int(args.type) == MISSION_TYPE_FOLLOW and float(args.x) == 0.0 and float(args.y) == 0.0:
        if spec["hex"] != FOLLOW_GOLDEN_HEX:
            bad.append("金标不符 %s（期望 %s）" % (spec["hex"], FOLLOW_GOLDEN_HEX))
    if bad:
        out["error"] = "本地帧布局断言失败：" + "；".join(bad)
        return fail_json(out, EXIT_FAIL, args.quiet)

    # ④ 发 task_set（missions[0] 就是这台车的点；一帧一车）
    sent_at = time.time()
    out["sent_at"] = sent_at
    ack = await client.cmd({"cmd": "task_set", "targets": targets, "missions": [mission]})
    out["ack"] = ack.get("ack")
    if not ack.get("ok", False):
        out["ack_ok"] = False
        out["error"] = ack.get("error", "<无 error>")
        return fail_json(out, EXIT_FAIL, args.quiet)
    out["ack_ok"] = True
    log("[ctl] task_set 已交给 kernel：type=%d→wire %d payload=%s（%d B；⚠ 不等于车端收到）"
        % (int(args.type), type_on_wire, spec["hex"], spec["len"]), args.quiet)

    # ⑤ --watch：按 pose_hz 采样位姿帧（K3 的轨迹证据；不判定到达）
    samples = 0
    watch_s = 0.0
    poses = []
    if args.watch > 0:
        w_t0 = time.monotonic()
        w_deadline = w_t0 + args.watch
        while time.monotonic() < w_deadline:
            msg = await client.next_msg(max(0.05, w_deadline - time.monotonic()))
            if msg is None:
                continue
            if msg.get("event") == "<closed>":
                raise CtlError("采样期间连接被关闭")
            if msg.get("event") != "pose":
                continue
            if target_vid and str(msg.get("vid", "")) != target_vid:
                continue
            poses.append({
                "t_wall": round(time.time(), 3),
                "x": float(msg.get("x", 0.0)),
                "y": float(msg.get("y", 0.0)),
                "yaw": float(msg.get("yaw", 0.0)),
                "valid": int(msg.get("valid", 0)),
                "t_ms": int(msg.get("t_ms", 0)),
                "target": [msg.get("gx"), msg.get("gy")],
            })
        watch_s = round(time.monotonic() - w_t0, 3)
        samples = len(poses)
        out["samples"] = samples
        out["watch_s"] = watch_s
        out["poses"] = poses
        log("[ctl] 采样 %.1f s：poses=%d（pose_hz=%s）" % (watch_s, samples, args.pose_hz), args.quiet)

    out["ok"] = True
    if args.json:
        emit_json(out)
    return EXIT_OK


async def cmd_monitor(client, args):
    events = parse_csv(args.events)
    for name in events:
        if name not in KNOWN_EVENTS:
            return fail_json({"ok": False, "error": "unknown event: %s" % name}, EXIT_FAIL, args.quiet)
        if name in ("map_delta", "map_full"):
            log("[ctl] 注意：订阅 %s 会给每个客户端推元数据（默认不订阅）" % name, args.quiet)
    ack = await client.cmd({"cmd": "subscribe", "events": events, "pose_hz": args.pose_hz,
                            "targets": args.targets})
    if not ack.get("ok", False):
        return fail_json({"ok": False, "error": "subscribe 被拒：%s" % ack.get("error", "")},
                         EXIT_FAIL, args.quiet)
    counts = {"pose": 0, "peer_connected": 0, "peer_info": 0, "peer_disconnected": 0,
              "map_delta": 0, "map_full": 0, "vehicles": 0}
    per_vid = {}
    head = []
    tail = []
    t0 = time.monotonic()
    while time.monotonic() - t0 < args.seconds:
        msg = await client.next_msg(max(0.05, args.seconds - (time.monotonic() - t0)))
        if msg is None:
            continue
        if msg.get("event") == "<closed>":
            raise CtlError("监视期间连接被关闭")
        if "ack" in msg:
            continue
        name = str(msg.get("event", ""))
        if name not in counts:
            counts[name] = 0
        counts[name] += 1
        if name == "pose":
            vid = str(msg.get("vid", ""))
            per_vid[vid] = per_vid.get(vid, 0) + 1
        if len(head) < 6:
            head.append(msg)                  # 首 6 条
        else:
            tail.append(msg)
            if len(tail) > 3:
                tail.pop(0)                   # 末 3 条
    elapsed = max(1e-6, time.monotonic() - t0)
    hz = {vid: round(n / elapsed, 2) for vid, n in per_vid.items()}
    out = {
        "ok": True,
        "seconds": round(elapsed, 2),
        "events_subscribed": events,
        "pose_hz": args.pose_hz,
        "counts": counts,
        "per_vid_pose": per_vid,
        "hz_measured": hz,
        "events": head + tail,
    }
    log("[ctl] 监视 %.1f s：%s per_vid=%s hz=%s"
        % (elapsed, {k: v for k, v in counts.items() if v}, per_vid, hz), args.quiet)
    if args.json:
        emit_json(out)
    return EXIT_OK


# ================================================================ CLI


def build_parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--url", default=None, help="完整 WS 地址（给了就不看 --port）")
    common.add_argument("--port", type=int, default=DEFAULT_PORT, help="Pictor 的 --ws-port（默认 9100）")
    common.add_argument("--host", default=DEFAULT_HOST)
    common.add_argument("--pose-hz", type=float, default=None,
                        help="pose 降频（默认：follow 为 10，其余为 %g；0 = 不限频）" % DEFAULT_POSE_HZ)
    common.add_argument("--events", default=DEFAULT_EVENTS,
                        help="订阅的事件集，逗号分隔（可用 pose/peer/map_delta/map_full）")
    common.add_argument("--targets", default="", help="按车名/vid 过滤，逗号分隔；空 = 全部")
    common.add_argument("--json", action="store_true", help="stdout 只输出一行 JSON（机读）")
    common.add_argument("--quiet", action="store_true", help="不打人类可读日志")
    common.add_argument("--connect-timeout", type=float, default=DEFAULT_CONNECT_TIMEOUT_S)
    common.add_argument("--close-abrupt", action="store_true",
                        help="拿到 handshake 后立刻裸断（断连探针，判据 5）")
    common.add_argument("--close-after", type=float, default=None,
                        help="拿到 handshake 后等 N 秒再裸断（断连探针）")

    ap = argparse.ArgumentParser(
        prog="pictor_ws_ctl.py",
        description="Pictor WS 命令通道控制脚本（task_40 Step 3）；退出码 0/1/2 = 通过/断言失败/环境错误")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("vehicles", parents=[common], help="查已注册车列表")
    p.set_defaults(func=cmd_vehicles)

    p = sub.add_parser("wait", parents=[common], help="等某台车注册")
    p.add_argument("--target", required=True, help="车名或 hex vid")
    p.add_argument("--timeout", type=float, default=DEFAULT_REGISTER_TIMEOUT_S)
    p.set_defaults(func=cmd_wait)

    p = sub.add_parser("task", parents=[common], help="等注册 → 发 task_set → 判到达（一次运行完成）")
    p.add_argument("--target", required=True, help="车名或 hex vid")
    p.add_argument("--x", type=float, required=True, help="目标 x（世界米）")
    p.add_argument("--y", type=float, required=True, help="目标 y（世界米）")
    p.add_argument("--tol", type=float, default=DEFAULT_TOL_M, help="到达容差（米，默认 0.3）")
    p.add_argument("--frames", type=int, default=DEFAULT_FRAMES, help="连续帧数（默认 3）")
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_S)
    p.add_argument("--register-timeout", type=float, default=DEFAULT_REGISTER_TIMEOUT_S)
    p.add_argument("--mode", default="none", choices=["none", "auto", "manual"],
                   help="发任务前先切模式（默认 none：sim 默认已是 Auto）")
    p.set_defaults(func=cmd_task)

    p = sub.add_parser("follow", parents=[common],
                       help="发一帧 TASK_SET（默认 type=2 Follow），断言帧布局并可采样 pose")
    p.add_argument("--target", required=True, help="车名或 hex vid")
    p.add_argument("--x", type=float, default=0.0, help="Follow 语义下预留，默认 0")
    p.add_argument("--y", type=float, default=0.0, help="Follow 语义下预留，默认 0")
    p.add_argument("--type", type=int, default=MISSION_TYPE_FOLLOW,
                   help="mission type（默认 2=Follow；3 = 「未知类型仍降级」探针）")
    p.add_argument("--watch", type=float, default=0.0, help="发完采样 pose 的墙钟秒数（默认 0）")
    p.add_argument("--mode", default="auto", choices=["none", "auto", "manual"],
                   help="发之前先切模式（默认 auto）")
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_S)
    p.add_argument("--register-timeout", type=float, default=DEFAULT_REGISTER_TIMEOUT_S)
    p.set_defaults(func=cmd_follow)

    p = sub.add_parser("monitor", parents=[common], help="订阅并统计事件（判据 4 用）")
    p.add_argument("--seconds", type=float, default=10.0)
    p.set_defaults(func=cmd_monitor)
    return ap


def resolve_pose_hz(args):
    """`--pose-hz` 缺省值按子命令定：follow → 10 Hz（K3 轨迹），其余 → §八 #5 的 2 Hz。"""
    if args.pose_hz is not None:
        return float(args.pose_hz)
    return FOLLOW_POSE_HZ if args.cmd == "follow" else DEFAULT_POSE_HZ


def build_url(args):
    if args.url:
        return args.url
    return "ws://%s:%d" % (args.host, args.port)


def main(argv=None):
    ap = build_parser()
    args = ap.parse_args(argv)
    args.targets = parse_csv(args.targets)
    args.pose_hz = resolve_pose_hz(args)
    url = build_url(args)

    async def run():
        client = Client(url, connect_timeout=args.connect_timeout)
        try:
            await client.connect()
            log("[ctl] 已连上 %s" % url, args.quiet)
            if await maybe_abort(client, args):
                return EXIT_OK
            return await args.func(client, args)
        finally:
            await client.close()

    try:
        return asyncio.run(run())
    except CtlError as exc:
        if args.json:
            emit_json({"ok": False, "error": str(exc), "env": True})
        print("[ctl] 环境错误：%s" % exc, file=sys.stderr, flush=True)
        return EXIT_ENV
    except KeyboardInterrupt:
        return EXIT_ENV


if __name__ == "__main__":
    sys.exit(main())
