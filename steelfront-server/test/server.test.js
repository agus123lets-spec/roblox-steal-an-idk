// End-to-end tests: a real server, real room workers and WebSocket clients speaking the game's protocol.
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import WebSocket from "ws";
import { startServer } from "../server.js";

let srv, base;
before(async () => {
  srv = await startServer({ port: 0, host: "127.0.0.1", log: () => {} });
  base = `127.0.0.1:${srv.port}`;
});
after(() => srv.close());

// minimal scripted player
class Client {
  constructor(name) {
    this.name = name; this.msgs = []; this.waiters = []; this.snap = null; this.events = [];
    this.ws = new WebSocket(`ws://${base}/ws`);
    this.ws.on("message", raw => {
      const m = JSON.parse(raw);
      if (m.t === "s") { this.snap = m.d; this.events.push(...m.d.e); } else this.msgs.push(m);
      for (const w of this.waiters.splice(0)) w();
    });
    this.open = new Promise(r => this.ws.on("open", r));
  }
  send(m) { this.ws.send(JSON.stringify(m)); }
  async until(pred, what, ms = 15000) {
    const end = Date.now() + ms;
    for (;;) {
      const v = pred();
      if (v) return v;
      if (Date.now() > end) throw new Error(`timed out waiting for ${what}`);
      await new Promise(r => { this.waiters.push(r); setTimeout(r, 100); });
    }
  }
  msg(t) { return this.until(() => this.msgs.find(m => m.t === t), t); }
  async hello() { await this.open; this.send({ t: "hello", name: this.name }); this.id = (await this.msg("welcome")).id; }
  seat() { return this.snap && this.snap.u.find(u => u[4] === this.id); }
  unit(id) { return this.snap && this.snap.u[id]; }
  // send our vehicle's movement block: [time, life, flags, pos, orientation, vel, speed, throttle, bombs, rockets, type]
  state(life, ty, pos, yaw = 0, flags = 1) {
    this.t = (this.t || 0) + 0.05;
    this.send({ t: "in", d: { st: [this.t, life, flags, ...pos, yaw, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, ty], e: this.out || [] } });
    this.out = [];
  }
  close() { this.ws.close(); }
}

test("serves the game page and a health check", async () => {
  const page = await fetch(`http://${base}/`);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /STEEL FRONT/);
  const health = await (await fetch(`http://${base}/healthz`)).json();
  assert.equal(health.ok, true);
});

