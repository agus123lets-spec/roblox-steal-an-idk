// Steel Front room server: serves the game page and hosts online rooms over WebSocket.
// Each room runs the game's own simulation headless in a worker thread (see headless.js / room-worker.js)
// as the authority for bots, damage, zones and tickets. Players connect to /ws.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import { WebSocketServer } from "ws";
import { extractScript } from "./headless.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const MAX_PLAYERS = 14; // 7 seats a side
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I
const EMPTY_ROOM_GRACE_MS = 60_000; // keep an empty room around briefly so a reload can rejoin it

const clean = (s, max, fallback) => String(s ?? "").replace(/[^\p{L}\p{N} _'.-]/gu, "").replace(/\s+/g, " ").trim().slice(0, max) || fallback;

export function startServer({
  port = Number(process.env.PORT) || 8080,
  host = process.env.HOST || "0.0.0.0",
  htmlPath = process.env.STEELFRONT_HTML || path.join(here, "..", "steelfront.html"),
  maxRooms = Number(process.env.MAX_ROOMS) || 8,
  log = (...a) => console.log(new Date().toISOString(), ...a),
} = {}) {
  let page = { mtime: 0, html: "" };
  const readPage = () => {
    const st = fs.statSync(htmlPath);
    if (st.mtimeMs !== page.mtime) page = { mtime: st.mtimeMs, html: fs.readFileSync(htmlPath, "utf8") };
    return page.html;
  };
  readPage(); // fail fast if the game file is missing

  const rooms = new Map(); // code -> room
  const clients = new Set();
  let nextId = 1;

  const httpServer = http.createServer((req, res) => {
    const url = new URL(req.url, "http://x");
    if (req.method !== "GET" && req.method !== "HEAD") { res.writeHead(405).end(); return; }
    if (url.pathname === "/" || url.pathname === "/index.html" || url.pathname === "/steelfront.html") {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-cache" });
      res.end(req.method === "HEAD" ? undefined : readPage());
    } else if (url.pathname === "/healthz") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, rooms: rooms.size, players: [...rooms.values()].reduce((n, r) => n + r.members.size, 0) }));
    } else res.writeHead(404, { "content-type": "text/plain" }).end("not found");
  });

  const wss = new WebSocketServer({ server: httpServer, path: "/ws", maxPayload: 64 * 1024, perMessageDeflate: { threshold: 512 } });
  const send = (c, m) => { if (c.ws.readyState === 1) c.ws.send(typeof m === "string" ? m : JSON.stringify(m)); };
  const roomList = () => [...rooms.values()].filter(r => !r.priv).map(r => ({ code: r.code, name: r.name, n: r.members.size, max: MAX_PLAYERS }));
  let listTimer = null;
  const announceRooms = () => {
    if (listTimer) return;
    listTimer = setTimeout(() => {
      listTimer = null;
      const m = JSON.stringify({ t: "rooms", rooms: roomList() });
      for (const c of clients) if (!c.room && c.name) send(c, m);
    }, 250);
  };

  function createRoom(name, priv) {
    let code;
    do code = Array.from({ length: 5 }, () => CODE_CHARS[(Math.random() * CODE_CHARS.length) | 0]).join(""); while (rooms.has(code));
    const seed = (Math.random() * 2 ** 31) | 0;
    const worker = new Worker(path.join(here, "room-worker.js"), { workerData: { script: extractScript(readPage()), seed } });
    const room = { code, name, priv, seed, worker, members: new Map(), emptyTimer: null, closed: false };
    worker.on("message", m => {
      if (m.t === "snap") {
        const msg = `{"t":"s","d":${m.json}}`;
        // skip players whose connection is badly backed up rather than queueing snapshots without limit
        for (const c of room.members.values()) if (c.ws.readyState === 1 && c.ws.bufferedAmount < 1 << 20) c.ws.send(msg);
      } else if (m.t === "added" && m.seat < 0) {
        const c = room.members.get(m.id);
        if (c) { leaveRoom(c); send(c, { t: "error", msg: "That room is full." }); }
      } else if (m.t === "ready") log(`room ${code} ready`);
    });
    worker.on("error", err => { log(`room ${code} crashed:`, err); closeRoom(room, "The room stopped because of a server error."); });
    rooms.set(code, room);
    log(`room ${code} created (${priv ? "private" : "public"}) "${name}"`);
    return room;
  }
  function closeRoom(room, why) {
    if (room.closed) return;
    room.closed = true;
    clearTimeout(room.emptyTimer);
    rooms.delete(room.code);
    room.worker.terminate();
    for (const c of room.members.values()) { c.room = null; if (why) send(c, { t: "error", msg: why }); }
    room.members.clear();
    log(`room ${room.code} closed`);
    announceRooms();
  }
  function joinRoom(c, room, team) {
    if (c.room) leaveRoom(c);
    if (room.members.size >= MAX_PLAYERS) { send(c, { t: "error", msg: "That room is full." }); return; }
    // keep names unique within a room so the scoreboard and kill feed stay readable
    let name = c.name;
    const taken = new Set([...room.members.values()].map(m => m.roomName));
    for (let i = 2; taken.has(name); i++) name = `${c.name.slice(0, 12)} (${i})`;
    c.roomName = name; c.room = room;
    clearTimeout(room.emptyTimer);
    room.members.set(c.id, c);
    room.worker.postMessage({ t: "add", id: c.id, name, team: team === 0 || team === 1 ? team : -1 });
    send(c, { t: "joined", code: room.code, room: room.name, name, seed: room.seed });
    log(`${name} (#${c.id}) joined ${room.code} (${room.members.size} players)`);
    announceRooms();
  }
  function leaveRoom(c) {
    const room = c.room;
    if (!room) return;
    c.room = null;
    room.members.delete(c.id);
    if (!room.closed) room.worker.postMessage({ t: "remove", id: c.id });
    if (!room.members.size) room.emptyTimer = setTimeout(() => closeRoom(room), EMPTY_ROOM_GRACE_MS);
    announceRooms();
  }

  wss.on("connection", ws => {
    const c = { id: nextId++, ws, name: null, room: null, roomName: null, alive: true, budget: 0, budgetT: Date.now() };
    clients.add(c);
    ws.on("pong", () => { c.alive = true; });
    ws.on("message", (raw, isBinary) => {
      // simple flood guard: about 120 messages a second is plenty (the game sends 30)
      const t = Date.now();
      if (t - c.budgetT > 1000) { c.budgetT = t; c.budget = 0; }
      if (++c.budget > 120 || isBinary) return;
      let m;
      try { m = JSON.parse(raw); } catch { return; }
      if (!m || typeof m !== "object") return;
      if (m.t === "in") { if (c.room && m.d && typeof m.d === "object") c.room.worker.postMessage({ t: "in", id: c.id, d: m.d }); return; }
      if (m.t === "hello") { c.name = clean(m.name, 16, "Player"); send(c, { t: "welcome", id: c.id, name: c.name }); return; }
      if (!c.name) return;
      if (m.t === "list") send(c, { t: "rooms", rooms: roomList() });
      else if (m.t === "create") {
        if (rooms.size >= maxRooms) { send(c, { t: "error", msg: "The server is at its room limit. Join an existing room or try again later." }); return; }
        joinRoom(c, createRoom(clean(m.name, 24, `${c.name}'s room`), !!m.priv), m.team);
      } else if (m.t === "join") {
        const room = rooms.get(String(m.code || "").toUpperCase());
        if (!room) send(c, { t: "error", msg: "No room with that code. Check the code, or ask for a new invite." });
        else joinRoom(c, room, m.team);
      } else if (m.t === "leave") leaveRoom(c);
    });
    ws.on("close", () => { leaveRoom(c); clients.delete(c); });
  });

  // drop connections that stopped answering (closed laptop lid, lost Wi-Fi)
  const heartbeat = setInterval(() => {
    for (const c of clients) {
      if (!c.alive) { c.ws.terminate(); continue; }
      c.alive = false;
      c.ws.ping();
    }
  }, 20_000);

  return new Promise(resolve => {
    httpServer.listen(port, host, () => {
      const actual = httpServer.address().port;
      log(`Steel Front server on http://${host === "0.0.0.0" ? "localhost" : host}:${actual}/ (WebSocket /ws)`);
      resolve({
        port: actual,
        rooms,
        close: () => new Promise(done => {
          clearInterval(heartbeat);
          for (const r of [...rooms.values()]) closeRoom(r);
          for (const c of clients) c.ws.terminate();
          wss.close();
          httpServer.close(() => done());
        }),
      });
    });
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const srv = await startServer();
  const stop = () => srv.close().then(() => process.exit(0));
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
}
