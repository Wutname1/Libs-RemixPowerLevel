### Quick orientation

This repository is a World of Warcraft library/addon called "Lib's - Remix Power Level". It provides UI overlays and tooltip text for two Remix modes (MOP and Legion) and includes an auto-scrapping module.

Key files/dirs to inspect:

- `main.lua` — addon entrypoints: `OnInitialize()` and `OnEnable()`; central logic for tooltips, character screen overlays, LDB object, and options.
- `Modules/Scrapping.lua` — module code for auto-scrapping (feature-specific logic).
- `libs/` — embedded Ace3/Libs dependencies (AceAddon, AceDB, AceConfig, LibDataBroker, LibDBIcon, etc.).
- `Libs-RemixPowerLevel.toc` — addon manifest and file load order (must be kept in sync when adding files).
- `.pkgmeta` — packager metadata (externals, files ignored, package name).

Big picture / architecture

- The addon is an AceAddon-3.0 style module (created with `LibStub('AceAddon-3.0'):NewAddon(...)`). `main.lua` sets up saved vars (AceDB), options (AceConfig/AceConfigDialog), an LDB data source, and hooks into game UI/tooltips.
- Data flow: game API -> aura/currency extraction -> formatted UI output.
  - For Legion Remix the addon calls `C_UnitAuras.GetAuraDataBySpellName(..., 'Infinite Power')` and sums `powerData.points` to compute total power and `points[5]` for versatility/est. Limits Unbound.
  - For MOP Remix the addon reads cloak-related currency totals (currency IDs like `2853 + c[i]`) to compute thread counts.
- UI integration points: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, TooltipProcessor)` for unit tooltips; `hooksecurefunc('PaperDollItemSlotButton_Update', ...)` to add overlays to equipment slots; LDB + LibDBIcon for a minimap button.

Project-specific conventions & patterns

- SavedVariables: the TOC declares `SavedVariables: LibsRemixDB` and the code uses `LibStub('AceDB-3.0'):New('LibsRemixDB', ...)`. Use that exact name when querying stored settings.
- Options: Options table is created in `GetOptions()` and registered with AceConfig and the Blizzard options pane via `Settings.OpenToCategory("Lib's - Remix Power Level")`.
- Debugging: there is an explicit `--@do-not-package@` block in `main.lua` which sets `debug = true`. Be aware these markers affect packaging and are intentionally used to enable local debug logging.
- Optional dependency: `Libs-AddonTools` is optional — if present it registers a logger (`LibAT.Logger.RegisterAddon(...)`). Guard against `nil`.
- Minimap toggle logic: profile stores `minimap.hide`, but the options `get/set` invert that boolean (`get = function() return not profile.minimap.hide end`). When creating UI, preserve that inversion pattern to avoid confusion.
- Strings and IDs: many values are hard-coded (spell names `'Infinite Power'`, `"Timerunner's Advantage"`, currency base `2853`). Search `main.lua` for concrete examples when modifying logic.

Build / packaging notes

- The `.toc` file controls load order in-game and contains the `SavedVariables` declaration — update it when adding new lua/xml files.
- `.pkgmeta` lists externals used by packager tools (WoWAce-style). If you rely on externals, prefer adding them to `.pkgmeta` rather than committing large upstream libraries.
- The `@do-not-package@` and matching `--@end-do-not-package@` markers are used to keep dev-only code out of published builds. Keep those markers intact.

Examples the agent should follow

- To add a tooltip augmentation: add a function similar to `TooltipProcessor(self)` and register it with `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, TooltipProcessor)` as done in `OnEnable()`.
- To add a character screen overlay: follow `UpdateItemSlotButton(button, unit)` which creates `overlayFrame = CreateFrame('FRAME', nil, button)` and attaches FontString fields to that overlay.
- To compute top players: mirror `GetTop10Players()` — iterate group members (`party`/`raid` units), pull aura/currency data, and sort by `LibRTC.dbobj.profile.sortBy`.

Testing / runtime checks

- There are no unit tests in this repo. Fast runtime verification is manual inside WoW client:
  - Load addon, ensure `.toc` and saved variables are correct, toggle options via `/rpl` or the Blizzard AddOn options.
  - Use `Libs-AddonTools` if available to get structured debug logs (the repo already guards logger usage).

Common pitfalls for contributors

- Don’t change the name used for SavedVariables in the TOC or the DB name used in `AceDB:New` — they must match.
- Keep the load order in `.toc` consistent; libraries listed under `# Libraries` must load before `main.lua`.
- When adding files, update `.toc` and the `X-Github`/metadata if packaging.

If anything here is unclear or you want additional examples (small generator for a new module, or a checklist for adding files and updating `.toc`), tell me which part to expand and I will iterate.
