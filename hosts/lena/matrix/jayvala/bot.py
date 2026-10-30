"""Jay Vala — a fictional mayor of Porto de Mós who lives in our Matrix rooms.

Two jobs:
  * every morning, post what is on today in his own municipality and what
    comes next, in the voice of a small-town mayor;
  * reply, in character, when someone mentions him, replies to one of his
    messages, or keeps asking him things right after he answered them. The
    reply prompt carries the upcoming agenda of the whole region and the last
    messages of the room, so answers stay factual and he does not repeat
    himself.

Event sources are configured in jayvala.nix (JAYVALA_SOURCES, a JSON list):
the municipal feeds of Porto de Mós and Batalha (same CMS, RSS), Leiria's
agenda site and the programme of Leiria's municipal theatres (both HTML).
A curated list of places to eat (JAYVALA_RESTAURANTS, see restaurantes.json)
is added to the prompt only when the message is about food. Secrets come from
systemd credentials.
"""

import asyncio
import collections
import datetime as dt
import email.utils
import html
import json
import logging
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zoneinfo
from pathlib import Path

from bs4 import BeautifulSoup
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
SOURCES = json.loads(os.environ["JAYVALA_SOURCES"])
RESTAURANTS = json.loads(Path(os.environ["JAYVALA_RESTAURANTS"]).read_text())
LLM_URL = os.environ["JAYVALA_LLM_URL"]
LLM_MODEL = os.environ["JAYVALA_LLM_MODEL"]
POST_HOUR = int(os.environ.get("JAYVALA_POST_HOUR", "8"))
REPLIES_PER_HOUR = int(os.environ.get("JAYVALA_REPLIES_PER_HOUR", "10"))
TZ = zoneinfo.ZoneInfo(os.environ.get("JAYVALA_TZ", "Europe/Lisbon"))

STATE_DIR = Path(os.environ["STATE_DIRECTORY"])
CRED_DIR = Path(os.environ["CREDENTIALS_DIRECTORY"])
SESSION_FILE = STATE_DIR / "session.json"
STATE_FILE = STATE_DIR / "state.json"
CACHE_DIR = STATE_DIR / "cache"

NICKNAMES = ("jay", "presidente", "sr. presidente", "senhor presidente")

# Within FOLLOW_UP seconds of a reply, a message that looks like a question
# from the same person is taken as addressed to Jay even without his name.
QUESTION = re.compile(
    r"\?|\b(o que|onde|quando|qual|quais|quem|como|porqu\w*|quero saber|diz-me|diga-me|conta-me)\b",
    re.IGNORECASE,
)

# A message about food gets the restaurant list in its prompt.
FOOD_WORDS = re.compile(
    r"\b(com(er|ida|e|es|em|emos)\b|restaurant|almo[çc]|jant|tasca|tabern|petisc|caf[eé]\b"
    r"|pastelar|pizz|churrasc|frango|leit[ãa]o|bitoque|fome\b|lanch|marisc|peix|bacalhau"
    r"|cozido|sobremesa|beber|cervej|gelad|esplanad|hamb[uú]rg|snack|bar\b)",
    re.IGNORECASE,
)

# Agenda handed to the model when replying: how far ahead it looks, how many
# events per source at most, and how old a source's cache may be before it is
# fetched again (the daily post always refreshes its own sources).
AGENDA_DAYS = 14
AGENDA_MAX = 8
FEED_MAX_AGE = 3 * 3600
LEIRIAGENDA_PAGE = 14  # results per listing page on leiriagenda.cm-leiria.pt
HISTORY = 12  # messages per room kept as context for replies
FOLLOW_UP = 180  # seconds during which whoever Jay just answered keeps his attention

WEEKDAYS = ("seg", "ter", "qua", "qui", "sex", "sáb", "dom")
MONTHS = {
    "jan": 1, "fev": 2, "mar": 3, "abr": 4, "mai": 5, "jun": 6,
    "jul": 7, "ago": 8, "set": 9, "out": 10, "nov": 11, "dez": 12,
}

