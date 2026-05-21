<div align="center">

# 🏭 FS25 Fertilizer Depot
### *Buy, Store & Sell Fertilizer — Your Way*

[![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_FertilizerDepot/total?style=for-the-badge&logo=github&color=4caf50&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/releases)
[![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_FertilizerDepot?style=for-the-badge&logo=tag&color=76c442&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/releases/latest)
[![License](https://img.shields.io/badge/license-CC%20BY--NC--ND%204.0-lightgrey?style=for-the-badge&logo=creativecommons&logoColor=white)](https://creativecommons.org/licenses/by-nc-nd/4.0/)
<a href="https://paypal.me/TheCodingDad">
  <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate via PayPal" height="50">
</a>

<br>

> *"Drove two kilometres to buy lime, only to find the shop showing last season's prices. Turned back, did the maths, came back the next morning. The field waited."*

<br>

**Base FS25 sells fertilizer through a static shop menu. This mod puts a building on your farm.**

Walk into the Depot, pick what you need, check the price, and either fill the sprayer parked outside or set a pre-order for collection at the Silo. Prices move with the seasons. Sell surplus back when the market turns. Every litre tracked.

`Singleplayer` • `Multiplayer (server-authoritative)` • `Persistent saves` • `26 languages`

</div>

> [!TIP]
> Want to be part of our community? Share tips, report issues, and chat with other farmers on the **[FS25 Modding Community Discord](https://discord.gg/Th2pnq36)**!

---

## ✨ Features

### 🏗️ Two-Building System

Place both buildings anywhere on your farm — they work together.

| Building | Access | What it does |
|---|---|---|
| **Fertilizer Depot** | Walk inside (5 m trigger) | Purchase dialog, pre-orders, sell-back, admin settings |
| **Fertilizer Silo** | Walk or drive up (5 m trigger) | Collect pre-orders directly into a parked vehicle |

Both appear in the shop under **Production → Factories**.

### 🛒 Purchase Flow

Two ways to get fertilizer into your vehicle:

**Direct fill** — park your sprayer or tanker within 60 m of the Depot, walk inside, select a fill type and amount. If a compatible vehicle is close enough, it fills on the spot.

**Pre-order → Silo collect** — place an order at the Depot with no vehicle required. Drive your sprayer to the Silo building, dismount, walk up, and press **E** to confirm. The mod finds your vehicle nearby and fills it.

```
[Depot — walk inside]             [Silo — drive up, dismount]
  Press E → open dialog              Press E → "Collect X (YL)?"
    Select fill type                   Confirm → vehicle filled
    Set amount
    Vehicle nearby? → fill now
    No vehicle?     → pre-order
```

### 💰 Seasonal Pricing

Fertilizer prices fluctuate across the year. Buy at the right time and save.

| Season | Price modifier |
|---|---|
| 🌱 Spring | +15% — peak demand |
| ☀️ Summer | ±0% — baseline |
| 🍂 Autumn | −10% — post-season dip |
| ❄️ Winter | −15% — lowest prices |

Seasonal pricing can be toggled off in the admin settings panel.

### 🔄 Sell-Back

Sell excess fertilizer back from a vehicle parked at the Depot's unload zone at **80% of the current buy price** (configurable). Drive into the zone, dismount, and press **E**.

### 📦 Per-Type Storage

The Depot holds up to **50,000 L per fill type** — configurable by an admin up to 500,000 L. Storage persists in the savegame. Buy in bulk during winter, draw down through spring.

### 🌿 FS25_SoilFertilizer Integration

When [FS25_SoilFertilizer](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer) is installed, 25+ specialist products become available in the Depot dialog:

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
1. Place the Fertilizer Depot building on your farm (Production → Factories)
2. Place the Fertilizer Silo nearby
3. Walk into the Depot — press E to open the purchase dialog
4. Select a fill type and set an amount
5. Vehicle parked within 60 m? → fills immediately
6. No vehicle? → place a pre-order, drive your sprayer to the Silo,
   dismount, walk up, press E to collect
7. Sell surplus: drive into the Depot unload zone, dismount, press E
8. Adjust prices and capacity: press Shift+D anywhere
```

> [!TIP]
> Buy in winter (−15%) and store it. Draw down through spring when prices peak. The Depot's per-type storage makes this effortless — watch the capacity bar in the dialog and stock up when it's cheap.

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
| **FS25_SoilFertilizer** | Full integration — 25+ specialist fill types unlocked automatically |
| **Courseplay / AutoDrive** | Compatible — no known conflicts |
| **Precision Farming DLC** | Compatible |
| **Multiplayer** | Fully supported — all transactions server-authoritative |
| **Console** | Not tested |

---

## ⚠️ Known Limitations

| Issue | Details |
|---|---|
| 🚜 **Vehicle search radius** | The mod searches for a vehicle within 60 m of the Silo, Depot, and unload node. Vehicles parked further away will not be found — move closer and try again. |
| 🌐 **Multiplayer settings sync** | Settings are pushed to all clients on change. Clients who join mid-session may need to reconnect if settings appear stale. |
| 🏗️ **Save compatibility** | Upgrading from a significantly older version may require removing and re-placing buildings if save data is incompatible. Check the release notes before upgrading. |

---

## 🤝 Contributing

Found a bug? [Open an issue](https://github.com/TheCodingDad-TisonK/FS25_FertilizerDepot/issues/new/choose) — the template will guide you through what to include.

Want to contribute code? PRs are welcome on the `development` branch. See `CLAUDE.md` in the repo root for architecture notes and coding conventions.

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

**Author:** TisonK &nbsp;·&nbsp; **Version:** 1.0.0.0

© 2026 TisonK — See [LICENSE](LICENSE) for full terms.

---

<div align="center">

*Farming Simulator 25 is published by GIANTS Software. This is an independent fan creation, not affiliated with or endorsed by GIANTS Software.*

*The depot is open. The silo is waiting.* 🏭

</div>