test("two players share a room: seats, movement, hits, kills and leaving", { timeout: 60000 }, async () => {
  const a = new Client("Alice"), b = new Client("Bob <b>");
  await a.hello(); await b.hello();

  a.send({ t: "create", name: "Test room", priv: false, team: -1 });
  const joined = await a.msg("joined");
  assert.match(joined.code, /^[A-Z2-9]{5}$/);
  assert.equal(joined.room, "Test room");

  // public rooms show up in the lobby list
  b.send({ t: "list" });
  const list = await b.until(() => b.msgs.find(m => m.t === "rooms" && m.rooms.some(r => r.code === joined.code)), "room list");
  assert.equal(list.rooms.find(r => r.code === joined.code).n, 1);

  b.send({ t: "join", code: joined.code.toLowerCase(), team: -1 });
  const bj = await b.msg("joined");
  assert.equal(bj.seed, joined.seed, "everyone builds the same map");
  assert.equal(bj.name, "Bob b", "names are sanitised by the server");

  // both get a seat, balanced across the two teams, waiting to deploy
  const sa = await a.until(() => a.seat(), "Alice's seat");
  const sb = await b.until(() => b.seat(), "Bob's seat");
  assert.notEqual(sa[2], sb[2], "auto balance puts them on different teams");
  assert.ok(sa[3] & 2 && sa[3] & 32, "seat is idle and marked as a player");
  assert.equal(b.snap.u.filter(u => u[3] & 32).length, 2);
  assert.equal(b.snap.u.length, 14, "bots fill the other seats");

  // deploy: Alice in a Tiger, Bob in a Sherman 40 m in front of her
  const la = sa[5] + 1, lb = sb[5] + 1;
  const pa = [0, 30, -100], pb = [0, 30, -60];
  a.out = [{ k: "spawn", ty: "tiger", life: la }];
  b.out = [{ k: "spawn", ty: "sherman", life: lb }];
  for (let i = 0; i < 6; i++) { a.state(la, "tiger", pa); b.state(lb, "sherman", pb); await new Promise(r => setTimeout(r, 50)); }
  const bobSeen = await a.until(() => { const u = a.unit(sb[0]); return u && u[3] & 1 && u[1] === "sherman" && Math.abs(u[9] - pb[2]) < 0.5 && u; }, "Bob deployed at his position");
  assert.ok(Math.abs(bobSeen[7] - pb[0]) < 0.5, "server relays the position the player sent");

  // other players see Alice's shots; she fires and claims front-hull penetrations on Bob
  const hp0 = bobSeen[6];
  const claim = { k: "hit", w: "main", st: [0, 32, -96], p: [0, 31, -62.9], kind: "tank", tg: sb[0], part: "hull", axis: 2, sign: 1, dir: [0, 0, 1], local: [0, 1.2, 2.9] };
  a.out = [{ k: "sh", w: "main", p: [0, 32, -96], v: [0, 0, 800] }, claim];
  a.state(la, "tiger", pa); b.state(lb, "sherman", pb);
  await b.until(() => b.events.some(e => e.k === "sh" && e.o === sa[0]), "Alice's shot relayed to Bob");
  await a.until(() => a.unit(sb[0])[6] < hp0, "damage applied to Bob");
  // the result is reported back to both crews
  await a.until(() => a.events.some(e => e.k === "ui" && e.to === a.id && e.m === "hit"), "hit result for Alice");
  await b.until(() => b.events.some(e => e.k === "ui" && e.to === b.id && e.m === "ph"), "'you were hit' for Bob");

  // keep shooting until he's destroyed (88 mm vs Sherman front, a few rounds)
  for (let i = 0; i < 12 && a.unit(sb[0])[3] & 1; i++) {
    a.out = [claim]; a.state(la, "tiger", pa); b.state(lb, "sherman", pb);
    await new Promise(r => setTimeout(r, 120));
  }
  const kill = await b.until(() => b.events.find(e => e.k === "kill" && e.v === sb[0]), "kill event");
  assert.equal(kill.by, sa[0]);
  await a.until(() => a.seat()[21] >= 1, "kill credited to Alice");

  // Bob leaves: a bot takes his seat back
  b.close();
  await a.until(() => { const u = a.unit(sb[0]); return u && !(u[3] & 32) && u[31] !== "Bob b"; }, "bot back in Bob's seat");
  await a.until(() => a.events.some(e => e.k === "msg" && /Bob b left/.test(e.text)), "leave message");
  a.close();
});

test("private rooms are hidden from the list but can be joined by code; bad input is ignored", { timeout: 30000 }, async () => {
  const a = new Client("Host"), b = new Client("Guest");
  await a.hello(); await b.hello();
  a.send({ t: "create", name: "Secret", priv: true, team: 1 });
  const { code } = await a.msg("joined");
  b.send({ t: "list" });
  const list = await b.msg("rooms");
  assert.ok(!list.rooms.some(r => r.code === code));
  a.ws.send("not json"); a.ws.send(JSON.stringify({ t: "in", d: { st: ["x"], e: [{ k: "spawn", ty: "__proto__" }, { k: "hit", p: "nope" }, null] } }));
  b.send({ t: "join", code: "ZZZZZ" });
  assert.match((await b.msg("error")).msg, /No room/);
  b.send({ t: "join", code, team: 1 });
  await b.msg("joined");
  const sa = await a.until(() => a.seat(), "host seat"), sb = await b.until(() => b.seat(), "guest seat");
  assert.equal(sa[2], 1); assert.equal(sb[2], 1, "team preference is honoured");
  a.close(); b.close();
});