PERSONA = """\
És o Jay Vala, Presidente da Câmara Municipal de Porto de Mós. És uma personagem \
fictícia e cómica: um autarca de concelho pequeno, orgulhoso da terra, que leva \
tudo demasiado a sério e fala em nome do "executivo" mesmo quando o assunto é um \
torneio de sueca. Mas estás numa conversa de chat, não num comunicado: escreves \
de forma natural e directa, como quem fala com um munícipe à porta da Câmara. Uma \
frase pomposa de vez em quando chega. Sem hashtags, sem emojis, sem markdown, \
sem listas, e sem enumerar freguesias só por enumerar. Leiria e Batalha são \
concelhos vizinhos: conheces a agenda deles e falas disso como bom vizinho, com \
uma pontinha de bairrismo (o melhor é sempre em Porto de Mós), mas sem desprezo.

Regras:
- Escreves sempre em português de Portugal, sem acordo ortográfico de 1990. \
Máximo 80 palavras.
- Só usas informação real: a agenda que recebes em cada pedido e o que é sabido \
sobre a região (o castelo de Porto de Mós, as Grutas de Mira de Aire, a Serra de \
Aire e Candeeiros, o Mosteiro da Batalha, o castelo de Leiria, as freguesias). \
Nunca inventes obras, rotundas, inaugurações, datas, horas, locais, preços ou \
números. Se a agenda não disser a hora ou o preço, não os inventes. Se não \
tiveres a informação, dizes que vais confirmar com os serviços.
- Nunca mencionas pessoas reais nem partidos. Se te perguntarem se és real, \
respondes que és o Jay Vala e mudas de assunto.
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
            "temperature": 0.7,
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


# -------------------------------------------------------------- sources --


def fetch(url: str, cache: Path) -> bytes | None:
    """GET url, honouring ETags. On 304 or any failure return the cached copy;
    None only when there is no cached copy either."""
    headers = {"user-agent": "jayvala-bot/1 (+https://pdmos.pt)"}
    etag_file = cache.with_suffix(".etag")
    try:
        headers["if-none-match"] = etag_file.read_text().strip()
    except FileNotFoundError:
        pass
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, headers=headers), timeout=30
        ) as resp:
            body = resp.read()
            etag = resp.headers.get("etag")
        cache.write_bytes(body)
        if etag:
            etag_file.write_text(etag)
        else:
            etag_file.unlink(missing_ok=True)
        return body
    except urllib.error.HTTPError as e:
        if e.code != 304:
            log.warning("%s: HTTP %s, using cached copy", url, e.code)
    except (urllib.error.URLError, TimeoutError) as e:
        log.warning("%s: %s, using cached copy", url, e)
    try:
        return cache.read_bytes()
    except FileNotFoundError:
        return None


def strip_html(text: str | None) -> str:
    text = re.sub(r"<[^>]+>", " ", text or "")
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def event(source: dict, **fields) -> dict:
    return {"source": source["name"], "venue": "", "place": "", "desc": "", "end": None} | fields


def parse_rss(body: bytes, source: dict) -> list[dict]:
    """The municipal CMS feeds (Porto de Mós, Batalha): pubDate is the event's
    start and the description, when present, holds the details."""
    out = []
    for item in ET.fromstring(body).iter("item"):
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        pub = item.findtext("pubDate")
        if not title or not pub:
            continue
        try:
            when = email.utils.parsedate_to_datetime(pub).astimezone(TZ)
        except (TypeError, ValueError):
            continue
        out.append(
            event(
                source,
                title=title,
                when=when,
                desc=strip_html(item.findtext("description")),
                link=link,
                guid=(item.findtext("guid") or link or title).strip(),
            )
        )
    return out


def parse_leiriagenda(body: bytes, source: dict) -> list[dict]:
    """leiriagenda.cm-leiria.pt listing: each card has a date block of spans
    (day, month, year, then an optional time or an end date), title, venue,
    locality and categories."""
    out = []
    for a in BeautifulSoup(body, "html.parser").select("a[href*='/pt/agenda/']"):
        card = a.select_one(".component-inner")
        if card is None:
            continue
        tokens = [s.get_text(strip=True) for s in card.select(".date span")]
        dates, when_time = [], None
        for i, tok in enumerate(tokens):
            if tok.isdigit() and i + 2 < len(tokens) and tokens[i + 1].rstrip(".").lower()[:3] in MONTHS:
                try:
                    dates.append(dt.date(int(tokens[i + 2]), MONTHS[tokens[i + 1].rstrip(".").lower()[:3]], int(tok)))
                except ValueError:
                    pass
            elif m := re.fullmatch(r"(\d{1,2})h(\d{2})", tok):
                when_time = dt.time(int(m[1]), int(m[2]))
        if not dates:
            continue
        when = dt.datetime.combine(dates[0], when_time or dt.time(0, 0), TZ)
        title = card.select_one(".proximo_title")
        venue = card.select_one(".location .local")
        locality = card.select_one(".location .localidade")
        cats = dict.fromkeys(c.get_text(strip=True) for c in card.select(".categorias small"))
        if title is None:
            continue
        out.append(
            event(
                source,
                title=title.get_text(strip=True),
                when=when,
                end=dates[1] if len(dates) > 1 and dates[1] != dates[0] else None,
                venue=venue.get_text(strip=True) if venue else "",
                place=locality.get_text(strip=True) if locality else "",
                desc=", ".join(cats),
                link=a["href"],
                guid=a["href"],
            )
        )
    return out


def parse_tjls(body: bytes, source: dict) -> list[dict]:
    """teatrojlsilva.pt programme: one <article> per show with a <time> tag,
    the hall name, the title and a coloured category label."""
    out = []
    for art in BeautifulSoup(body, "html.parser").select("article"):
        a = art.select_one("a[href*='/evento/']")
        t = art.select_one("time[datetime]")
        h = art.select_one("h3")
        if not (a and t and h):
            continue
        try:
            when = dt.datetime.fromisoformat(t["datetime"])
        except ValueError:
            continue
        if when.tzinfo is None:
            when = when.replace(tzinfo=TZ)
        venue = art.select_one("span.truncate")
        cat = art.select_one("span[style*='background-color']")
        out.append(
            event(
                source,
                title=h.get_text(strip=True),
                when=when,
                venue=venue.get_text(strip=True) if venue else "",
                desc=cat.get_text(strip=True).capitalize() if cat else "",
                link=a["href"],
                guid=a["href"],
            )
        )
    return out


PARSERS = {"rss": parse_rss, "leiriagenda": parse_leiriagenda, "tjls": parse_tjls}


def source_urls(source: dict, now: dt.datetime) -> list[str]:
    """The requests needed to cover the agenda window for one source."""
    url, kind = source["url"], source["kind"]
    today = now.date()
    if kind == "leiriagenda":
        # The listing shows at most LEIRIAGENDA_PAGE results and data_fim is
        # exclusive, so ask for one day at a time.
        urls = []
        for n in range(AGENDA_DAYS):
            a = today + dt.timedelta(days=n)
            q = urllib.parse.urlencode(
                {"data_inicio": a.isoformat(), "data_fim": (a + dt.timedelta(days=1)).isoformat()}
            )
            urls.append(f"{url}?{q}")
        return urls
    if kind == "tjls":
        # 25 shows per page, sorted by date; three pages cover well over two weeks.
        return [f"{url}?page={n}" for n in (1, 2, 3)]
    return [url]


def load_source(source: dict, now: dt.datetime) -> list[dict]:
    """Fetch and parse everything one source publishes for the agenda window."""
    CACHE_DIR.mkdir(exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", source["name"].lower())
    events, seen = [], set()
    for n, url in enumerate(source_urls(source, now)):
        body = fetch(url, CACHE_DIR / f"{slug}-{n}.body")
        if body is None:
            continue
        try:
            parsed = PARSERS[source["kind"]](body, source)
        except Exception:
            log.exception("%s: cannot parse %s", source["name"], url)
            continue
        if source["kind"] == "leiriagenda" and len(parsed) >= LEIRIAGENDA_PAGE:
            log.warning("%s: %s returned %d events, the listing may be truncated", source["name"], url, len(parsed))
        for e in parsed:
            if e["guid"] not in seen:
                seen.add(e["guid"])
                events.append(e)
    events.sort(key=lambda e: e["when"])
    log.info("%s: %d event(s)", source["name"], len(events))
    return events


# -------------------------------------------------------------- agenda --


def fmt_date(day: dt.date) -> str:
    return f"{WEEKDAYS[day.weekday()]} {day:%d/%m/%Y}"


def fmt_when(e: dict) -> str:
    when = e["when"]
    text = f"{WEEKDAYS[when.weekday()]} {when:%d/%m}"
    if e["end"]:
        text += f" a {WEEKDAYS[e['end'].weekday()]} {e['end']:%d/%m}"
    elif (when.hour, when.minute) != (0, 0):
        text += f" às {when:%H:%M}"
    return text


def event_line(e: dict, detail: int = 400) -> str:
    line = f"- {fmt_when(e)}: {e['title']}"
    where = ", ".join(x for x in (e["venue"], e["place"]) if x)
    extra = " — ".join(x for x in (where, e["desc"][:detail]) if x)
    return f"{line} — {extra}" if extra else line


def agenda_text(events: list[dict], now: dt.datetime) -> str:
    """Upcoming events grouped by source, in the order sources are configured.
    A show listed by two sources (Leiria's agenda also carries the theatres'
    programme) is kept under the first source only."""
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + dt.timedelta(days=AGENDA_DAYS)
    blocks, listed = [], set()
    for source in SOURCES:
        lines = []
        for e in events:
            key = (re.sub(r"\W+", " ", e["title"].lower()).strip(), e["when"].date())
            if e["source"] != source["name"] or not start <= e["when"] < end or key in listed:
                continue
            if len(lines) == AGENDA_MAX:
                break
            listed.add(key)
            lines.append(event_line(e))
        blocks.append(f"{source['name']}:\n" + "\n".join(lines or ["- (nada na agenda)"]))
    return "\n".join(blocks)


def restaurants_text() -> str:
    """Places to eat grouped by municipality, the mayor's own first, busiest
    (most reviewed) first within each."""
    order = {s["name"]: i for i, s in enumerate(SOURCES)}
    places = sorted(RESTAURANTS["restaurantes"], key=lambda r: (order.get(r["concelho"], 99), -r["avaliacoes"]))
    blocks: dict[str, list[str]] = {}
    for r in places:
        bits = [r["localidade"] or r["concelho"], r["categoria"]]
        if r["nota"]:
            bits.append(f"{r['nota']} em {r['avaliacoes']} avaliações")
        if r["preco"]:
            bits.append("€" * r["preco"])
        blocks.setdefault(r["concelho"], []).append(f"- {r['nome']} ({'; '.join(bits)})")
    return "\n".join(f"{town}:\n" + "\n".join(lines) for town, lines in blocks.items())


def message_text(event: RoomMessageText) -> str:
    """The message body without the quoted fallback some clients prepend to replies."""
    body = event.body
    if "m.in_reply_to" in event.source.get("content", {}).get("m.relates_to", {}):
        body = re.sub(r"\A(?:>.*\n)+\n?", "", body)
    return body


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
        self.state = load_json(STATE_FILE, {"last_post_day": ""})
        self.reply_times: collections.deque[float] = collections.deque()
        self.started_at = time.time()
        self.room_id = ROOM
        self.feeds: dict[str, tuple[float, list[dict]]] = {}
        self.history: dict[str, collections.deque[tuple[str, str]]] = collections.defaultdict(
            lambda: collections.deque(maxlen=HISTORY)
        )
        self.own_events: collections.deque[str] = collections.deque(maxlen=200)
        self.last_reply: dict[str, float] = {}  # sender -> when Jay last answered them

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

    # -- sources ----------------------------------------------------------

    async def events(self, sources: list[dict], max_age: float = FEED_MAX_AGE) -> list[dict]:
        """Events of the given sources, refreshed when older than max_age seconds.
        A source that yields nothing keeps its previous events."""
        now = dt.datetime.now(TZ)
        out = []
        for source in sources:
            fetched, events = self.feeds.get(source["name"], (0.0, []))
            if time.time() - fetched >= max_age:
                fresh = await asyncio.to_thread(load_source, source, now)
                if fresh or not events:
                    events = fresh
                else:
                    log.warning("%s: no events parsed, keeping previous ones", source["name"])
                self.feeds[source["name"]] = (time.time(), events)
            out.extend(events)
        return out

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
        # Every message, ours included, is remembered as context for replies.
        name = "Jay Vala" if event.sender == USER_ID else room.user_name(event.sender) or event.sender
        body = message_text(event)
        earlier = "\n".join(f"{n}: {' '.join(t.split())[:300]}" for n, t in self.history[room.room_id])
        self.history[room.room_id].append((name, body))
        if event.sender == USER_ID:
            self.own_events.append(event.event_id)
            return
        # Ignore history replayed on (re)start.
        if event.server_timestamp / 1000 < self.started_at - 60:
            return
        if not self.mentioned(event, body):
            return
        if not self.allow_reply():
            log.info("reply rate limit hit, staying quiet")
            return
        now = dt.datetime.now(TZ)
        agenda = agenda_text(await self.events(SOURCES), now)
        food = ""
        if FOOD_WORDS.search(body):
            food = (
                f"Sítios para comer, segundo o {RESTAURANTS['fonte']}, por número "
                f"de avaliações:\n{restaurants_text()}\n\n"
                "Se perguntarem onde comer, usa só esta lista: podes dizer a localidade, "
                "o tipo e a nota, mais nada. Puxa pelo teu concelho, sem esconder a "
                "Batalha.\n\n"
            )
        prompt = (
            f"Hoje é {fmt_date(now.date())}. Agenda dos próximos {AGENDA_DAYS} dias, "
            "por concelho ou sala, segundo os sites oficiais (Câmaras de Porto de Mós, "
            f"Batalha e Leiria, e o Teatro José Lúcio da Silva):\n{agenda}\n\n"
            f"{food}"
            "Últimas mensagens da sala, da mais antiga para a mais recente:\n"
            f"{earlier or '(nenhuma)'}\n\n"
            f"Agora {name} escreveu, dirigindo-se a ti:\n«{body}»\n\n"
            "Responde como o Jay Vala, em conversa, só a esta última mensagem. Trata as "
            "pessoas pelo primeiro nome e só de vez em quando; não comeces a resposta "
            "pelo nome de quem escreveu. A agenda "
            "serve para quando perguntam o que há para fazer ou por um evento concreto: "
            "aí usa só o que lá está e diz de que terra é cada coisa. Noutros assuntos "
            "responde ao que te perguntam, em personagem e sem inventar factos, e não "
            "metas eventos na resposta. Não repitas o que já disseste acima nem voltes "
            "a anunciar eventos que já referiste."
        )
        try:
            text = await asyncio.to_thread(llm, prompt, 200)
        except Exception:
            log.exception("llm failed")
            return
        await self.send(room.room_id, text)
        self.last_reply[event.sender] = time.time()

    async def on_undecryptable(self, room: MatrixRoom, event: MegolmEvent) -> None:
        log.warning("could not decrypt event %s in %s", event.event_id, room.room_id)

    def mentioned(self, event: RoomMessageText, body: str) -> bool:
        content = event.source.get("content", {})
        if USER_ID in content.get("m.mentions", {}).get("user_ids", []):
            return True
        if content.get("m.relates_to", {}).get("m.in_reply_to", {}).get("event_id") in self.own_events:
            return True
        lower = body.lower()
        if any(n in lower for n in NICKNAMES):
            return True
        recent = time.time() - self.last_reply.get(event.sender, 0) < FOLLOW_UP
        return recent and QUESTION.search(lower) is not None

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
        """Every morning, say what is on today in the mayor's own municipality
        and what comes next. Raises when the feed gives nothing, so the
        scheduler retries instead of skipping the day."""
        today = dt.datetime.now(TZ).date()
        if self.state["last_post_day"] == today.isoformat():
            return
        home = [s for s in SOURCES if s.get("home")]
        events = await self.events(home, max_age=0)
        if not events:
            raise RuntimeError("no events from the home feed")
        on_today = [e for e in events if e["when"].date() == today][:5]
        upcoming = [e for e in events if today < e["when"].date() <= today + dt.timedelta(days=AGENDA_DAYS)][:3]

        def block(evs: list[dict]) -> str:
            return "\n".join(event_line(e) for e in evs) or "- (nada na agenda)"

        prompt = (
            f"Hoje é {fmt_date(today)} e esta é a tua mensagem da manhã na sala. "
            f"Segundo a agenda da Câmara, no teu concelho há hoje:\n{block(on_today)}\n\n"
            f"E a seguir, nos próximos {AGENDA_DAYS} dias:\n{block(upcoming)}\n\n"
            "Dá os bons-dias e diz aos munícipes o que há para fazer hoje; se hoje não "
            "houver nada, diz isso mesmo e aponta o que aí vem. Usa só os dados acima: "
            "não acrescentes horas, locais, preços ou pormenores que não constem. Podes "
            "dizer que lá estarás em representação do executivo. Hoje podes ir até 120 "
            "palavras."
        )
        text = await asyncio.to_thread(llm, prompt)
        links = [e["link"] for e in (on_today or upcoming) if e["link"]]
        if links:
            text = text + "\n\n" + "\n".join(links)
        await self.send(self.room_id, text)
        self.state["last_post_day"] = today.isoformat()
        save_json(STATE_FILE, self.state)
        log.info("morning post done: %d today, %d upcoming", len(on_today), len(upcoming))

    async def scheduler(self) -> None:
        while True:
            now = dt.datetime.now(TZ)
            target = now.replace(hour=POST_HOUR, minute=0, second=0, microsecond=0)
            if now >= target:
                try:
                    await self.daily_post()
                except Exception:
                    log.exception("morning post failed, retrying in 10 min")
                    await asyncio.sleep(600)
                    continue
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
        asyncio.create_task(self.events(SOURCES))  # warm the cache for the first reply
        asyncio.create_task(self.scheduler())
        try:
            await self.client.sync_forever(timeout=30000, full_state=True)
        finally:
            await self.client.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    asyncio.run(Jay().run())
