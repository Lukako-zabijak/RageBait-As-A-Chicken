# RageBait As A Chicken

Source-code showcase for the Roblox experience **RageBait As A Chicken**. The repository preserves the original Roblox Studio service hierarchy, and every file is labeled as `(Server)`, `(Client)`, or `(Module)`.

## My contribution

I was responsible for the game's scripting. The models, user interface artwork, map, sounds, animations, and other visual assets were created by other contributors and are not represented as my work here.

## Highlighted systems

| System | What it demonstrates |
| --- | --- |
| [Server bootstrap](ServerScriptService/server_bootstrap%20%28Module%29.luau) | Server lifecycle, rate-limited remote routing, player initialization, cleanup, and shutdown handling |
| [Data service](ServerScriptService/data_service%20%28Module%29.luau) | Persistent profiles, session locking, schema normalization, autosaves, retries, and ordered leaderboards |
| [Monetization service](ServerScriptService/monetization_service%20%28Module%29.luau) | Server-authoritative game passes and retry-safe developer-product receipt processing |
| [Anti-cheat service](ServerScriptService/anti_cheat_service%20%28Module%29.luau) | Server-observed movement checks, violation scoring, and controlled enforcement |
| [Inventory service](ServerScriptService/inventory_service%20%28Module%29.luau) | Authoritative item ownership, equipment validation, tool restoration, and skin handling |
| [Crate service](ServerScriptService/crate_service%20%28Module%29.luau) | Validated purchases, weighted rewards, inventory consumption, and secure result handoff |
| [Reward service](ServerScriptService/reward_service%20%28Module%29.luau) | Server-validated daily and playtime rewards with duplicate-claim prevention |
| [Client bootstrap](ReplicatedStorage/Modules/client_bootstrap%20%28Module%29.luau) | Fault-isolated initialization of camera, UI, inventory, rewards, dialogue, and gameplay controllers |

## Architecture

The server owns persistent data, currency, inventory, rewards, purchases, crates, character state, and anti-cheat decisions. Clients handle input and presentation, while remote requests are validated and rate-limited before reaching the relevant service. Small entry scripts load the larger modules so responsibilities remain separated.

## Third-party code

The Satchel and TopbarPlus packages under `ReplicatedStorage/SatchelLoader` are third-party dependencies and are included only because this is a complete Studio script export. They are not presented as my work.

## Repository scope

This is a source review repository rather than a standalone Rojo project. Non-script Studio instances and visual assets are demonstrated in the separate gameplay showcase.
