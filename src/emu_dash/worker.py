from __future__ import annotations

from pathlib import Path
from threading import Event, Lock, Thread
from time import monotonic

from .protocol import FrameParser, TelemetryStore
from .sources import ByteSource


class TelemetryWorker:
    def __init__(self, source: ByteSource, store: TelemetryStore, raw_log: str | None = None) -> None:
        self.source = source
        self.store = store
        self.parser = FrameParser()
        self.stop_event = Event()
        self.thread = Thread(target=self._run, name="emu-telemetry", daemon=True)
        self.raw_log = Path(raw_log) if raw_log else None
        self._state_lock = Lock()
        self._status = "starting"
        self._error: str | None = None
        self._last_data_at = 0.0

    def start(self) -> None:
        self.thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        self.thread.join(timeout=3)

    def status(self) -> dict[str, object]:
        with self._state_lock:
            return {
                "status": self._status,
                "error": self._error,
                "last_data_age_s": monotonic() - self._last_data_at if self._last_data_at else None,
                "source": self.source.name,
                "valid_frames": self.parser.frames,
                "bad_checksums": self.parser.bad_checksums,
                "dropped_bytes": self.parser.dropped_bytes,
            }

    def _set_state(self, status: str, error: str | None = None) -> None:
        with self._state_lock:
            self._status = status
            self._error = error

    def _run(self) -> None:
        log_stream = None
        try:
            if self.raw_log:
                self.raw_log.parent.mkdir(parents=True, exist_ok=True)
                log_stream = self.raw_log.open("ab", buffering=0)
            while not self.stop_event.is_set():
                try:
                    self._set_state("connecting")
                    for chunk in self.source.chunks(self.stop_event):
                        if self.stop_event.is_set():
                            break
                        self._last_data_at = monotonic()
                        self._set_state("connected")
                        if log_stream:
                            log_stream.write(chunk)
                        for frame in self.parser.feed(chunk):
                            self.store.apply(frame)
                    if not self.stop_event.is_set():
                        self._set_state("reconnecting", "Stream ended")
                except Exception as exc:  # Keep the dashboard alive while hardware reconnects.
                    self._set_state("reconnecting", f"{type(exc).__name__}: {exc}")
                    self.stop_event.wait(2)
        finally:
            if log_stream:
                log_stream.close()
            self._set_state("stopped")
