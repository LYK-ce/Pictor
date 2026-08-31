# Presented by KeJi
# Date ： 2026-08-31
#
# STT 本地推理服务（faster-whisper）
#
# 用法：
#   pip install -r requirements.txt
#   python tool/stt_server.py
#
# 接口：
#   POST /transcribe
#     body: {"audio_base64": "<wav 的 base64>"}
#     成功 → {"text": "..."}
#     忙   → {"busy": true}
#     失败 → {"error": "..."}
#
# 说明：
#   - 三状态状态机（READY → INFERENCING → RETURN）：推理中收到新请求直接回 busy（单任务）。
#   - 模型首次启动时加载；音频重采样（44.1kHz/stereo → 16kHz/mono）由 faster-whisper 内部自动完成。
#   - 本服务只跑模型，不做任何下游（文本由 Godot 端打印）。

import base64
import io

from fastapi import FastAPI
from faster_whisper import WhisperModel

# ===== 配置 =====
MODEL_SIZE = "medium"   # 可改 "large-v3"（更准但吃显存，约 3GB）
LANGUAGE = "zh"         # 识别语言；改 None 则自动检测
BEAM_SIZE = 5           # 越大越准但越慢
HOST = "127.0.0.1"
PORT = 9881
# =================

app = FastAPI()

_model = None
_busy = False


def get_model() -> WhisperModel:
    """懒加载模型；device="auto" 自动选 GPU/CPU，compute_type 默认（GPU float16 / CPU int8）。"""
    global _model
    if _model is None:
        _model = WhisperModel(MODEL_SIZE, device="auto")
    return _model


@app.post("/transcribe")
def transcribe(req: dict):
    global _busy
    if _busy:
        return {"busy": True}
    _busy = True
    try:
        audio_b64 = req.get("audio_base64", "")
        if not audio_b64:
            return {"error": "empty audio_base64"}
        audio_bytes = base64.b64decode(audio_b64)
        model = get_model()
        segments, _info = model.transcribe(
            io.BytesIO(audio_bytes),
            language=LANGUAGE,
            beam_size=BEAM_SIZE,
        )
        text = "".join(seg.text for seg in segments).strip()
        return {"text": text}
    except Exception as exc:  # noqa: BLE001
        return {"error": str(exc)}
    finally:
        _busy = False


if __name__ == "__main__":
    import uvicorn

    print(f"[STT] loading model '{MODEL_SIZE}' ...")
    get_model()
    print("[STT] model ready")
    uvicorn.run(app, host=HOST, port=PORT)
