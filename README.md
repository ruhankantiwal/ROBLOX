# 🐾 Grow Your Pets: Animal Farm

*The "Mutant Army & Fruits" update. Roblox, launching October 1.*

Hatch an animal army, feed them **Beast Fruits** until they mutate into monsters, defend your farm from zombie waves, run a brainrot conveyor tycoon, and **steal the Dragon Egg** at the end of a giant valley, riding your Alpha pet home while the guardians chase you.

- 📘 **Game Design Document:** [`docs/GDD.md`](docs/GDD.md)
- 🎮 **Game file:** [`build/GrowYourPets.rbxlx`](build/GrowYourPets.rbxlx)

## Put it in your existing Roblox game ("Grow Your Pets Animal Farm")

You need Roblox Studio on a computer (Windows or Mac). Pick **one** of these:

### Option A: replace the game with this build (easiest, 1 minute)
1. Open Roblox Studio, then **File → Open from File** → `GrowYourPets.rbxlx`.
2. **File → Publish to Roblox As…**
3. Pick your existing game **Grow Your Pets Animal Farm**, pick its start place, then press **Overwrite**.
4. Done. Your game now runs this build, with the same name, link and players.

⚠️ This replaces what's currently inside that game. Roblox keeps the old version: *Creator Hub → your game → Places → Version History* lets you restore it any time.

### Option B: keep your old stuff and add this on top
1. In Studio open your game: **Home → Open → My Games → Grow Your Pets Animal Farm**.
2. Also open `GrowYourPets.rbxlx` (**File → Open from File**). Now you have two tabs.
3. In the `GrowYourPets` tab's Explorer, copy these three folders (right-click → Copy), then in your game's tab right-click the same place → **Paste Into**:
   - `ReplicatedStorage` → **Shared**
   - `ServerScriptService` → **Server**
   - `StarterPlayer` → `StarterPlayerScripts` → **Client**
4. In your game tab, click **Workspace** → Properties → tick **StreamingEnabled** (keeps phones from lagging).
5. If your old game already has its own pet, coin/leaderstats, spawn or saving scripts, disable them (right-click → *Disabled*) so they don't fight the new ones.
6. **File → Publish to Roblox** (Alt+P).

The new map builds itself when the game starts. It begins at the centre of the world (0, 0, 0) and runs about 3,300 studs in one direction (+Z), so move any old builds out of the way (or delete them) if they overlap.

## What's in the game

| System | Where |
|---|---|
| Animal Army AI (Tank / Striker / Ranged / Support, commands, surround, focus-fire) | `src/server/Services/PetAIService.luau` |
| Beast Fruits (Blaze, Frost, Volt, Dragon, Ohio) + mastery + awakening | `src/shared/Config/Fruits.luau`, `FruitService`, `CombatService` |
| Visual mutations (every pet and zombie is built from blocks in code) | `src/shared/Art/BlockyBuilder.luau` |
| Build & Kill base waves, walls and turrets, Barn Heart | `ZombieService`, `PlotService` |
| Ride your Alpha + mounted combat | `MountService`, `client/Controllers/MountController.luau` |
| The Long Valley (7 zones, gates, parkour, hidden fruits, dungeon) | `WorldBuilder`, `src/shared/Config/World.luau` |
| Egg Heists (Chicken Coop, Dragon's Nest) + incubator | `EggHeistService`, `CarryService` |
| Conveyor tycoon + Brainrot Extractor + Brainrot Belt + vault stealing | `ConveyorService`, `MutationService` |
| Game passes, products, VIP subscription, odds display, region rules | `MonetizationService`, `src/shared/Config/Monetization.luau` |
| Mobile-first HUD, panels, hatch and mutation cinematics, Clip Mode | `src/client/UI/*`, `client/Controllers/Cinematics.luau` |

## Play it in Studio (no tools needed)

1. Open `build/GrowYourPets.rbxlx` in Roblox Studio.
2. Press **Play**. You spawn on your farm with a Farm Pup. Press **🧟 WAVE**, walk to the hub (up the road) to hatch eggs, and explore the valley.
3. In Studio, every game pass and product is **free to test**: open 🛒 Shop and buy anything.
4. To test saving: *Game Settings → Security → Enable Studio Access to API Services* (the place must be published first).

Test multiplayer (stealing, heists, banners): *Test → Clients and Servers → 2+ players*. Test phones: *Test → Device emulator*.

## Develop with Rojo (recommended for a team)

```bash
rokit install                 # installs Rojo 7.4.4 (see rokit.toml)
rojo serve                    # then connect with the Rojo Studio plugin
# or
rojo build -o build/GrowYourPets.rbxlx
```

Quality gate (the same script CI runs on every push):

```bash
./scripts/check.sh    # type check vs the Roblox API (luau-lsp), headless logic tests, build
```

## Before launch

1. Create the passes, products and subscription in Creator Hub and paste their IDs into `src/shared/Config/Monetization.luau` (`id = 0` means hidden in live servers and free in Studio).
2. Tune numbers in `src/shared/Config/*`. **All** balance lives there: pets, fruits, mutations, eggs, zombies, waves, conveyor, zones, rewards, codes.
3. Follow the checklist in `docs/GDD.md` §16.

## Project layout

```
src/
  shared/   -> ReplicatedStorage.Shared   Config (all tuning), Art (blocky builder, props, stud style), Util, Net
  server/   -> ServerScriptService.Server Main.server + 18 services
  client/   -> StarterPlayerScripts.Client HUD, panels, entity renderer, FX, cinematics, mount, world
tests/      headless Luau logic tests (shims + spec + runner)
docs/GDD.md the design document
```
