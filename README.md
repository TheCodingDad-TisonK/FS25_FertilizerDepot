# FS25 Fertilizer Depot

**Version:** 1.0.0.0  
**Author:** TisonK  
**Compatible with:** Farming Simulator 25

---

## Overview

The Fertilizer Depot adds a **two-building system** for managing fertilizer on your farm. Place both buildings to unlock the full experience:

| Building | What it does |
|---|---|
| **Fertilizer Depot** | Walk-in office building. Manage settings, seasonal pricing, storage and sell-back. Press Shift+D anywhere to open settings. |
| **Fertilizer Filling Silo** | Drive up with any trailer or tank. Fills all fertilizer types directly into your vehicle at market price. |

Both buildings appear in the shop under **Production → Factories**.

---

## Features

- **All FS25_SoilFertilizer fill types** — UAN32, POTASH, AMS, MAP, DAP, POLIFOSKA, LIQUIDLIME and 20+ more types, automatically available when SF is installed
- **Vanilla fallback** — works without SoilFertilizer using FERTILIZER, LIQUIDFERTILIZER, LIME, MANURE, LIQUIDMANURE, DIGESTATE
- **Seasonal pricing** — Spring +15%, Summer ±0%, Fall −10%, Winter −15% (toggle in settings)
- **Sell-back** — sell excess fertilizer back at 80% of buy price (configurable)
- **Per-type storage** — 50,000L capacity per fill type in the depot (configurable)
- **Admin settings** — storage capacity, sell ratio, buy multiplier, seasonal toggle (Shift+D)
- **Full multiplayer support** — server-authoritative transactions, admin-only settings

---

## How to Use

1. **Place the Fertilizer Depot** — the building (Farmers Market style). Walk inside for the management dialog.
2. **Place the Fertilizer Filling Silo** — near your fields or on your farm. Drive any compatible trailer or tanker into the pipe zone and it fills automatically.
3. **Adjust settings** with **Shift+D** at any time.

---

## Compatibility

| Mod | Status |
|---|---|
| FS25_SoilFertilizer | Full integration — all 23+ fill types |
| FS25_FarmTablet | Compatible via `g_DepotManager` global |
| Multiplayer | Fully supported |
| Console | Not tested |

---

## Credits

### Fertilizer Filling Silo building
The **Fertilizer Filling Silo** uses the building model from:

**Multifruit Buying Station** by **82Studio**  
Original mod: [FS25_Multifruit_Buying_Station](https://www.farming-simulator.com/mod.php?lang=en&country=us&mod_id=310019)

The i3d model (`multifruitstation.i3d`) and its textures (`fs25_multifruit_mat_*.dds`) are the work of 82Studio and are redistributed here for integration with the Fertilizer Depot system. All credit for the building model and textures goes to 82Studio.

---

## Changelog

### v1.0.0.0
- Initial release
- Two-building system: Fertilizer Depot + Fertilizer Filling Silo
- Seasonal pricing (4 seasons × 4 multipliers)
- Full FS25_SoilFertilizer integration (23+ fill types)
- Multiplayer support with server-authoritative transactions
- Admin settings panel (Shift+D)
