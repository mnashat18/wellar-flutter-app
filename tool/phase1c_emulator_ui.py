"""Run the test-only V2 UI entrypoint against a disposable local API/worker."""
from __future__ import annotations

import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
import shutil
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
V2 = Path(r"D:\flutter\last\wellar-ai-v2")
PYTHON = V2 / ".venv" / "Scripts" / "python.exe"
FLUTTER = Path(r"C:\flutter\bin\flutter.bat")
ADB = Path(r"C:\Android\Sdk\platform-tools\adb.exe")
DEVICE = "emulator-5554"


class RetryingTemporaryDirectory(tempfile.TemporaryDirectory):
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
                time.sleep(0.4)
        raise RuntimeError("Could not remove disposable Phase 1C state.") from last_error


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def adb(*args: str) -> str:
    return subprocess.run(
        [str(ADB), "-s", DEVICE, *args], check=True, capture_output=True,
        text=True, timeout=15,
    ).stdout


def ui_xml() -> str:
    adb("shell", "uiautomator", "dump", "/sdcard/window.xml")
    return adb("shell", "cat", "/sdcard/window.xml")


def wait_ui(text: str, flutter_process: subprocess.Popen | None = None, timeout: int = 90) -> str:
    deadline = time.monotonic() + timeout
    latest = ""
    while time.monotonic() < deadline:
        if flutter_process is not None and flutter_process.poll() is not None:
            raise RuntimeError("Flutter debug launch exited before the expected UI appeared.")
        try:
            latest = ui_xml()
        except subprocess.CalledProcessError:
            time.sleep(1.5)
            continue
        if text in latest:
            return latest
        time.sleep(1.5)
    safe_nodes = []
    try:
        for node in ET.fromstring(latest).iter("node"):
            label = node.attrib.get("text") or node.attrib.get("content-desc")
            if label:
                safe_nodes.append(label)
    except ET.ParseError:
        pass
    raise RuntimeError(f"Expected UI state did not appear: {text}; visible labels={safe_nodes[:20]}")


def tap_text(xml: str, expected: str) -> None:
    root = ET.fromstring(xml)
    for node in root.iter("node"):
        if expected in (node.attrib.get("text", ""), node.attrib.get("content-desc", "")):
            left, top, right, bottom = map(
                int, node.attrib["bounds"].replace("][", ",").replace("[", "").replace("]", "").split(",")
            )
            adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))
            return
    raise RuntimeError(f"Could not find tappable UI text: {expected}")


