// In-process tests of the room simulation (the game script running headless), no network.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { test } from "node:test";
import { createSim, extractScript } from "../headless.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const script = new vm.Script(extractScript(fs.readFileSync(path.join(here, "..", "..", "steelfront.html"), "utf8")), { filename: "steelfront.html" });
const sim = createSim(script, 4242);
const run = s => { for (let i = 0; i < s * 60; i++) sim.tick(1 / 60); };
const seatOf = id => sim.snapshot().u.find(u => u[4] === id);

test("a browser builds exactly the room server's map from the room seed", () => {
  // load the game the way a browser does (not headless), then regenerate with the room's seed like joining does
  const dom = new Proxy(function () {}, { get: (_, k) => (k === Symbol.toPrimitive ? () => "" : k === "then" ? undefined : dom), set: () => true, apply: () => dom, construct: () => dom, has: () => true });
  const ctx = { console, performance, URL, URLSearchParams, setTimeout, clearTimeout, document: dom, requestAnimationFrame() {}, addEventListener() {}, innerWidth: 1280, innerHeight: 720, devicePixelRatio: 1, location: { protocol: "file:", search: "", host: "", pathname: "" } };
  ctx.window = ctx;
  vm.createContext(ctx);
  script.runInContext(ctx);
  ctx.steelFront.regen(4242);
  const browser = ctx.steelFront.world(), server = sim.world();
  assert.ok(server.buildings.length > 20 && server.trees.length > 300);
  assert.deepEqual(JSON.parse(JSON.stringify(browser)), JSON.parse(JSON.stringify(server)));
});

test("players take over bot seats and give them back", () => {
  const seat = sim.addPeer(1, "Ann", 0);
  assert.equal(seat, 3, "first player on a team gets the middle seat");
  const u = seatOf(1);
  assert.equal(u[31], "Ann"); assert.ok(u[3] & 2, "idle until they deploy");
  for (let i = 0; i < 6; i++) sim.addPeer(10 + i, `P${i}`, 0);
  assert.equal(sim.addPeer(20, "Overflow", 0) >= 7, true, "a full team sends the next player to the other side");
  for (let i = 0; i < 6; i++) sim.removePeer(10 + i);
  sim.removePeer(20);
  run(0.1);
  assert.equal(sim.snapshot().u.filter(u => u[3] & 32).length, 1);
});

test("hit claims: damage comes from the shooter's weapon and implausible claims are dropped", () => {
  sim.addPeer(2, "Ben", 1);
  const a = seatOf(1), b = seatOf(2);
  const st = (life, ty, pos) => [sim.info().time + 1000, life, 1, ...pos, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, ty];
  sim.input(1, { e: [{ k: "spawn", ty: "tiger", life: a[5] + 1 }], st: st(a[5] + 1, "tiger", [0, 30, -100]) });
  sim.input(2, { e: [{ k: "spawn", ty: "sherman", life: b[5] + 1 }], st: st(b[5] + 1, "sherman", [0, 30, -60]) });
  run(0.3);
  const target = sim.tanks[b[0]];
  assert.ok(target.alive && Math.abs(target.pos[2] + 60) < 1, "Ben is where his browser put him");
  const claim = { k: "hit", w: "main", st: [0, 32, -96], p: [0, 31, -62.9], kind: "tank", tg: b[0], part: "hull", axis: 2, sign: 1, dir: [0, 0, 1], local: [0, 1.2, 2.9] };

  const hp = target.hp;
  sim.input(1, { e: [{ ...claim, p: [300, 31, 300] }] }); // nowhere near Ben
  sim.input(1, { e: [{ ...claim, w: "rkt" }] }); // a Tiger has no rockets
  sim.input(1, { e: [{ ...claim, tg: a[0] }] }); // can't hit yourself
  assert.equal(target.hp, hp);

  sim.input(1, { e: [claim] });
  assert.ok(target.hp < hp, "88 mm front-hull hit penetrates a Sherman");
  const ev = sim.snapshot().e;
  assert.ok(ev.some(e => e.k === "ui" && e.to === 1 && e.m === "hit"));
  assert.ok(ev.some(e => e.k === "ui" && e.to === 2 && e.m === "ph"));

  // dead players can't respawn instantly
  for (let i = 0; i < 10 && target.alive; i++) sim.input(1, { e: [claim] });
  assert.equal(target.alive, false);
  sim.input(2, { e: [{ k: "spawn", ty: "sherman", life: target.life + 1 }] });
  assert.equal(target.alive, false, "respawn before the timer is refused");
  run(5.5);
  sim.input(2, { e: [{ k: "spawn", ty: "sherman", life: target.life + 1 }] });
  assert.equal(target.alive, true);
});
