// Runs steelfront.html's game script in Node, headless, as the authority for one online room.
// The game checks window.SF_HEADLESS and then skips rendering, audio, particles and the local player;
// everything it still touches in the DOM / WebGL / canvas APIs goes to a do-nothing stub.
import vm from "node:vm";

export function extractScript(html) {
  const m = html.match(/<script>([\s\S]*)<\/script>\s*<\/body>/);
  if (!m) throw new Error("steelfront.html: game <script> not found");
  return m[1];
}

// A value that accepts any property access, assignment, call or `new`, and reads as 0 / "".
function stub() {
  const p = new Proxy(function () {}, {
    get(_, k) {
      if (k === Symbol.toPrimitive) return hint => (hint === "number" ? 0 : "");
      if (k === "then") return undefined; // not a promise
      return p;
    },
    set: () => true,
    apply: () => p,
    construct: () => p,
    has: () => true,
  });
  return p;
}

// Returns the room API exposed by the game (window.steelFrontHost): addPeer, removePeer, input, tick, snapshot, info.
export function createSim(script, seed, extra = {}) {
  const dom = stub();
  const ctx = {
    console, performance, setTimeout, clearTimeout, URL, URLSearchParams,
    document: dom, requestAnimationFrame() {}, addEventListener() {},
    innerWidth: 1280, innerHeight: 720, devicePixelRatio: 1,
    location: { protocol: "about:", search: "", host: "", origin: "", pathname: "" },
    SF_HEADLESS: { seed },
    ...extra,
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  const code = script instanceof vm.Script ? script : new vm.Script(script, { filename: "steelfront.html" });
  code.runInContext(ctx);
  if (!ctx.steelFrontHost) throw new Error("steelfront.html did not start in headless mode");
  return ctx.steelFrontHost;
}
