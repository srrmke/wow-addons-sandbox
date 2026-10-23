# WoW Addon Sandbox

A browser sandbox that runs World of Warcraft addons (Lua and XML) and renders their frames live, so you can see an addon's UI without launching the game. It reloads when you save files, and has a console, event firing, mock player data, slash commands and a frame inspector.

```
npm install
npm run dev      # open the printed URL (Chrome/Edge recommended)
```

Click **Open folder…** (or drop a folder on the page) and choose an addon folder (contains `<Name>.toc`) or a whole `AddOns` folder. In Chromium the folder is watched, so saving a `.lua`/`.xml`/`.toc` file reloads the addon.

## What is emulated
- TOC parsing, load order, dependencies, `SavedVariables` (kept in localStorage), `local addonName, ns = ...`
- Lua 5.4 (wasmoon) with Lua 5.1 shims: `unpack`, `setfenv/getfenv`, `bit`, `strsplit`, `tinsert`, `hooksecurefunc`, `Mixin`, …
- Frames: Frame, Button, CheckButton, EditBox, Slider, StatusBar, ScrollFrame, GameTooltip, ScrollingMessageFrame; Texture, FontString, fonts, backdrops, anchors, strata/levels, scripts/events, `OnUpdate`, `C_Timer`, animation groups (Alpha/Translation/Scale), dragging
- XML templates (`virtual`, `inherits`, `parentKey`, `$parent`, `mixin`), common built-in templates (UIPanelButton, BasicFrame, UICheckButton, OptionsSlider, InputBox, scroll frames, …)
- Mock game world (player/target units, combat, modifier keys), slash commands (`/run`, `/dump`, `/reload`, `SlashCmdList`), event firing panel, frame inspector

## Known limits
- Blizzard art isn't shipped: known `Interface\` paths get a stylised stand-in, unknown ones a labelled placeholder. PNG/JPG/TGA files inside your addon render for real; BLP does not.
- Lua 5.4 prints `5.0` for float results when concatenated with `..` (`print`, `tostring` and `string.format` are patched).
- Unimplemented widget methods log a one-time warning and no-op. No secure templates, models, cooldowns, minimap, or dropdown menus yet.
