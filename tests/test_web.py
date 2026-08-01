import json
import threading
import unittest
from urllib.request import urlopen

from emu_dash.protocol import TelemetryStore
from emu_dash.web import DashboardHTTPServer


class FakeWorker:
    def status(self):
        return {
            "status": "connected",
            "error": None,
            "source": "TEST",
            "valid_frames": 0,
            "bad_checksums": 0,
            "dropped_bytes": 0,
        }


class DashboardServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = DashboardHTTPServer(("127.0.0.1", 0), TelemetryStore(), FakeWorker())
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def test_health_endpoint(self):
        with urlopen(self.base_url + "/api/health") as response:
            self.assertEqual(json.load(response), {"ok": True})

    def test_dashboard_assets(self):
        with urlopen(self.base_url + "/") as response:
            body = response.read().decode()
        self.assertIn("EMU Black", body)
        self.assertIn("/app.js", body)


if __name__ == "__main__":
    unittest.main()
