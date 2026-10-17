"""Run the opt-in Flutter V2 HTTP test against disposable local API/worker processes."""
from __future__ import annotations

import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path


FLUTTER_ROOT = Path(__file__).resolve().parents[1]
V2_ROOT = Path(r"D:\flutter\last\wellar-ai-v2")
V2_PYTHON = V2_ROOT / ".venv" / "Scripts" / "python.exe"
FLUTTER_BAT = Path(r"C:\flutter\bin\flutter.bat")
ADB = Path(r"C:\Users\Abdulrhman Nashat\AppData\Local\Android\Sdk\platform-tools\adb.exe")


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_ready(process: subprocess.Popen, url: str) -> None:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Disposable V2 service exited before readiness.")
        try:
            with opener.open(url, timeout=1) as response:
                if response.status == 200:
                    return
        except (OSError, urllib.error.URLError):
            time.sleep(0.2)
    raise RuntimeError("Disposable local V2 API did not become ready in 45 seconds.")


def verify_emulator_route(port: int) -> None:
    devices = subprocess.run([str(ADB), "devices"], capture_output=True, check=True).stdout
    if b"emulator-5554\tdevice" not in devices:
        raise RuntimeError("The installed Android emulator is not online in adb.")
    response = subprocess.run(
        [str(ADB), "-s", "emulator-5554", "shell", "toybox", "nc", "-z", "-w", "3",
         "10.0.2.2", str(port)],
        capture_output=True, timeout=8, check=False,
    )
    if response.returncode != 0:
        raise RuntimeError("Android emulator could not reach the disposable host API at 10.0.2.2.")


def stop(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


class RetryingTemporaryDirectory(tempfile.TemporaryDirectory):
    """Retry Windows SQLite WAL/shm cleanup while the OS releases file handles."""

    def cleanup(self) -> None:
        last_error = None
        for _ in range(10):
            try:
                shutil.rmtree(self.name)
                self._finalizer.detach()
                return
            except FileNotFoundError:
                self._finalizer.detach()
                return
            except OSError as error:
                last_error = error
                time.sleep(0.5)
        raise RuntimeError("Could not remove the disposable V2 state directory.") from last_error


def main() -> int:
    for path in (V2_PYTHON, FLUTTER_BAT, ADB):
        if not path.exists():
            raise RuntimeError(f"Required installed local tool is unavailable: {path}")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("An installed ffmpeg is required to generate the synthetic MP4 fixture.")

    token = secrets.token_urlsafe(32)
    port = free_port()
    api = worker = None
    with RetryingTemporaryDirectory(prefix="wellar-v2-phase1b-") as temporary:
        state = Path(temporary)
        media = state / "media"
        db = state / "queue.sqlite3"
        video = state / "synthetic.mp4"
        audio = state / "synthetic.wav"
        subprocess.run(
            [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi",
             "-i", "color=c=black:s=160x120:r=4:d=2", "-an", "-c:v", "libx264",
             "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(video)],
            check=True,
        )
        with wave.open(str(audio), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16000)
            output.writeframes(bytes(16000 * 2))

        env = os.environ.copy()
        env.update({
            "WELLAR_ENV": "test",
            "WELLAR_LOG_LEVEL": "WARNING",
            "WELLAR_DB_PATH": str(db),
            "WELLAR_MEDIA_ROOT": str(media),
            "WELLAR_QUEUE_BACKEND": "sqlite",
            "WELLAR_MEDIA_BACKEND": "local",
            "WELLAR_AUTH_MODE": "development",
            "WELLAR_DEV_AUTH_TOKENS_JSON": json.dumps({
                token: {"sub": "synthetic-user", "tenant_id": "synthetic-tenant"},
            }),
            "WELLAR_MEDIA_RETENTION_DAYS": "1",
            "DART_SUPPRESS_ANALYTICS": "true",
            "WELLAR_V2_LIVE_TEST": "1",
            "WELLAR_V2_LIVE_BASE_URL": f"http://127.0.0.1:{port}",
            "WELLAR_V2_LIVE_TOKEN": token,
            "WELLAR_V2_LIVE_VIDEO": str(video),
            "WELLAR_V2_LIVE_AUDIO": str(audio),
        })
        token = ""  # Do not retain the ephemeral credential beyond the child environment.
        worker_env = dict(env, WELLAR_LOG_LEVEL="ERROR")
        try:
            worker = subprocess.Popen(
                [str(V2_PYTHON), "-m", "app.workers.entrypoint"],
                cwd=V2_ROOT, env=worker_env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            api = subprocess.Popen(
                [str(V2_PYTHON), "-m", "uvicorn", "app.main:app", "--host",
                 "127.0.0.1", "--port", str(port), "--no-access-log"],
                cwd=V2_ROOT, env=env,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            wait_ready(api, f"http://127.0.0.1:{port}/ready")
            verify_emulator_route(port)
            print("Android emulator reached the disposable host API via 10.0.2.2.")
            if worker.poll() is not None:
                raise RuntimeError("Disposable V2 worker exited during startup.")
            completed = subprocess.run(
                ["C:\\Windows\\System32\\cmd.exe", "/d", "/c",
                 f'{FLUTTER_BAT} test test\\wellar_v2_live_http_test.dart --reporter expanded'],
                cwd=FLUTTER_ROOT, env=env, check=False,
            )
            if completed.returncode:
                return completed.returncode
            remaining_media = [path for path in media.rglob("*") if path.is_file()] if media.exists() else []
            if remaining_media:
                raise RuntimeError(f"V2 cleanup left {len(remaining_media)} media file(s) in temporary storage.")
            print("Disposable API and separate worker completed the real HTTP client test.")
            print("Synthetic uploaded media was deleted before temporary state cleanup.")
            return 0
        finally:
            stop(api)
            stop(worker)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
