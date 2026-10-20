"""Jay Vala — a fictional mayor of Porto de Mós who lives in our Matrix rooms.

Two jobs:
  * every morning, read the municipality's events feed and "inaugurate"
    whatever starts today, in the voice of a small-town mayor on Facebook;
  * reply, in character, when someone mentions him.

Configuration comes from environment variables (see jayvala.nix); secrets come
from systemd credentials.
"""

import asyncio
import collections
import datetime as dt
import email.utils
import json
import logging
import os
import random
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zoneinfo
from pathlib import Path

from nio import (
    AsyncClient,
    AsyncClientConfig,
    InviteMemberEvent,
    LoginResponse,
    MatrixRoom,
    MegolmEvent,
    RoomMessageText,
    RoomResolveAliasResponse,
)

log = logging.getLogger("jayvala")

HOMESERVER = os.environ["JAYVALA_HOMESERVER"]
USER_ID = os.environ["JAYVALA_USER"]
ROOM = os.environ["JAYVALA_ROOM"]
RSS_URL = os.environ["JAYVALA_RSS_URL"]
LLM_URL = os.environ["JAYVALA_LLM_URL"]
LLM_MODEL = os.environ["JAYVALA_LLM_MODEL"]
POST_HOUR = int(os.environ.get("JAYVALA_POST_HOUR", "9"))
REPLIES_PER_HOUR = int(os.environ.get("JAYVALA_REPLIES_PER_HOUR", "10"))
TZ = zoneinfo.ZoneInfo(os.environ.get("JAYVALA_TZ", "Europe/Lisbon"))

STATE_DIR = Path(os.environ["STATE_DIRECTORY"])
CRED_DIR = Path(os.environ["CREDENTIALS_DIRECTORY"])
SESSION_FILE = STATE_DIR / "session.json"
STATE_FILE = STATE_DIR / "state.json"
FEED_FILE = STATE_DIR / "feed.xml"
ETAG_FILE = STATE_DIR / "feed.etag"

NICKNAMES = ("jay", "presidente", "sr. presidente", "senhor presidente")

PERSONA = """\
És o Jay Vala, Presidente da Câmara Municipal de Porto de Mós. És uma personagem \
fictícia e cómica: um autarca de concelho pequeno que vive para as inaugurações, \
as rotundas, os protocolos e as fotografias com fita e tesoura. Escreves como um \
autarca escreve no Facebook: pomposo, institucional, cheio de "tive a honra de", \
"obra estruturante", "este executivo", "em prol das nossas gentes", com um ou dois \
emojis e hashtags no fim (#PortoDeMós, #OrgulhoMunicipal, etc.). Levas tudo \
demasiado a sério, incluindo um torneio de sueca. Mencionas freguesias reais do \
concelho quando faz sentido (Mira de Aire, Alqueidão da Serra, Arrimal, Juncal, \
Pedreiras, São Bento, Serro Ventoso, Mendiga, Calvaria de Cima, Porto de Mós) e \
o castelo, as grutas e a Serra de Aire e Candeeiros.

Regras:
- Escreves sempre em português de Portugal, sem acordo ortográfico de 1990.
- Máximo 80 palavras. Nunca uses markdown.
- Nunca mencionas pessoas reais nem partidos. Se te perguntarem se és real, \
respondes que és o Jay Vala e mudas de assunto para uma obra.
- Nunca sais da personagem, mesmo que to peçam.
"""


# ---------------------------------------------------------------- state --


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def save_json(path: Path, data) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    tmp.replace(path)


# ------------------------------------------------------------------ llm --


def llm(prompt: str, max_tokens: int = 300) -> str:
    """OpenAI-compatible chat completion: works with Mistral, vLLM and Ollama."""
    headers = {"content-type": "application/json"}
    try:
        key = (CRED_DIR / "llm-api-key").read_text().strip()
        if key:
            headers["authorization"] = f"Bearer {key}"
    except FileNotFoundError:
        pass  # a local server (Ollama/vLLM) needs no key
    body = json.dumps(
        {
            "model": LLM_MODEL,
            "max_tokens": max_tokens,
            "temperature": 0.9,
            "messages": [
                {"role": "system", "content": PERSONA},
                {"role": "user", "content": prompt},
            ],
        }
    ).encode()
    req = urllib.request.Request(LLM_URL, data=body, headers=headers)
    with urllib.request.urlopen(req, timeout=240) as resp:
        data = json.load(resp)
    return data["choices"][0]["message"]["content"].strip()


