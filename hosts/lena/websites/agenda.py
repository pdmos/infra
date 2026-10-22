#!/usr/bin/env python3
"""Render the Porto de Mós events RSS into an HTML fragment for pdmos.pt.

The feed uses pubDate as the event start date, not the publication date.
Only title, link and pubDate are used: description carries remote images
and inline styles that the CSP blocks.
"""
import argparse
import html
import os
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta
from email.utils import parsedate_to_datetime
from pathlib import Path
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Europe/Lisbon")
DAYS = 30
ORIGIN = "https://www.municipio-portodemos.pt/"
MONTHS = "jan fev mar abr mai jun jul ago set out nov dez".split()
WEEKDAYS = "seg ter qua qui sex sáb dom".split()


def events(feed: bytes, today: date):
    out = []
    for item in ET.fromstring(feed).iter("item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        raw = item.findtext("pubDate")
        if not (title and raw) or not link.startswith(ORIGIN):
            continue
        try:
            start = parsedate_to_datetime(raw).astimezone(TZ)
        except ValueError:
            continue
        if today <= start.date() < today + timedelta(days=DAYS):
            out.append((start, title, link))
    return sorted(out)


def when(start: datetime, today: date) -> str:
    d = start.date()
    label = {today: "hoje", today + timedelta(days=1): "amanhã"}.get(d, WEEKDAYS[d.weekday()])
    # 00:00 means the feed has no time for the event
    if (start.hour, start.minute) != (0, 0):
        label += f" · {start.hour}h{start.minute:02d}"
    return label


def render(evs, today: date) -> str:
    if not evs:
        return '<p class="vazio">Nada marcado para os próximos 30 dias.</p>\n'
    rows = [
        f'<li><a href="{html.escape(link)}">'
        f'<time datetime="{start.isoformat()}"><b>{start.day}</b>{MONTHS[start.month - 1]}</time>'
        f'<span><small>{when(start, today)}</small>{html.escape(title)}</span></a></li>'
        for start, title, link in evs
    ]
    return '<ol class="eventos">\n' + "\n".join(rows) + "\n</ol>\n"


def write_atomic(path: Path, data: bytes):
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.chmod(tmp, 0o644)  # mkstemp creates 0600; nginx reads the result as another user
    os.replace(tmp, path)


def fetch(url: str, state: Path) -> bytes:
    """Download the feed; on any failure fall back to the last good copy."""
    cache = state / "feed.xml"
    req = urllib.request.Request(url, headers={"User-Agent": "pdmos.pt agenda"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read()
        ET.fromstring(body)  # never cache a broken feed
        write_atomic(cache, body)
    except (OSError, ET.ParseError) as e:
        print(f"feed: {e}, using cached copy", file=sys.stderr)
    return cache.read_bytes()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True, help="feed URL (file:// works for testing)")
    p.add_argument("--out", required=True, type=Path, help="directory for feed.xml and agenda.html")
    p.add_argument("--today", type=date.fromisoformat)
    a = p.parse_args()
    today = a.today or datetime.now(TZ).date()
    write_atomic(a.out / "agenda.html", render(events(fetch(a.url, a.out), today), today).encode())
