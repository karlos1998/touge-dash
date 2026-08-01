from __future__ import annotations

import math
import os
import select
import socket
import subprocess
import sys
import termios
import json
from glob import glob
from importlib.resources import files
from pathlib import Path
from random import Random
from threading import Event
from time import monotonic
from typing import Iterator, Protocol

from .protocol import encode_frame, raw_from_value


class ByteSource(Protocol):
    name: str

    def chunks(self, stop: Event) -> Iterator[bytes]: ...


class RfcommSource:
    """Direct Linux/BlueZ RFCOMM (Bluetooth Classic SPP) connection."""

    def __init__(self, mac: str, channel: int = 1, reconnect_delay: float = 2.0) -> None:
        self.mac = mac.upper()
        self.channel = channel
        self.reconnect_delay = reconnect_delay
        self.name = f"Bluetooth {self.mac} ch.{channel}"

    def chunks(self, stop: Event) -> Iterator[bytes]:
        if not hasattr(socket, "AF_BLUETOOTH"):
            raise RuntimeError("Direct Bluetooth RFCOMM is supported on Linux/Raspberry Pi only")

        while not stop.is_set():
            sock: socket.socket | None = None
            try:
                sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
                sock.settimeout(8)
                sock.connect((self.mac, self.channel))
                sock.settimeout(1)
                while not stop.is_set():
                    try:
                        data = sock.recv(2048)
                    except TimeoutError:
                        continue
                    if not data:
                        raise ConnectionError("Bluetooth connection closed")
                    yield data
            finally:
                if sock is not None:
                    sock.close()
            stop.wait(self.reconnect_delay)


