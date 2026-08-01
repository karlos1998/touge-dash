from __future__ import annotations

from dataclasses import dataclass
from threading import Lock
from time import monotonic
from typing import Callable


ID_CHAR = 0xA3


@dataclass(frozen=True, slots=True)
class Frame:
    channel: int
    raw_value: int
    raw: bytes


@dataclass(frozen=True, slots=True)
class ChannelSpec:
    key: str
    label: str
    unit: str
    divider: float = 1.0
    bits: int = 16
    signed: bool = False
    precision: int = 0

    def decode(self, raw_value: int) -> float:
        mask = (1 << self.bits) - 1
        value = raw_value & mask
        if self.signed and value >= 1 << (self.bits - 1):
            value -= 1 << self.bits
        return value / self.divider


CHANNELS: dict[int, ChannelSpec] = {
    1: ChannelSpec("rpm", "RPM", "rpm"),
    2: ChannelSpec("map_kpa", "MAP", "kPa"),
    3: ChannelSpec("tps", "TPS", "%", bits=8),
    4: ChannelSpec("iat_c", "IAT", "°C", bits=8, signed=True),
    5: ChannelSpec("battery_v", "Battery", "V", divider=37, precision=1),
    6: ChannelSpec("ignition_deg", "Ignition", "°", divider=2, bits=8, signed=True, precision=1),
    7: ChannelSpec("injector_pw_ms", "Injector PW", "ms", divider=62, precision=2),
    8: ChannelSpec("egt1_c", "EGT 1", "°C"),
    9: ChannelSpec("egt2_c", "EGT 2", "°C"),
    10: ChannelSpec("knock_v", "Knock", "V", divider=51, bits=8, precision=2),
    11: ChannelSpec("dwell_ms", "Dwell", "ms", divider=20, bits=8, precision=2),
    12: ChannelSpec("afr", "AFR", "AFR", divider=10, bits=8, precision=1),
    13: ChannelSpec("gear", "Gear", "", bits=8, signed=True),
    14: ChannelSpec("baro_kpa", "BARO", "kPa", bits=8),
    15: ChannelSpec("analog1_v", "Analog 1", "V", divider=51, bits=8, precision=2),
    16: ChannelSpec("analog2_v", "Analog 2", "V", divider=51, bits=8, precision=2),
    17: ChannelSpec("analog3_v", "Analog 3", "V", divider=51, bits=8, precision=2),
    18: ChannelSpec("analog4_v", "Analog 4", "V", divider=51, bits=8, precision=2),
    19: ChannelSpec("injector_dc", "Injector DC", "%", divider=2, bits=8, precision=1),
    20: ChannelSpec("ecu_temp_c", "ECU temp", "°C", bits=8, signed=True),
    21: ChannelSpec("oil_pressure_bar", "Oil pressure", "bar", divider=16, bits=8, precision=1),
    22: ChannelSpec("oil_temp_c", "Oil temp", "°C", bits=8),
    23: ChannelSpec("fuel_pressure_bar", "Fuel pressure", "bar", divider=16, bits=8, precision=1),
    24: ChannelSpec("clt_c", "Coolant", "°C", signed=True),
    25: ChannelSpec("ethanol_pct", "Ethanol", "%", divider=2, bits=8, precision=1),
    26: ChannelSpec("fuel_temp_c", "Fuel temp", "°C", bits=8, signed=True),
    27: ChannelSpec("lambda", "Lambda", "λ", divider=128, bits=8, precision=2),
    28: ChannelSpec("speed_kmh", "Speed", "km/h", divider=4, precision=0),
    29: ChannelSpec("fuel_delta_kpa", "Fuel delta", "kPa"),
    30: ChannelSpec("fuel_level_pct", "Fuel level", "%", bits=8),
    31: ChannelSpec("tables_set", "Tables set", "", bits=8),
    32: ChannelSpec("lambda_target", "Lambda target", "λ", divider=100, bits=8, precision=2),
    33: ChannelSpec("secondary_pw_ms", "Secondary PW", "ms", divider=62, precision=2),
    34: ChannelSpec("analog5_v", "Analog 5", "V", divider=51, bits=8, precision=2),
    35: ChannelSpec("analog6_v", "Analog 6", "V", divider=51, bits=8, precision=2),
    255: ChannelSpec("cel_mask", "Check engine", ""),
}