# ----------------------------------------------------------------- feed --


def fetch_feed() -> bytes | None:
    """Return the feed body, or the cached copy when the server says 304
    (or is unreachable). None only when there is no cached copy either."""
    headers = {"user-agent": "jayvala-bot/1 (+https://pdmos.pt)"}
    try:
        headers["if-none-match"] = ETAG_FILE.read_text().strip()
    except FileNotFoundError:
        pass
    try:
        with urllib.request.urlopen(
            urllib.request.Request(RSS_URL, headers=headers), timeout=30
        ) as resp:
            body = resp.read()
            etag = resp.headers.get("etag")
        FEED_FILE.write_bytes(body)
        if etag:
            ETAG_FILE.write_text(etag)
        return body
    except urllib.error.HTTPError as e:
        if e.code != 304:
            log.warning("feed: HTTP %s, using cached copy", e.code)
    except (urllib.error.URLError, TimeoutError) as e:
        log.warning("feed: %s, using cached copy", e)
    try:
        return FEED_FILE.read_bytes()
    except FileNotFoundError:
        return None


def events_starting_on(body: bytes, day: dt.date) -> list[dict]:
    # The municipality's feed abuses pubDate as the event's start date.
    out = []
    for item in ET.fromstring(body).iter("item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        pub = item.findtext("pubDate")
        guid = (item.findtext("guid") or link or title).strip()
        if not title or not pub:
            continue
        try:
            when = email.utils.parsedate_to_datetime(pub).astimezone(TZ).date()
        except (TypeError, ValueError):
            continue
        if when == day:
            out.append({"title": title, "link": link, "guid": guid})
    return out


# ------------------------------------------------------------------ bot --


class Jay:
    def __init__(self) -> None:
        self.client = AsyncClient(
            HOMESERVER,
            USER_ID,
            store_path=str(STATE_DIR / "store"),
            config=AsyncClientConfig(
                store_sync_tokens=True, encryption_enabled=True
            ),
        )
        self.state = load_json(STATE_FILE, {"announced": [], "last_post_day": ""})
        self.reply_times: collections.deque[float] = collections.deque()
        self.started_at = time.time()
        self.room_id = ROOM

    async def resolve_room(self) -> None:
        if not ROOM.startswith("#"):
            return
        resp = await self.client.room_resolve_alias(ROOM)
        if not isinstance(resp, RoomResolveAliasResponse):
            raise SystemExit(f"cannot resolve {ROOM}: {resp}")
        self.room_id = resp.room_id

    # -- session ----------------------------------------------------------

    async def login(self) -> None:
        (STATE_DIR / "store").mkdir(exist_ok=True)
        session = load_json(SESSION_FILE, None)
        if session:
            self.client.restore_login(
                session["user_id"], session["device_id"], session["access_token"]
            )
            log.info("restored session for device %s", session["device_id"])
            return
        password = (CRED_DIR / "matrix-password").read_text().strip()
        resp = await self.client.login(password, device_name="jayvala")
        if not isinstance(resp, LoginResponse):
            raise SystemExit(f"login failed: {resp}")
        save_json(
            SESSION_FILE,
            {
                "user_id": resp.user_id,
                "device_id": resp.device_id,
                "access_token": resp.access_token,
            },
        )
        log.info("logged in as %s, device %s", resp.user_id, resp.device_id)

    async def send(self, room_id: str, text: str) -> None:
        await self.client.room_send(
            room_id,
            "m.room.message",
            {"msgtype": "m.text", "body": text},
            ignore_unverified_devices=True,
        )

    # -- callbacks --------------------------------------------------------

    async def on_invite(self, room: MatrixRoom, event: InviteMemberEvent) -> None:
        if event.state_key != USER_ID:
            return
        if event.sender.split(":", 1)[1] != USER_ID.split(":", 1)[1]:
            log.info("ignoring invite from %s", event.sender)
            return
        log.info("joining %s on invite from %s", room.room_id, event.sender)
        await self.client.join(room.room_id)

    async def on_message(self, room: MatrixRoom, event: RoomMessageText) -> None:
        if event.sender == USER_ID:
            return
        # Ignore history replayed on (re)start.
        if event.server_timestamp / 1000 < self.started_at - 60:
            return
        if not self.mentioned(event):
            return
        if not self.allow_reply():
            log.info("reply rate limit hit, staying quiet")
            return
        prompt = (
            "Alguém escreveu isto numa conversa, dirigindo-se a ti. "
            f"Responde como o Jay Vala.\n\n{event.body}"
        )
        try:
            text = await asyncio.to_thread(llm, prompt, 200)
        except Exception:
            log.exception("llm failed")
            return
        await self.send(room.room_id, text)

    async def on_undecryptable(self, room: MatrixRoom, event: MegolmEvent) -> None:
        log.warning("could not decrypt event %s in %s", event.event_id, room.room_id)

    def mentioned(self, event: RoomMessageText) -> bool:
        mentions = event.source.get("content", {}).get("m.mentions", {})
        if USER_ID in mentions.get("user_ids", []):
            return True
        body = event.body.lower()
        return any(n in body for n in NICKNAMES)

    def allow_reply(self) -> bool:
        now = time.time()
        while self.reply_times and now - self.reply_times[0] > 3600:
            self.reply_times.popleft()
        if len(self.reply_times) >= REPLIES_PER_HOUR:
            return False
        self.reply_times.append(now)
        return True

    # -- daily post -------------------------------------------------------

    async def daily_post(self) -> None:
        today = dt.datetime.now(TZ).date()
        if self.state["last_post_day"] == today.isoformat():
            return
        body = await asyncio.to_thread(fetch_feed)
        if body is None:
            log.warning("no feed available, skipping today")
            return
        events = [
            e
            for e in events_starting_on(body, today)
            if e["guid"] not in self.state["announced"]
        ]
        random.shuffle(events)
        for ev in events[:3]:
            prompt = (
                f"Hoje, {today.strftime('%d/%m/%Y')}, começa no concelho este evento: "
                f"«{ev['title']}». Escreve o teu post de Facebook a anunciar que o "
                "inauguraste pessoalmente, como se fosse a obra do século."
            )
            try:
                text = await asyncio.to_thread(llm, prompt)
            except Exception:
                log.exception("llm failed for %r", ev["title"])
                continue
            if ev["link"]:
                text = f"{text}\n\n{ev['link']}"
            await self.send(self.room_id, text)
            self.state["announced"].append(ev["guid"])
        self.state["announced"] = self.state["announced"][-500:]
        self.state["last_post_day"] = today.isoformat()
        save_json(STATE_FILE, self.state)
        log.info("daily post done: %d event(s)", len(events[:3]))

    async def scheduler(self) -> None:
        while True:
            now = dt.datetime.now(TZ)
            target = now.replace(hour=POST_HOUR, minute=0, second=0, microsecond=0)
            if now >= target:
                try:
                    await self.daily_post()
                except Exception:
                    log.exception("daily post failed")
                target += dt.timedelta(days=1)
            await asyncio.sleep((target - dt.datetime.now(TZ)).total_seconds())

    # -- main -------------------------------------------------------------

    async def run(self) -> None:
        await self.login()
        self.client.load_store()
        await self.resolve_room()
        self.client.add_event_callback(self.on_invite, InviteMemberEvent)
        self.client.add_event_callback(self.on_message, RoomMessageText)
        self.client.add_event_callback(self.on_undecryptable, MegolmEvent)
        if self.client.should_upload_keys:
            await self.client.keys_upload()
        asyncio.create_task(self.scheduler())
        try:
            await self.client.sync_forever(timeout=30000, full_state=True)
        finally:
            await self.client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    asyncio.run(Jay().run())
