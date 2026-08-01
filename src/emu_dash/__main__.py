from __future__ import annotations

import argparse
import json
import os
import signal
import sys
from threading import Event
from time import sleep

from .dashboard import run_dashboard
from .protocol import TelemetryStore
from .sources import AutoMacOSRfcommSource, DemoSource, DeviceSource, MacOSRfcommSource, ReplaySource, RfcommSource
from .web import serve_web
from .worker import TelemetryWorker


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="ECUMaster EMU Black dashboard for Raspberry Pi")
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--demo", action="store_true", help="Use generated engine data")
    source.add_argument("--mac", help="Bluetooth MAC of EMUCANBT_SPP")
    source.add_argument("--device", help="Read a bound device such as /dev/rfcomm0")
    source.add_argument("--replay", help="Replay a raw .bin log")
    parser.add_argument("--rfcomm-channel", type=int, default=1)
    parser.add_argument("--replay-speed", type=float, default=1.0)
    parser.add_argument("--log-raw", help="Append the complete raw stream to a binary log")
    parser.add_argument("--baro", type=float, default=101.325, help="Fallback atmospheric pressure in kPa")
    parser.add_argument("--web", action="store_true", help="Serve a browser dashboard")
    parser.add_argument("--host", default="127.0.0.1", help="Web server bind address")
    parser.add_argument("--port", type=int, default=8080, help="Web server port")
    parser.add_argument("--no-open", action="store_true", help="Do not open the browser automatically")
    parser.add_argument("--headless", action="store_true", help="Print telemetry as JSON instead of showing the UI")
    parser.add_argument("--windowed", action="store_true")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--screenshot", help=argparse.SUPPRESS)
    parser.add_argument("--run-seconds", type=float, help=argparse.SUPPRESS)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    environment_mac = os.getenv("EMU_BT_MAC")
    selected_mac = args.mac or (environment_mac if not any((args.demo, args.device, args.replay)) else None)
    if selected_mac:
        source = MacOSRfcommSource(selected_mac, args.rfcomm_channel) if sys.platform == "darwin" else RfcommSource(selected_mac, args.rfcomm_channel)
    elif args.device:
        source = DeviceSource(args.device)
    elif args.replay:
        source = ReplaySource(args.replay, args.replay_speed)
    elif args.demo:
        source = DemoSource()
    elif args.web and sys.platform == "darwin":
        source = AutoMacOSRfcommSource(args.rfcomm_channel)
    else:
        source = DemoSource()

    store = TelemetryStore(args.baro)
    worker = TelemetryWorker(source, store, args.log_raw)
    worker.start()
    try:
        if args.web:
            serve_web(store, worker, host=args.host, port=args.port, open_browser=not args.no_open)
        elif args.headless:
            stopping = Event()

            def stop_handler(_signum, _frame):
                stopping.set()

            signal.signal(signal.SIGINT, stop_handler)
            signal.signal(signal.SIGTERM, stop_handler)
            elapsed = 0.0
            while not stopping.is_set() and (args.run_seconds is None or elapsed < args.run_seconds):
                print(json.dumps({"telemetry": store.snapshot(), "connection": worker.status()}, ensure_ascii=False))
                sleep(1)
                elapsed += 1
        else:
            run_dashboard(
                store,
                worker,
                fullscreen=not args.windowed,
                width=args.width,
                height=args.height,
                fps=args.fps,
                screenshot=args.screenshot,
                run_seconds=args.run_seconds,
            )
    finally:
        worker.stop()


if __name__ == "__main__":
    main()