CEL_BITS = {
    0: "CLT",
    1: "IAT",
    2: "MAP",
    3: "WBO",
    4: "EGT1",
    5: "EGT2",
    6: "EGT alarm",
    7: "Knock",
    8: "Flex fuel",
    9: "DBW",
    10: "Fuel pressure",
}


def checksum(payload: bytes) -> int:
    return sum(payload) & 0xFF


def encode_frame(channel: int, raw_value: int) -> bytes:
    raw_value &= 0xFFFF
    payload = bytes((channel & 0xFF, ID_CHAR, raw_value >> 8, raw_value & 0xFF))
    return payload + bytes((checksum(payload),))


class FrameParser:
    """Incremental parser with byte-by-byte recovery after damaged input."""

    def __init__(self) -> None:
        self.buffer = bytearray()
        self.frames = 0
        self.bad_checksums = 0
        self.dropped_bytes = 0

    def feed(self, data: bytes) -> list[Frame]:
        self.buffer.extend(data)
        result: list[Frame] = []
        while len(self.buffer) >= 5:
            if self.buffer[1] != ID_CHAR:
                del self.buffer[0]
                self.dropped_bytes += 1
                continue

            candidate = bytes(self.buffer[:5])
            if checksum(candidate[:4]) != candidate[4]:
                del self.buffer[0]
                self.bad_checksums += 1
                self.dropped_bytes += 1
                continue

            del self.buffer[:5]
            frame = Frame(candidate[0], (candidate[2] << 8) | candidate[3], candidate)
            result.append(frame)
            self.frames += 1
        return result


def cel_names(mask: int) -> list[str]:
    return [name for bit, name in CEL_BITS.items() if mask & (1 << bit)]


class TelemetryStore:
    def __init__(self, fallback_baro_kpa: float = 101.325) -> None:
        self._lock = Lock()
        self._values: dict[str, float] = {}
        self._last_seen: dict[str, float] = {}
        self._last_frame_at = 0.0
        self._frame_count = 0
        self._unknown_frames = 0
        self.fallback_baro_kpa = fallback_baro_kpa

    def apply(self, frame: Frame) -> None:
        spec = CHANNELS.get(frame.channel)
        now = monotonic()
        with self._lock:
            self._last_frame_at = now
            self._frame_count += 1
            if spec is None:
                self._unknown_frames += 1
                return
            self._values[spec.key] = spec.decode(frame.raw_value)
            self._last_seen[spec.key] = now

    def snapshot(self) -> dict[str, object]:
        now = monotonic()
        with self._lock:
            values: dict[str, object] = dict(self._values)
            values["frame_count"] = self._frame_count
            values["unknown_frames"] = self._unknown_frames
            values["age_s"] = now - self._last_frame_at if self._last_frame_at else None
            values["last_seen"] = dict(self._last_seen)

        map_kpa = values.get("map_kpa")
        if isinstance(map_kpa, (int, float)):
            baro = values.get("baro_kpa", self.fallback_baro_kpa)
            if isinstance(baro, (int, float)):
                values["boost_bar"] = (map_kpa - baro) / 100.0

        cel_mask = int(values.get("cel_mask", 0) or 0)
        values["cel_names"] = cel_names(cel_mask)
        return values


def raw_from_value(channel: int, value: float) -> int:
    """Encode an engineering value; useful for simulation and protocol tests."""
    spec = CHANNELS[channel]
    scaled = int(round(value * spec.divider))
    if spec.signed and scaled < 0:
        scaled += 1 << spec.bits
    return scaled