def stop(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    subprocess.run(
        ["taskkill", "/T", "/F", "/PID", str(process.pid)],
        capture_output=True, check=False, timeout=8,
    )
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def main() -> int:
    for path in (PYTHON, FLUTTER, ADB):
        if not path.exists():
            raise RuntimeError(f"Installed local tool unavailable: {path}")
    devices = subprocess.run([str(ADB), "devices"], capture_output=True, check=True).stdout
    if f"{DEVICE}\tdevice".encode() not in devices:
        raise RuntimeError("The installed emulator is not online in adb.")

    token = secrets.token_urlsafe(32)
    secret = token
    port = free_port()
    api = worker = flutter = None
    flutter_log = None
    api_log = None
    started = time.monotonic()
    with RetryingTemporaryDirectory(prefix="wellar-v2-phase1c-") as temporary:
        state = Path(temporary)
        environment = os.environ.copy()
        environment.update({
            "WELLAR_ENV": "test", "WELLAR_LOG_LEVEL": "ERROR",
            "WELLAR_DB_PATH": str(state / "queue.sqlite3"),
            "WELLAR_MEDIA_ROOT": str(state / "media"),
            "WELLAR_QUEUE_BACKEND": "sqlite", "WELLAR_MEDIA_BACKEND": "local",
            "WELLAR_AUTH_MODE": "development",
            "WELLAR_DEV_AUTH_TOKENS_JSON": json.dumps({
                token: {"sub": "synthetic-user", "tenant_id": "synthetic-tenant"},
            }),
            "WELLAR_MEDIA_RETENTION_DAYS": "1",
            "DART_SUPPRESS_ANALYTICS": "true",
        })
        api_log = (state / "api-access.log").open("w", encoding="utf-8")
        api = subprocess.Popen(
            [str(PYTHON), "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1",
             "--port", str(port), "--access-log"],
            cwd=V2, env=environment, stdout=api_log, stderr=subprocess.STDOUT,
        )
        worker = subprocess.Popen(
            [str(PYTHON), "-m", "app.workers.entrypoint"],
            cwd=V2, env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                if api.poll() is not None or worker.poll() is not None:
                    raise RuntimeError("Disposable V2 process exited during startup.")
                try:
                    with opener.open(f"http://127.0.0.1:{port}/ready", timeout=1) as response:
                        if response.status == 200:
                            break
                except (OSError, urllib.error.URLError):
                    time.sleep(0.2)
            else:
                raise RuntimeError("Disposable local V2 API did not become ready.")
            adb("shell", "toybox", "nc", "-z", "-w", "3", "10.0.2.2", str(port))
            adb("shell", "am", "force-stop", "com.example.waller_app")

            flutter_args = [
                str(FLUTTER), "run", "--debug", "--no-pub", "-d", DEVICE,
                "-t", "test/v2_ui_smoke_main.dart",
                f"--dart-define=ENABLE_LOCAL_WELLAR_V2=true",
                f"--dart-define=WELLAR_V2_BASE_URL=http://10.0.2.2:{port}",
                f"--dart-define=WELLAR_V2_DEV_TOKEN={token}",
                "--dart-define=WELLAR_V2_DEV_TENANT=synthetic-tenant",
                "--dart-define=WELLAR_V2_DEV_SUBJECT=synthetic-user",
            ]
            token = ""
            flutter_log = (state / "flutter-debug.log").open("w", encoding="utf-8")
            flutter = subprocess.Popen(
                flutter_args, cwd=ROOT, stdout=flutter_log, stderr=subprocess.STDOUT,
            )
            print("ANDROID_UI launch=debug_test_entrypoint", flush=True)
            try:
                wait_ui("V2 accepted the scan", flutter, timeout=180)
            except RuntimeError as error:
                log_text = (state / "flutter-debug.log").read_text(
                    encoding="utf-8", errors="replace",
                ).replace(secret, "<redacted>")
                tail = "\n".join(log_text.splitlines()[-60:])
                raise RuntimeError(f"{error}\nFlutter debug log tail:\n{tail}") from error
            print("ANDROID_UI state=v2_scan_accepted", flush=True)
            wait_ui("Insufficient evidence", flutter, timeout=180)
            final_xml = ui_xml()
            if "No readiness score or risk category is available" not in final_xml:
                raise RuntimeError("V2 result UI did not show the non-predictive disclaimer.")
            if "Unavailable" not in final_xml:
                raise RuntimeError("V2 result UI did not show nullable target values.")
            tap_text(final_xml, "Done")
            wait_ui("V2 local UI verification", flutter, timeout=30)
            media_root = state / "media"
            remaining = [p for p in media_root.rglob("*") if p.is_file()] if media_root.exists() else []
            if remaining:
                raise RuntimeError(f"V2 left {len(remaining)} temporary media object(s).")
            api_log.flush()
            access_log = (state / "api-access.log").read_text(
                encoding="utf-8", errors="replace",
            )
            observed = re.findall(
                r'"(GET|POST|DELETE) ([^ ?"]+)(?:\?[^" ]*)? HTTP/1\.[01]" (\d{3})',
                access_log,
            )
            if not observed or any("/process" in route for _, route, _ in observed):
                raise RuntimeError("Expected V2-only API access log evidence was incomplete.")
            required = {
                ("POST", "/api/v1/media/video", "201"),
                ("POST", "/api/v1/media/audio", "201"),
                ("POST", "/api/v1/scans", "202"),
                ("DELETE", "/api/v1/media", "204"),
            }
            has_status = any(
                method == "GET" and route.startswith("/api/v1/scans/")
                and not route.endswith("/result") and status == "200"
                for method, route, status in observed
            )
            has_result = any(
                method == "GET" and route.endswith("/result") and status == "200"
                for method, route, status in observed
            )
            if not required.issubset(set(observed)) or not has_status or not has_result:
                raise RuntimeError("The V2 access log did not contain the expected upload, submit, status, and cleanup statuses.")
            for method, route, status in observed:
                if route.startswith("/api/v1/"):
                    print(f"ANDROID_HTTP method={method} route={route} status={status}")
            elapsed_ms = int((time.monotonic() - started) * 1000)
            print("ANDROID_V2_UI outcome=insufficient_evidence targets=null disclaimer=visible media_files_remaining=0")
            print(f"ANDROID_V2_UI elapsed_ms={elapsed_ms} device={DEVICE} host_route=10.0.2.2")
            return 0
        finally:
            stop(flutter)
            if flutter_log is not None:
                flutter_log.close()
            stop(api)
            if api_log is not None:
                api_log.close()
            stop(worker)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
