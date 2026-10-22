# Nest Heist 🥚

A Roblox steal-and-hatch game. Sneak into guarded nests, grab an egg, outrun the guardian, hatch it at your base, and build a collection of pets that earn coins every second. Other players can net you on the way home, so watch your back. Everything is original: the names, art (built from basic parts), map and code.

## Play it in Roblox Studio

1. Download **`NestHeist.rbxl`** (from the latest build, or build it yourself, see below).
2. Open **Roblox Studio**, then **File → Open from File…** and pick `NestHeist.rbxl`.
3. Press **Play** (F5).

To test stealing with more than one player, use **Test → Clients and Servers**, choose 2 players and press **Start**.

### Saving progress and leaderboards

Progress and the global leaderboards only work in a published game:

1. **File → Publish to Roblox**.
2. **Home → Game Settings → Security → Enable Studio Access to API Services** (only needed for saving while testing in Studio).
3. Keep the server size at **8 players** (the map has 8 nests; the place file already sets this).

Without this the game still runs, shows a short "saving is off" notice, and the leaderboard boards say they'll appear once the game is published.

## How to play

| Action | PC | Mobile / Console |
| --- | --- | --- |
| Grab or steal an egg | Hold **E** | Tap the prompt / ButtonX |
| Dash | **Q** | Dash button / L1 |
| Double jump | **Space** in the air | Jump button in the air |
| Use a tool (Net, Slime) | Equip (1, 2) and click | Equip and tap |
| Menus | Buttons on the left | Same |

**The loop**
1. Cross a bridge to a biome and grab an egg from a nest (new players get a glowing trail to follow).
2. The biome's **guardian** wakes up and chases you. Run (and dash) back to your nest.
3. Walk into your nest: the egg goes into an **incubator** and hatches after a few seconds.
4. Your pet earns coins every second, even while you're offline (50%, up to 3 hours). Your best pet follows you around.
5. Spend coins on **shoes** (more Speed from training), **pen slots** and tools.
6. Gain **Speed** by running laps on the **Training Track** (faster laps give up to 1.6x bonus) or standing on your **Jog Pad** (AFK). More Speed means you can outrun stronger guardians.

**Biomes**

| Biome | Recommended Speed | Guardian | Pets earn |
| --- | --- | --- | --- |
| 🌼 Meadow Hollow | 0 | Bramble Boar | $1 – $50/s |
| 🍬 Candy Cliffs | 300 | Gummy Golem | $40 – $1K/s |
| ⚡ Storm Peaks | 5,000 | Thunderhorn Ram | $800 – $20K/s |
| ⚙️ Clockwork City | 60,000 | Cogwork Sentinel | $16K – $400K/s |
| 🌙 Moonlit Grove | 400,000 | Moonwing Owl | $320K – $8M/s |

Each biome has 5 pets (Common → Legendary): 25 pets in total. Pets roll a **size** (Tiny → Titanic) and sometimes a **mutation** (Glitter x1.5, Diamond x2.5, Starlight x4). There's also an 8% chance of a **lucky hatch** that bumps the egg up one rarity.

**Progression**
- **♻️ Rebirth:** once you have enough coins and Speed (first one: $1M and 5,000 Speed), trade your coins, Speed and shoes for a permanent **+50% income** and **+25% training** per rebirth, plus 25 Feathers. You keep your pets, slots, tools and cosmetics.
- **🧪 Fusion:** three copies of a pet fuse into the next rarity from the same biome (keeping the best size and mutation). Three Legendaries grow one size instead.
- **📖 Pet Index:** see every pet as a 3D card. Discover all 5 pets in a biome for **+10% income forever**.
- **👥 Friends:** every friend on your server adds +10% income (up to +30%).

**Rewards**
- **🎁 Daily rewards:** a 7-day streak of coins, Feathers and boosts. Miss two days and the streak restarts.
- **📜 Daily quests:** 3 new quests every day (hatch eggs, run laps, escape guardians, fuse pets...) plus a bonus for finishing all of them.
- **🎟 Codes:** `NESTHEIST`, `HATCHLING`, `LUCKYEGG`, `ZOOMZOOM`. Add your own in `Config.Codes`.

**Stealing, made fair**
- **Net Launcher** (free): knock the egg off someone carrying one, then grab it.
- **Slime Puddle** (shop): slows down egg carriers who run through it.
- Incubating eggs can be stolen from a nest unless its owner stepped on the **Shield** pad (40 s shield, 90 s recharge).
- Hatched pets can **never** be stolen.
- Tools only affect players carrying an egg, and the **fair-play rule** stops much faster players from robbing much slower ones.
- If your egg is stolen you get **Feathers** 🪶 and a 60 s **Revenge Ping** that highlights the thief. Net them to drop the egg, then grab it back.

**Events and extras**
- **Jackpot Eggs:** every 3 minutes a glowing Epic/Legendary egg with a golden light beam appears somewhere, with 5x mutation luck.
- **Server events** every 7 minutes: 🍀 Lucky Hour, 💰 Coin Rush, ⚡ Speed Frenzy, 🥚 Egg Shower and 😴 Sleepy Guardians.
- **Global leaderboards** in the hub: Most Rebirths, Top Hatchers, Master Thieves and Fastest Laps.
- **Feathers shop:** Lucky Charm and Turbo Laces boosts, glowing trails and **nest themes** that repaint your base.

## Customising

All the balance numbers live in [`src/shared/Config.luau`](src/shared/Config.luau): egg odds, hatch times, pet incomes, speed requirements, guardian speeds, prices, rebirth costs, quests, codes, events and more. The world layout is generated by [`src/shared/MapBuilder.luau`](src/shared/MapBuilder.luau), and pets, eggs and guardians by [`src/shared/Builders.luau`](src/shared/Builders.luau). You can also edit the baked map directly in Studio; the scripts find things by name, so keep part names intact. Sound ids are in [`src/client/Controllers/Sounds.luau`](src/client/Controllers/Sounds.luau) (built-in Roblox sounds; swap in your own audio).

## Building from source

The project uses [Rojo](https://rojo.space) and [Lune](https://lune-org.github.io/docs). Tool versions are pinned in `rokit.toml`.

```bash
rokit install          # installs rojo, lune, selene, stylua, luau-lsp
./scripts/build.sh     # bakes the map (Lune) and builds build/NestHeist.rbxl (Rojo)
./scripts/check.sh     # StyLua, Selene, luau-lsp type check, Lune tests
rojo serve             # optional: live-sync code into Studio with the Rojo plugin
```

```
src/
  shared/   Config, PetLogic and Progression (game math), Format, Rng, Builders, MapBuilder, Remotes
  server/   Main + Services: Data, Player, Plot, Egg, Guardian, Training, Tool, Shop,
            Reward, Progression, Event, Leaderboard, Actions
  client/   Main + Controllers: ClientState, UIKit, HUD, Panels (+ Pages), Reveal, World,
            Input, Followers, Sounds
scripts/    build.sh, check.sh, build-map.luau (bakes Workspace.Map), lib/loader.luau
tests/      logic.spec (game math, config, map), place.spec (built place), remotes.spec (remote contract)
```

## Roadmap

Co-op boss heists, base decoration items, weekly limited events, and Robux items (cosmetics, a 2x coins pass and a season pass).
