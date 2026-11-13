# Steel Front room server

Online rooms for [`steelfront.html`](../steelfront.html). The server hands out the game page and hosts rooms over WebSocket (`/ws`). Each room runs the game's own simulation, headless, in a worker thread. That simulation is the authority for bots, damage, zones, tickets and the end of the battle.

- Players open the server's address in a browser, choose **Online rooms**, then create a room (public or private) or join one by its code. Invite links look like `http://your-server:8080/?room=ABCDE`.
- Each room has 14 seats, 7 per team. Bots fill the empty seats. A joining player takes over a bot's seat, and a bot takes the seat back when they leave. When a battle ends, the next one starts in the same room after 15 s.
- Each browser simulates only its own vehicle, exactly as offline: the same 120 Hz step, flight model and camera. It sends that vehicle to the server 30×/s and draws everyone else from 20 Hz snapshots, played back 0.1 s late so movement stays smooth.
- The shooter's browser traces its own shots. Hits go to the server as claims. The server works out the damage from the shooter's vehicle type and rejects claims where the target isn't roughly where the server has it. This is meant for friends, not hardened against cheaters: a modified client can still lie about its own movement.
- The downloaded or `file://` copy of the game still plays offline. To play online from a downloaded copy, type the server address into the **Online rooms** screen.

## Run it

You need Node.js 20 or newer.

```sh
cd steelfront-server
npm install
npm start            # http://localhost:8080/
```

| Variable | Default | |
| --- | --- | --- |
| `PORT` | `8080` | HTTP + WebSocket port |
| `HOST` | `0.0.0.0` | Interface to listen on |
| `MAX_ROOMS` | `8` | A room uses roughly 10–15 % of one CPU core and ~70 MB of memory |
| `STEELFRONT_HTML` | `../steelfront.html` | Game file to serve and simulate |

`GET /healthz` returns `{ ok, rooms, players }`.

Tests: `npm test`. They start a real server and connect scripted WebSocket players: seats, movement relay, shots, hit claims, kills, leaving, private rooms and bad input. They also check that a browser and the server build the same map from a room's seed.

## Playing over the internet

Players need to reach the server's port. Choose one of these:

- **Your own PC (LAN party or quick test):** run `npm start` and have friends open `http://<your-ip>:8080/`. For friends outside your network, forward TCP port 8080 on your router to your PC. Alternatively, use a tunnel such as `cloudflared tunnel --url http://localhost:8080` or `ngrok http 8080`, and share the `https://` address it prints. WebSockets work through both tunnels.
- **A small VPS (any Linux box with Node 20+):** copy the repository there, then run `npm ci --omit=dev` and `npm start` under systemd or pm2. Open the port in the firewall.
- **Docker** (build from the repository root, so the image includes `steelfront.html`):

  ```sh
  docker build -f steelfront-server/Dockerfile -t steelfront-server .
  docker run -p 8080:8080 steelfront-server
  ```

**HTTPS:** behind a reverse proxy (Caddy, nginx), forward both `/` and `/ws` and allow the WebSocket upgrade. A page loaded over `https://` connects with `wss://` automatically. With Caddy, `caddy reverse-proxy --from game.example.com --to localhost:8080` is enough.

Nothing is hosted publicly by this repository. You have to run the server somewhere yourself.
