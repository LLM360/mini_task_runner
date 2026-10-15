#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["aiohttp==3.14.4"]
# ///
"""proxy.py <dir> <port> <route>=<url>...: forward and record every model call of a trial.

Listens on <port> on every address of this machine. A request for /<route>/<rest> is forwarded,
unchanged, to <url>/<rest>, and the reply is passed back as it arrives. Each call gets its own
file, <dir>/000001.jsonl, 000002.jsonl, ..., written one line at a time while the call happens.
"t" is seconds since the call arrived:

  {"t": 0.0,  "route": "OPENAI_BASE_URL", "method": "POST", "path": "/chat/completions", "start": "2026-10-08T10:15:02.481Z", "request": {...}}
  {"t": 0.41, "status": 200}
  {"t": 0.42, "data": {...}}      a stream: one line per event, with "event": <name> when it has one
  {"t": 63.1, "body": {...}}      not a stream: the whole body, once it has all arrived
  {"t": 3.2,  "hung_up": true}    the caller left early; the proxy still reads the reply to the end
  {"t": 0.01, "error": "..."}     the server failed: a caller who got nothing yet gets a 502, one
                                  part-way through the reply has its connection cut
  {"t": 63.1, "end": true}

A file without "end" was cut off when the proxy was stopped. Headers are never recorded. The proxy
never gives up on a call by itself: a call that isn't streamed can take an hour, and its caller
decides how long to wait.
"""
import itertools
import json
import os
import sys
import time
from datetime import datetime, timezone

from aiohttp import ClientSession, ClientTimeout, web
from yarl import URL

DIR, PORT = sys.argv[1], int(sys.argv[2])
ROUTES = dict(arg.split("=", 1) for arg in sys.argv[3:])  # route name -> model server URL
NEVER_GIVE_UP = ClientTimeout(total=None)  # no time limit at all
TRANSPORT = {"host", "content-length", "transfer-encoding", "connection", "keep-alive",
             "accept-encoding", "content-encoding"}  # headers each hop sets for itself


# ── One call, from request to end ─────────────────────────────────────────────────────────────

async def handle(request):
    record = Record()
    route, _, rest = request.raw_path[1:].partition("/")  # "/agent/v1/chat/completions" → "agent", "v1/chat/completions"
    body = await request.read()
    record.write(route=route, method=request.method, path="/" + rest, start=utc_now(), request=parsed(body))
    caller = Caller(request, record)
    try:
        url = URL(f"{ROUTES[route]}/{rest}", encoded=True)  # encoded=True: the path goes out byte for byte
        async with model_servers.request(request.method, url, data=body,
                                         headers=without_transport(request.headers)) as reply:
            record.write(status=reply.status)
            await caller.start(reply.status, without_transport(reply.headers))
            if reply.content_type == "text/event-stream":
                await pass_stream(reply, caller, record)
            else:
                await pass_body(reply, caller, record)
            await caller.finish()
    except Exception as error:  # the server can't be reached, refuses, or breaks off
        record.write(error=f"{type(error).__name__}: {error}")
        caller.fail(str(error))
    record.end()
    return caller.response


async def pass_stream(reply, caller, record):
    """Pass each piece on as soon as it arrives; record each event once it is complete."""
    pending = b""
    async for piece in reply.content.iter_any():
        await caller.send(piece)
        pending = (pending + piece).replace(b"\r\n", b"\n")  # lines may also end in CRLF
        while b"\n\n" in pending:  # a blank line ends an event
            event, pending = pending.split(b"\n\n", 1)
            record.write(**parse_event(event))
    if pending.strip():  # a last event the server didn't end with a blank line
        record.write(**parse_event(pending))


async def pass_body(reply, caller, record):
    """Pass the body on as it arrives; record it once it has all arrived."""
    whole = b""
    async for piece in reply.content.iter_any():
        await caller.send(piece)
        whole += piece
    record.write(body=parsed(whole))


# ── The record of one call ─────────────────────────────────────────────────────────────────────

class Record:
    """One call's file. Every line is on disk as soon as it is written, so stopping the proxy can
    cut a record short but never lose what it already holds."""
    numbers = itertools.count(1)

    def __init__(self):
        self.file = open(f"{DIR}/{next(Record.numbers):06d}.jsonl", "w", buffering=1)  # 1: flush each line
        self.started = time.monotonic()

    def write(self, **fields):
        self.file.write(json.dumps({"t": round(time.monotonic() - self.started, 3), **fields}) + "\n")

    def end(self):
        self.write(end=True)
        self.file.close()


# ── The caller, and what happens when it leaves early ─────────────────────────────────────────

class Caller:
    """Whoever made the call. The reply goes to them piece by piece. If they leave early, the
    proxy notes it once and keeps reading the reply, so the record stays complete even when a
    client hangs up part-way through."""

    def __init__(self, request, record):
        self.request, self.record = request, record
        self.response = None  # the proxy's answer, made when the server's status arrives
        self.gone = False

    async def start(self, status, headers):
        self.response = web.StreamResponse(status=status, headers=headers)
        await self.try_to(self.response.prepare, self.request)  # sends the status line and headers

    async def send(self, piece):
        await self.try_to(self.response.write, piece)

    async def finish(self):
        await self.try_to(self.response.write_eof)

    async def try_to(self, write, *args):
        if self.gone:
            return
        try:
            await write(*args)
        except ConnectionResetError:  # the caller has left
            self.gone = True
            self.record.write(hung_up=True)

    def fail(self, error):
        """The server failed. A caller who has received nothing yet gets a 502 with the error. One
        part-way through the reply has its connection cut, as the server cut the proxy's, so it can't
        take half a reply for the whole."""
        if self.response is None:
            self.response = web.json_response({"error": {"message": error}}, status=502)
        elif self.request.transport:  # still connected
            self.request.transport.close()


# ── Small helpers ──────────────────────────────────────────────────────────────────────────────

def parse_event(raw):
    """One server-sent event: b'event: delta\\ndata: {"x": 1}' → {"event": "delta", "data": {"x": 1}}."""
    event, data = {}, []
    for line in raw.decode(errors="replace").splitlines():
        field, _, value = line.partition(":")
        if field == "event":
            event["event"] = value.strip()
        elif field == "data":
            data.append(value.removeprefix(" "))
    event["data"] = parsed("\n".join(data).encode())
    return event


def parsed(raw):
    """The JSON in raw; its text if it isn't JSON; None if it's empty."""
    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return raw.decode(errors="replace")


def without_transport(headers):
    return {name: value for name, value in headers.items() if name.lower() not in TRANSPORT}


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


# ── Start ──────────────────────────────────────────────────────────────────────────────────────

async def open_client(app):
    """One client to the model servers, shared by every call. It keeps connections open between
    calls (a new connection per call hits the relay's 68 s stall) and never gives up on a call."""
    global model_servers
    model_servers = ClientSession(timeout=NEVER_GIVE_UP)


os.makedirs(DIR, exist_ok=True)
sys.stdout.reconfigure(line_buffering=True)  # proxy.log gets each line at once, even if the proxy is killed
app = web.Application(client_max_size=2**30)  # agents' requests can be far over aiohttp's 1 MB default
app.on_startup.append(open_client)
app.router.add_route("*", "/{path:.*}", handle)
web.run_app(app, port=PORT, handle_signals=False)  # SIGTERM stops it at once: every line is already on disk
