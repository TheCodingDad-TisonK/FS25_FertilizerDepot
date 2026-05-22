<div align="center">

# 🏭 FS25 Fertilizer Depot
### *Buy, Store, Deliver & Sell Fertilizer — Your Way*

[![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_FertilizerDepot/total?style=for-the-badge&logo=github&color=4caf50&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/releases)
[![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_FertilizerDepot?style=for-the-badge&logo=tag&color=76c442&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/releases/latest)
[![License](https://img.shields.io/badge/license-CC%20BY--NC--ND%204.0-lightgrey?style=for-the-badge&logo=creativecommons&logoColor=white)](https://creativecommons.org/licenses/by-nc-nd/4.0/)
<a href="https://paypal.me/TheCodingDad">
  <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate via PayPal" height="50">
</a>

<br>

> *"Drove two kilometres to buy lime, only to find the shop showing last season's prices. Turned back, did the maths, came back the next morning. The field waited."*

<br>

**Base FS25 sells fertilizer through a static shop menu. This mod puts the whole operation on your farm.**

Walk into the Depot, browse every fill type with live seasonal prices, fill a parked sprayer on the spot or set a pre-order for the Silo. Need a full restock? Place a delivery order and drive to the supplier — the depot stocks itself when you return. Sell surplus back when the market turns. Every litre tracked, every session saved.

`Singleplayer` • `Multiplayer (server-authoritative)` • `Persistent saves` • `26 languages`

</div>

> [!TIP]
> Want to be part of our community? Share tips, report issues, and chat with other farmers on the **[FS25 Modding Community Discord](https://discord.gg/Th2pnq36)**!

---

## ✨ Features at a glance

| Feature | What it does |
|---|---|
| 🏗️ **Two-building system** | Depot (walk-in dialog) + Silo (vehicle drive-up collection) |
| 🛒 **Direct fill** | Park within 60 m, select type & amount, fill immediately |
| 📋 **Pre-order → Silo** | Set order at Depot, collect at Silo with any vehicle |
| 🚚 **Player delivery** | Order a full restock, drive to supplier, haul it back yourself |
| 📦 **Physical products** | Order bags and tanks that spawn at the Depot for pickup |
| 💰 **Seasonal pricing** | Prices shift ±15% across spring/summer/autumn/winter |
| 🔄 **Sell-back** | Return surplus at 80% of current buy price (configurable) |
| 🗺️ **Delivery HUD** | Movable on-screen status panel — drag, resize, saves position |
| ⚙️ **Admin panel** | Shift+D to tune capacity, pricing, sell ratio |
| 🌿 **SoilFertilizer** | Optional integration unlocks 25+ specialist products |

---

## 🏗️ The Buildings

Place both anywhere on your farm — they work together.

| Building | Access | Purpose |
|---|---|---|
| **Fertilizer Depot** | Walk inside (5 m trigger) | Purchase dialog, pre-orders, delivery orders, sell-back, admin settings |
| **Fertilizer Silo** | Walk or drive up | Collect pre-orders directly into a parked vehicle |
| **Supplier Pickup Zone** | Place near in-game shop | Pickup point for player-driven deliveries |

All three appear in the shop under **Production → Factories**.

---

## 🛒 Buying Fertilizer

### Direct fill
Park your sprayer or tanker within 60 m of the Depot, walk inside, open the **BUY** tab, select a fill type and amount. If a compatible vehicle is close enough it fills on the spot.

### Pre-order → Silo collect
No vehicle at the Depot? Set a pre-order in the BUY tab. Drive your sprayer to the Silo, dismount, walk up, and press **E** to confirm. The mod finds your vehicle and fills it.

```
[Depot — walk inside]             [Silo — drive up, dismount]
  Press E → open dialog              Press E → "Collect X (YL)?"
    Select fill type                   Confirm → vehicle filled
    Set amount
    Vehicle nearby? → fill now
    No vehicle?     → set pre-order
```

---

## 🚚 Player-Driven Delivery System

When your depot runs low, skip the shop entirely. The **ORDER tab** lets you place a full restock delivery and drive it yourself.

### How it works

```
1. Walk into Depot → open ORDER tab
2. Click "Place Delivery Order" — cost shown upfront
3. Drive to the Supplier Pickup Zone (place it near the in-game shop)
4. Press E → confirm pickup → money deducted
5. Drive back to your Depot
6. Walk inside → ORDER tab → "Complete Delivery" → all types restocked
```

### Delivery status HUD

Once an order is active, a movable status panel appears on-screen:

- 🟡 **Yellow** — "Drive to the pickup zone to collect your order"
- 🟢 **Green** — "Return to your depot to complete the delivery"

**Right-click** the panel to enter edit mode. Drag it anywhere, resize from any corner, right-click again to save. Position persists per savegame.

> [!NOTE]
> A 10% delivery fee is added to the order total. Cancelling a pending order (before pickup) costs 20% of the delivery value.

---

## 📦 Physical Products

The **PRODUCTS tab** lets you order physical fertilizer bags and tanks that are spawned at the Depot for pickup — useful when you want to stockpile product rather than fill a vehicle directly.

Select a fill type, choose bag or tank, set quantity, and confirm. Products appear at the Depot's spawn marker.

---

## 💰 Seasonal Pricing

Fertilizer prices shift across the year. Buy at the right time and save.

| Season | Price modifier |
|---|---|
| 🌱 Spring | +15% — peak demand |
| ☀️ Summer | ±0% — baseline |
| 🍂 Autumn | −10% — post-season dip |
| ❄️ Winter | −15% — lowest prices |

> [!TIP]
> Stock up in winter at −15% and draw down through spring when prices peak. The per-type storage makes bulk buying effortless — watch the capacity bar and buy when it's cheap.

Seasonal pricing can be toggled off in the admin settings panel.

---

## 🔄 Sell-Back

Sell excess fertilizer back from a vehicle parked at the Depot's unload zone at **80% of the current buy price** (configurable). Drive into the zone, dismount, and press **E**.

---

## 📊 Per-Type Storage

The Depot holds up to **50,000 L per fill type** — configurable by an admin up to 500,000 L. Storage persists across sessions. Stock levels are visible in every tab of the dialog.

---

## 🌿 FS25_SoilFertilizer Integration

When [FS25_SoilFertilizer](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer) is installed, 25+ specialist products become available automatically.

**Liquid nitrogen sources**

| Product | N content | Notes |
|---|---|---|
| UAN-32 | High | Highest N/L of liquid sources |
| UAN-28 | High | Slightly lower concentration |
| Anhydrous Ammonia | Very high | Maximum N concentration |
| Liquid Urea | Medium-high | Dissolved urea for sprayers |
| Liquid AMS | Medium | Liquid ammonium sulphate |
| Starter 10-34-0 | Low N / high P | In-furrow high-P starter |

**Liquid P / K sources**

| Product | Primary benefit |
|---|---|
| Liquid MAP | High P + some N |
| Liquid DAP | High P + some N |
| Liquid Potash | Pure K — dissolved potassium |

**Solid / granular (big bag)**

| Product | Notes |
|---|---|
| Urea | Standard granular N |
| AMS | Ammonium sulphate granular |
| MAP / DAP | Phosphorus-focused granular blends |
| Potash | Pure K granular |
| Gypsum | pH amendment |
| Compost / Biosolids / Chicken Manure / Pelletized Manure | Organic amendments |

**Vanilla fallback** (always available without SoilFertilizer):

`FERTILIZER` · `LIQUIDFERTILIZER` · `LIME` · `MANURE` · `LIQUIDMANURE` · `DIGESTATE`

---

## ⚙️ Admin Settings

Press **`Shift+D`** anywhere in-game (on foot or in a vehicle) to open the admin panel.

> [!NOTE]
> In multiplayer, settings are **admin-only**. Non-admin clients can see the panel but cannot change values. Settings are server-authoritative and synced to all clients.

| Setting | Default | What it does |
|---|---|---|
| **Storage Capacity** | 50,000 L | Per-type storage limit across all Depot buildings |
| **Buy Price Multiplier** | 1.0× | Scale all purchase prices up or down |
| **Sell Ratio** | 80% | Fraction of buy price paid on sell-back |
| **Seasonal Pricing** | On | Toggle spring/summer/autumn/winter price adjustments |

---

## 🎮 Quick Start

```
1. Place the Fertilizer Depot  (Production → Factories)
2. Place the Fertilizer Silo nearby
3. Optionally place the Supplier Pickup Zone near the in-game shop
4. Walk into the Depot — press E to open the dialog

BUY tab:
  → Select fill type, set amount
  → Vehicle within 60 m? Fills immediately
  → No vehicle? Sets a pre-order for the Silo

ORDER tab:
  → "Place Delivery Order" — review cost, confirm
  → Drive to Supplier Pickup Zone, press E to collect
  → Drive back, open dialog, "Complete Delivery"

SELL tab:
  → Drive into the Depot's unload zone, dismount, press E

PRODUCTS tab:
  → Order physical bags / tanks spawned at the Depot

Admin panel (Shift+D):
  → Tune capacity, prices, sell ratio
```

---

## 🛠️ Installation

**1. Download** `FS25_FertilizerDepot.zip` from the [latest release](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/releases/latest).

**2. Copy** the ZIP (do not extract) to your mods folder:

| Platform | Path |
|---|---|
| 🪟 Windows | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\` |
| 🍎 macOS | `~/Library/Application Support/FarmingSimulator2025/mods/` |

**3. Enable** *Fertilizer Depot* in the in-game mod manager.

**4. Place** the Depot and Silo buildings from the shop (Production → Factories).

---

## 🔌 Mod Compatibility

| Mod | Status |
|---|---|
| **FS25_SoilFertilizer** | ✅ Full integration — 25+ specialist fill types unlocked automatically |
| **Courseplay / AutoDrive** | ✅ Compatible — no known conflicts |
| **Precision Farming DLC** | ✅ Compatible |
| **Multiplayer** | ✅ Fully supported — all transactions server-authoritative |
| **Console** | ❓ Not tested |

---

## ⚠️ Known Limitations

| Issue | Details |
|---|---|
| 🚜 **Vehicle search radius** | The mod searches for a vehicle within 60 m of the Silo, Depot, and unload node. Vehicles parked further away will not be found — move closer and try again. |
| 🌐 **Multiplayer settings sync** | Settings are pushed to all clients on change. Clients who join mid-session may see stale values until the next settings change or reconnect. |

---

## 🤝 Contributing

Found a bug? [Open an issue](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/issues/new/choose) — the template will guide you through what to include.

Want to help translate? Open an issue with your language file and we'll include it in the next release. See [issue #20](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/issues/20) for the community translation thread.

Want to contribute code? PRs are welcome on the `development` branch. See `CLAUDE.md` in the repo root for architecture notes and coding conventions.

---

## 🌍 Translations

26 languages supported. Community contributions welcome.

| Language | Status | Contributor |
|---|---|---|
| English | ✅ Native | — |
| Danish | ✅ Native | DJWestDK |
| German, French, Spanish, Italian, Polish, Portuguese, Russian, Ukrainian, Dutch, Norwegian, Swedish, Finnish, Czech, Hungarian, Romanian, Turkish, Japanese, Korean, Chinese (Traditional/Simplified), Indonesian, Vietnamese, Brazilian Portuguese | ✅ EN fallback | Community / AI-assisted |

---

## 📦 Credits

### Fertilizer Silo building model

The **Fertilizer Silo** uses the building model from:

**Multifruit Buying Station** by **82Studio**
Original mod: [FS25_Multifruit_Buying_Station](https://www.farming-simulator.com/mod.php?lang=en&country=us&mod_id=310019)

The `multifruitstation.i3d` model and its textures (`fs25_multifruit_mat_*.dds`) are the work of 82Studio and are redistributed here under their original terms. All credit for the building model goes to 82Studio.

---

## 📝 License

This mod is licensed under **[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)**.

You may share it in its original form with attribution. You may not sell it, modify and redistribute it, or reupload it under a different name or authorship. Contributions via pull request are explicitly permitted and encouraged.

**Author:** TisonK &nbsp;·&nbsp; **Version:** 1.0.3.0

© 2026 TisonK — See [LICENSE](LICENSE) for full terms.

---

<div align="center">

*Farming Simulator 25 is published by GIANTS Software. This is an independent fan creation, not affiliated with or endorsed by GIANTS Software.*

*The depot is open. The silo is waiting.* 🏭

</div>
