// One online room: the game simulation runs here, off the main thread, so a busy room (or one that's
// still starting up) never stalls the others or the network.
import { parentPort, workerData } from "node:worker_threads";
import { createSim } from "./headless.js";

const SNAP_INTERVAL = 0.05; // 20 snapshots a second
const sim = createSim(workerData.script, workerData.seed);
parentPort.postMessage({ t: "ready" });

let last = performance.now(), snapAcc = 0;
setInterval(() => {
  const t = performance.now(), dt = Math.min(0.1, (t - last) / 1000);
  last = t;
  sim.tick(dt);
  snapAcc += dt;
  if (snapAcc >= SNAP_INTERVAL) {
    snapAcc %= SNAP_INTERVAL;
    parentPort.postMessage({ t: "snap", json: JSON.stringify(sim.snapshot()) });
  }
}, 1000 / 60);

parentPort.on("message", m => {
  if (m.t === "add") parentPort.postMessage({ t: "added", id: m.id, seat: sim.addPeer(m.id, m.name, m.team) });
  else if (m.t === "remove") sim.removePeer(m.id);
  else if (m.t === "in") sim.input(m.id, m.d);
});
