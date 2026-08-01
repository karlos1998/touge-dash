from __future__ import annotations

import json
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib.resources import files
from time import monotonic

from .protocol import TelemetryStore
from .sources import likely_emu_bluetooth_devices, list_serial_ports
from .worker import TelemetryWorker


CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
}


class DashboardHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], store: TelemetryStore, worker: TelemetryWorker) -> None:
        super().__init__(address, DashboardHandler)
        self.store = store
        self.worker = worker
        self._inventory_lock = threading.Lock()
        self._inventory_at = 0.0
        self._inventory: dict[str, object] = {"serial_ports": [], "bluetooth_devices": []}

    def inventory(self) -> dict[str, object]:
        with self._inventory_lock:
            now = monotonic()
            if now - self._inventory_at >= 2:
                self._inventory = {
                    "serial_ports": list_serial_ports(),
                    "bluetooth_devices": likely_emu_bluetooth_devices(),
                }
                self._inventory_at = now
            return dict(self._inventory)


class DashboardHandler(BaseHTTPRequestHandler):
    server: DashboardHTTPServer

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/api/telemetry":
            telemetry = self.server.store.snapshot()
            telemetry.pop("last_seen", None)
            inventory = self.server.inventory()
            self._json(
                {
                    "telemetry": telemetry,
                    "connection": self.server.worker.status(),
                    **inventory,
                }
            )
            return
        if path == "/api/health":
            self._json({"ok": True})
            return

        asset = {"/": "index.html", "/app.css": "app.css", "/app.js": "app.js"}.get(path)
        if asset is None:
            self.send_error(404)
            return
        resource = files("emu_dash").joinpath("web", asset)
        body = resource.read_bytes()
        suffix = "." + asset.rsplit(".", 1)[-1]
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPES.get(suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, payload: object) -> None:
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def serve_web(
    store: TelemetryStore,
    worker: TelemetryWorker,
    *,
    host: str = "127.0.0.1",
    port: int = 8080,
    open_browser: bool = True,
) -> None:
    server = DashboardHTTPServer((host, port), store, worker)
    display_host = "localhost" if host in {"127.0.0.1", "0.0.0.0"} else host
    url = f"http://{display_host}:{server.server_port}"
    print(f"EMU dashboard: {url}", flush=True)
    if open_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
