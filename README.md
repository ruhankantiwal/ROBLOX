# 🐉 Beast Valley: Mutant Army & Fruits

*Formerly "Grow Your Pets — Animal Farm". Roblox, launching October 1.*

Hatch an animal army, feed them **Beast Fruits** until they mutate into monsters, defend your farm from zombie waves, run a brainrot conveyor tycoon, and **steal the Dragon Egg** at the end of a giant valley, riding your Alpha pet home while the guardians chase you.

- 📘 **Game Design Document:** [`docs/GDD.md`](docs/GDD.md). It covers progression, rarity tiers, the 5 starter fruits, UI layout, monetization, the launch plan, and the step-by-step Pet AI and Fruit Mutation architecture.
- 🎮 **Playable place file:** [`build/BeastValley.rbxlx`](build/BeastValley.rbxlx) (open it in Roblox Studio).

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

1. Open `build/BeastValley.rbxlx` in Roblox Studio.
2. Press **Play**. You spawn on your farm with a Farm Pup. Press **🧟 WAVE**, walk to the hub (up the road) to hatch eggs, and explore the valley.
3. In Studio, every game pass and product is **free to test**: open 🛒 Shop and buy anything.
4. To test saving: *Game Settings → Security → Enable Studio Access to API Services* (the place must be published first).

Test multiplayer (stealing, heists, banners): *Test → Clients and Servers → 2+ players*. Test phones: *Test → Device emulator*.

## Develop with Rojo (recommended for a team)

```bash
rokit install                 # installs Rojo 7.4.4 (see rokit.toml)
rojo serve                    # then connect with the Rojo Studio plugin
# or
rojo build -o build/BeastValley.rbxlx
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
