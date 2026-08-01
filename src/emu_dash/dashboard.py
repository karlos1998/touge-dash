from __future__ import annotations

from pathlib import Path
from time import monotonic
from typing import Any

from .protocol import TelemetryStore
from .worker import TelemetryWorker


BG = (7, 10, 15)
PANEL = (16, 22, 31)
PANEL_2 = (21, 29, 40)
TEXT = (237, 242, 247)
MUTED = (135, 149, 166)
CYAN = (25, 211, 218)
GREEN = (68, 214, 136)
AMBER = (255, 181, 46)
RED = (255, 76, 86)


def _value(data: dict[str, object], key: str, precision: int = 0) -> str:
    value = data.get(key)
    if not isinstance(value, (int, float)):
        return "--"
    return f"{value:.{precision}f}"


def run_dashboard(
    store: TelemetryStore,
    worker: TelemetryWorker,
    *,
    fullscreen: bool = True,
    width: int = 1280,
    height: int = 720,
    fps: int = 30,
    screenshot: str | None = None,
    run_seconds: float | None = None,
) -> None:
    try:
        import pygame
    except ImportError as exc:
        raise RuntimeError("Missing pygame. Install with: pip install -e '.[display]'") from exc

    pygame.init()
    flags = pygame.FULLSCREEN if fullscreen else pygame.RESIZABLE
    screen = pygame.display.set_mode((0, 0) if fullscreen else (width, height), flags)
    pygame.display.set_caption("EMU Black Dash")
    clock = pygame.time.Clock()
    started = monotonic()
    screenshot_done = False

    def font(size: int, bold: bool = False):
        return pygame.font.SysFont("dejavusans", max(12, size), bold=bold)

    def text(surface, value: str, x: float, y: float, size: int, color=TEXT, bold=False, anchor="topleft"):
        rendered = font(size, bold).render(value, True, color)
        rect = rendered.get_rect()
        setattr(rect, anchor, (int(x), int(y)))
        surface.blit(rendered, rect)

    def panel(surface, rect, title: str, value: str, unit: str = "", warning: bool = False):
        pygame.draw.rect(surface, PANEL_2 if not warning else (57, 25, 29), rect, border_radius=12)
        pad = max(12, int(rect.w * 0.045))
        text(surface, title.upper(), rect.x + pad, rect.y + pad, max(13, int(rect.h * 0.13)), MUTED, True)
        value_color = RED if warning else TEXT
        text(surface, value, rect.x + pad, rect.centery + rect.h * 0.12, max(22, int(rect.h * 0.36)), value_color, True, "midleft")
        if unit:
            text(surface, unit, rect.right - pad, rect.bottom - pad, max(12, int(rect.h * 0.13)), MUTED, False, "bottomright")

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key in (pygame.K_ESCAPE, pygame.K_q):
                running = False

        data = store.snapshot()
        status = worker.status()
        w, h = screen.get_size()
        scale = min(w / 1280, h / 720)
        margin = max(12, int(20 * scale))
        gap = max(8, int(12 * scale))
        header_h = max(42, int(58 * scale))
        screen.fill(BG)

        age = data.get("age_s")
        connected = status["status"] == "connected" and isinstance(age, (int, float)) and age < 2
        status_color = GREEN if connected else AMBER
        text(screen, "EMU BLACK", margin, header_h / 2, int(25 * scale), TEXT, True, "midleft")
        text(screen, str(status["source"]), w / 2, header_h / 2, int(15 * scale), MUTED, False, "center")
        pygame.draw.circle(screen, status_color, (w - margin - int(94 * scale), header_h // 2), max(5, int(6 * scale)))
        text(screen, "ONLINE" if connected else str(status["status"]).upper(), w - margin, header_h / 2, int(14 * scale), status_color, True, "midright")

        content_y = header_h + gap
        content_h = h - content_y - margin
        left_w = int(w * 0.48)
        left = pygame.Rect(margin, content_y, left_w - margin, content_h)
        pygame.draw.rect(screen, PANEL, left, border_radius=14)

        rpm = float(data.get("rpm", 0) or 0)
        rpm_color = RED if rpm >= 8000 else AMBER if rpm >= 7000 else CYAN
        text(screen, "RPM", left.x + margin, left.y + margin, int(17 * scale), MUTED, True)
        text(screen, _value(data, "rpm"), left.centerx, left.y + left.h * 0.31, int(104 * scale), rpm_color, True, "center")

        bar = pygame.Rect(left.x + margin, int(left.y + left.h * 0.52), left.w - margin * 2, max(16, int(21 * scale)))
        pygame.draw.rect(screen, PANEL_2, bar, border_radius=bar.h // 2)
        fill = bar.copy()
        fill.w = max(0, min(bar.w, int(bar.w * rpm / 9000)))
        if fill.w:
            pygame.draw.rect(screen, rpm_color, fill, border_radius=bar.h // 2)

        boost = data.get("boost_bar")
        boost_warning = isinstance(boost, (int, float)) and boost > 1.5
        text(screen, "BOOST", left.x + margin, left.y + left.h * 0.65, int(17 * scale), MUTED, True)
        text(screen, _value(data, "boost_bar", 2), left.x + margin, left.y + left.h * 0.83, int(64 * scale), RED if boost_warning else TEXT, True, "midleft")
        text(screen, "bar", left.right - margin, left.y + left.h * 0.83, int(20 * scale), MUTED, False, "midright")

        right_x = left.right + gap
        right_w = w - right_x - margin
        cols, rows = 3, 4
        cell_w = (right_w - gap * (cols - 1)) / cols
        cell_h = (content_h - gap * (rows - 1)) / rows
        tiles = [
            ("AFR", "afr", "", 1, False),
            ("TPS", "tps", "%", 0, False),
            ("COOLANT", "clt_c", "°C", 0, (data.get("clt_c") or 0) > 105),
            ("OIL PRESS", "oil_pressure_bar", "bar", 1, rpm > 1200 and (data.get("oil_pressure_bar") or 99) < 0.5),
            ("OIL TEMP", "oil_temp_c", "°C", 0, (data.get("oil_temp_c") or 0) > 135),
            ("BATTERY", "battery_v", "V", 1, rpm > 500 and (data.get("battery_v") or 99) < 11.5),
            ("SPEED", "speed_kmh", "km/h", 0, False),
            ("GEAR", "gear", "", 0, False),
            ("IGNITION", "ignition_deg", "°", 1, False),
            ("IAT", "iat_c", "°C", 0, False),
            ("FUEL PRESS", "fuel_pressure_bar", "bar", 1, False),
            ("INJECTOR", "injector_dc", "%", 1, False),
        ]
        for index, (title, key, unit, precision, warning) in enumerate(tiles):
            row, col = divmod(index, cols)
            rect = pygame.Rect(
                int(right_x + col * (cell_w + gap)),
                int(content_y + row * (cell_h + gap)),
                int(cell_w),
                int(cell_h),
            )
            panel(screen, rect, title, _value(data, key, precision), unit, bool(warning))

        cel = data.get("cel_names")
        if isinstance(cel, list) and cel:
            banner = pygame.Rect(margin, h - margin - int(48 * scale), w - margin * 2, int(48 * scale))
            pygame.draw.rect(screen, RED, banner, border_radius=10)
            text(screen, "CHECK ENGINE: " + ", ".join(str(item) for item in cel), banner.centerx, banner.centery, int(18 * scale), (255, 255, 255), True, "center")

        pygame.display.flip()
        if screenshot and not screenshot_done and monotonic() - started > 0.5:
            Path(screenshot).parent.mkdir(parents=True, exist_ok=True)
            pygame.image.save(screen, screenshot)
            screenshot_done = True
        if run_seconds is not None and monotonic() - started >= run_seconds:
            running = False
        clock.tick(fps)

    pygame.quit()