class DeviceSource:
    """Read a stream exposed as a device, normally /dev/rfcomm0."""

    def __init__(self, path: str, reconnect_delay: float = 2.0, baudrate: int = 19200) -> None:
        self.path = path
        self.reconnect_delay = reconnect_delay
        self.baudrate = baudrate
        self.name = path

    def chunks(self, stop: Event) -> Iterator[bytes]:
        while not stop.is_set():
            fd: int | None = None
            try:
                fd = os.open(self.path, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
                _configure_serial(fd, self.baudrate)
                while not stop.is_set():
                    readable, _, _ = select.select([fd], [], [], 1.0)
                    if not readable:
                        continue
                    data = os.read(fd, 2048)
                    if not data:
                        raise ConnectionError(f"Device closed: {self.path}")
                    yield data
            finally:
                if fd is not None:
                    os.close(fd)
            stop.wait(self.reconnect_delay)


def _configure_serial(fd: int, baudrate: int) -> None:
    speed = getattr(termios, f"B{baudrate}", termios.B19200)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = (attrs[2] & ~termios.CSIZE & ~termios.PARENB & ~termios.CSTOPB) | termios.CS8 | termios.CLOCAL | termios.CREAD
    attrs[3] = 0
    attrs[4] = speed
    attrs[5] = speed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 10
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def list_serial_ports() -> list[str]:
    ports = set(glob("/dev/cu.*") + glob("/dev/tty.*") + glob("/dev/rfcomm*"))
    return sorted(ports)


def likely_emu_serial_ports() -> list[str]:
    tokens = ("emu", "ecumaster", "canbt", "edl", "btcan")
    excluded = ("bluetooth-incoming-port", "debug-console")
    ports = list_serial_ports()
    likely = [port for port in ports if any(token in port.lower() for token in tokens)]
    return likely or [port for port in ports if not any(token in port.lower() for token in excluded)]


class AutoDeviceSource:
    def __init__(self, baudrate: int = 19200) -> None:
        self.baudrate = baudrate
        self.current_port: str | None = None

    @property
    def name(self) -> str:
        return self.current_port or "Waiting for EMU serial port"

    def chunks(self, stop: Event) -> Iterator[bytes]:
        while not stop.is_set():
            candidates = likely_emu_serial_ports()
            if not candidates:
                self.current_port = None
                stop.wait(1)
                continue
            self.current_port = candidates[0]
            try:
                yield from DeviceSource(self.current_port, reconnect_delay=0, baudrate=self.baudrate).chunks(stop)
            except (OSError, ConnectionError, termios.error):
                self.current_port = None
                stop.wait(1)


def list_macos_bluetooth_devices() -> list[dict[str, str]]:
    if sys.platform != "darwin":
        return []
    try:
        output = subprocess.check_output(
            ["system_profiler", "SPBluetoothDataType", "-json", "-detailLevel", "full"],
            text=True,
            timeout=8,
        )
        payload = json.loads(output)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return []

    devices: list[dict[str, str]] = []
    for controller in payload.get("SPBluetoothDataType", []):
        for group_name, group in controller.items():
            if not group_name.startswith("device_") or not isinstance(group, list):
                continue
            connected = group_name == "device_connected"
            for entry in group:
                if not isinstance(entry, dict):
                    continue
                for name, details in entry.items():
                    if not isinstance(details, dict) or not details.get("device_address"):
                        continue
                    devices.append(
                        {
                            "name": str(name),
                            "address": str(details["device_address"]).upper(),
                            "connected": "yes" if connected else "no",
                        }
                    )
    return devices


def likely_emu_bluetooth_devices() -> list[dict[str, str]]:
    tokens = ("emu", "ecumaster", "canbt", "edl", "btcan")
    return [device for device in list_macos_bluetooth_devices() if any(token in device["name"].lower() for token in tokens)]


def _macos_bridge_binary() -> Path:
    cache_dir = Path.home() / "Library" / "Caches" / "emu-black-dash"
    binary = cache_dir / "emu-rfcomm-macos"
    source = Path(str(files("emu_dash").joinpath("native/macos_rfcomm.swift")))
    if binary.exists() and binary.stat().st_mtime >= source.stat().st_mtime:
        return binary
    cache_dir.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["xcrun", "swiftc", str(source), "-framework", "IOBluetooth", "-o", str(binary)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode:
        raise RuntimeError("Cannot compile macOS Bluetooth bridge: " + (result.stderr.strip() or "unknown error"))
    return binary


class MacOSRfcommSource:
    def __init__(self, mac: str, channel: int = 1) -> None:
        self.mac = mac.upper()
        self.channel = channel
        self.name = f"macOS Bluetooth {self.mac} ch.{channel}"

    def chunks(self, stop: Event) -> Iterator[bytes]:
        if sys.platform != "darwin":
            raise RuntimeError("The native IOBluetooth bridge is available on macOS only")
        binary = _macos_bridge_binary()
        process = subprocess.Popen(
            [str(binary), self.mac, str(self.channel)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            assert process.stdout is not None
            while not stop.is_set():
                readable, _, _ = select.select([process.stdout], [], [], 0.5)
                if readable:
                    data = os.read(process.stdout.fileno(), 4096)
                    if data:
                        yield data
                    elif process.poll() is not None:
                        break
                elif process.poll() is not None:
                    break
            if process.poll() not in (None, 0) and not stop.is_set():
                stderr = process.stderr.read().decode("utf-8", "replace").strip() if process.stderr else ""
                raise ConnectionError(stderr or f"Bluetooth bridge exited with {process.returncode}")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    process.kill()


class AutoMacOSRfcommSource:
    def __init__(self, channel: int = 1) -> None:
        self.channel = channel
        self.current_device: dict[str, str] | None = None

    @property
    def name(self) -> str:
        if self.current_device:
            return f"{self.current_device['name']} ({self.current_device['address']})"
        return "Waiting for paired EMU Bluetooth device"

    def chunks(self, stop: Event) -> Iterator[bytes]:
        while not stop.is_set():
            candidates = likely_emu_bluetooth_devices()
            if not candidates:
                self.current_device = None
                stop.wait(2)
                continue
            self.current_device = candidates[0]
            try:
                yield from MacOSRfcommSource(self.current_device["address"], self.channel).chunks(stop)
            except (OSError, ConnectionError, RuntimeError):
                stop.wait(2)


class ReplaySource:
    def __init__(self, path: str, speed: float = 1.0, loop: bool = True) -> None:
        self.path = Path(path)
        self.speed = max(speed, 0.05)
        self.loop = loop
        self.name = f"Replay {self.path.name}"

    def chunks(self, stop: Event) -> Iterator[bytes]:
        while not stop.is_set():
            with self.path.open("rb") as stream:
                while not stop.is_set():
                    data = stream.read(5)
                    if not data:
                        break
                    yield data
                    stop.wait(0.003 / self.speed)
            if not self.loop:
                return


class DemoSource:
    name = "DEMO"

    def __init__(self) -> None:
        self.random = Random(42)

    def chunks(self, stop: Event) -> Iterator[bytes]:
        start = monotonic()
        while not stop.is_set():
            t = monotonic() - start
            rpm = max(850.0, 4300 + 3300 * math.sin(t * 0.47))
            throttle = max(0.0, min(100.0, 48 + 47 * math.sin(t * 0.47 + 0.35)))
            boost = max(-0.7, min(1.55, (rpm - 3100) / 2600 + math.sin(t * 0.9) * 0.08))
            afr = 14.7 if throttle < 30 else 12.2 + 0.25 * math.sin(t * 1.6)
            speed = max(0.0, min(220.0, (rpm - 700) / 32))
            gear = max(1, min(6, int(speed // 35) + 1))
            values = {
                1: rpm,
                2: 101.325 + boost * 100,
                3: throttle,
                4: 31 + math.sin(t * 0.1) * 2,
                5: 13.8 + math.sin(t) * 0.1,
                6: 17 + math.sin(t * 0.7) * 7,
                7: 2.2 + throttle / 14,
                12: afr,
                13: gear,
                14: 101,
                19: min(96, throttle * 0.78),
                21: 1.2 + rpm / 2100,
                22: 92 + math.sin(t * 0.08) * 3,
                23: 3.2 + math.sin(t * 0.3) * 0.1,
                24: 89 + math.sin(t * 0.11) * 4,
                27: afr / 14.7,
                28: speed,
                255: 0,
            }
            packet = bytearray()
            for channel, value in values.items():
                jitter = self.random.uniform(-0.04, 0.04) if channel in {5, 12, 21, 23} else 0
                packet.extend(encode_frame(channel, raw_from_value(channel, value + jitter)))
            yield bytes(packet)
            stop.wait(0.04)
