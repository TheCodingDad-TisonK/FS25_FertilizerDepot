## What Does This PR Do?

<!-- One paragraph summary. What changed and why? -->

## Related Issue

<!-- Closes #, Fixes #, or "no issue" -->

## Type of Change

- [ ] Bug fix
- [ ] New feature (fill type, UI, flow change)
- [ ] Refactor / code quality
- [ ] Documentation / translations
- [ ] Build / tooling

## How Was This Tested?

- [ ] Singleplayer — placed Depot and Silo, tested purchase and Silo collect flow, no errors in log.txt
- [ ] Multiplayer — tested as host and/or client

<!-- Describe what specifically you tested and any edge cases you checked -->

## Checklist

- [ ] I read `CLAUDE.md` before writing code
- [ ] I targeted the `development` branch (not `main`)
- [ ] My change touches only what it needs to — no unrelated edits
- [ ] If I added a translation key: it is present in all 26 `translations/translation_XX.xml` files
- [ ] If I added a network event: `InitEventClass` is called and `emptyNew` / `readStream` / `writeStream` are all implemented
- [ ] If I changed vehicle fill logic: tested with both a self-propelled sprayer and a trailed tanker
- [ ] No `goto` / `continue` / `os.time()` — FS25 is Lua 5.1
- [ ] No `onClose` XML callback name — use `fdOnClose` or similar to avoid lifecycle stack overflow

## Screenshots / Log Output (if relevant)

<!-- Paste a [FertDepot] log excerpt or screenshot if this fixes a visible bug or changes UI -->
