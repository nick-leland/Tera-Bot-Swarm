# pip install rich requests

import json
import time
from datetime import datetime
from pathlib import Path

import requests
from rich.live import Live
from rich.panel import Panel
from rich.columns import Columns
from rich.json import JSON as RichJSON
from rich.text import Text
from rich.console import Group

PORT = 8081           # <- set your port
REFRESH = 0.5         # seconds
BASE = f"http://127.0.0.1:{PORT}"

ENDPOINTS = {
    "game-data":  f"{BASE}/game-data",
    "player":     f"{BASE}/player",
    "entities":   f"{BASE}/entities",
    "status":     f"{BASE}/status",
}

OUTDIR = Path(".")
OUTDIR.mkdir(parents=True, exist_ok=True)

state = {name: {"data": None, "error": None, "code": None, "updated": None} for name in ENDPOINTS}

def fetch_and_save(name: str, url: str):
    try:
        r = requests.get(url, timeout=3)
        code = r.status_code
        data = r.json()
        with open(OUTDIR / f"{name}.json", "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        state[name].update({
            "data": data,
            "error": None,
            "code": code,
            "updated": datetime.now(),
        })
    except Exception as e:
        state[name].update({
            "error": str(e),
            "code": None,
            "updated": datetime.now(),
        })

def render():
    panels = []
    for name, s in state.items():
        title = Text.assemble(
            (name, "bold"),
            ("  "),
            (f"{s['code']}" if s['code'] is not None else "…", "bold")
        )
        if s["error"]:
            body = Text(s["error"], style="red")
        elif s["data"] is None:
            body = Text("No data yet", style="dim")
        else:
            # Pretty JSON (rich truncates nicely to terminal width)
            body = RichJSON.from_data(s["data"])

        footer = Text(
            f"Updated: {s['updated'].strftime('%H:%M:%S') if s['updated'] else '—'}",
            style="dim"
        )
        panels.append(Panel(Group(body, footer), title=title, border_style="cyan"))
    return Columns(panels)

if __name__ == "__main__":
    try:
        with Live(render(), refresh_per_second=1/REFRESH if REFRESH > 0 else 4, screen=False):
            while True:
                for name, url in ENDPOINTS.items():
                    fetch_and_save(name, url)
                # Live will re-render on the next tick; force immediate update:
                # (Alternatively call live.update(render())).
                time.sleep(REFRESH)
    except KeyboardInterrupt:
        print("\nStopped.")
