# Silencio — The Dark Story

Game horror co-op escape di karnaval terbengkalai, dibuat dengan Roblox Studio.
Kolaborasi **KARIS Studio × OnBlox Studio** · Chapter 1: *The Mask Maze*.

---

## 📚 Daftar Dokumen

Setiap sistem punya dokumennya sendiri — baca yang relevan saja.

| Sistem | Dokumen | Isi singkat | Butuh tag? |
|---|---|---|---|
| **Enemy AI** | [`ENEMY_AI.md`](ENEMY_AI.md) | NPC monster: patrol, chase, attack, animasi (FSM) | `Monster` |
| **Knock & Revive** | [`KNOCK_SYSTEM.md`](KNOCK_SYSTEM.md) | Pemain tumbang, merangkak, dibangunkan rekan | ✗ otomatis |
| **Battery Puzzle** | [`BATTERY_PUZZLE.md`](BATTERY_PUZZLE.md) | Rakit baterai + panel/engine → generator nyala | 5 tag |
| **Key System** | [`KEY_SYSTEM.md`](KEY_SYSTEM.md) | Kunci → pintu → power switch → lampu carnival | 4 tag |
| **Safe Zone** | [`SAFE_ZONE.md`](SAFE_ZONE.md) | Bilik sembunyi berbatas napas | `SafeZone` |
| **DamageEffect** | [`DAMAGE_EFFECT.md`](DAMAGE_EFFECT.md) | Efek horor sinematik saat dikejar monster | ✗ otomatis |
| **Generator SFX** | [`GENERATOR_SFX.md`](GENERATOR_SFX.md) | Suara & efek listrik generator | ✗ otomatis |
| **Aturan kerja** | [`AGENTS.md`](AGENTS.md) | Alur kerja, aturan keamanan, peta struktur | — |
| **Riwayat** | [`PROGRESS.md`](PROGRESS.md) | Log perubahan + commit hash per entri | — |

> Setiap sistem berdiri sendiri dan bisa dimatikan tanpa merusak yang lain.

---

## 🚀 Setup Cepat

Sistem digerakkan **tag** + **Attribute**. Kamu **tidak perlu menempel script** ke objek apa pun.

1. Buka **View → Tag Editor**
2. Pilih objek di Explorer
3. Tempel tag sesuai tabel di bawah
4. **Play**

Objek yang di-tag saat game sedang jalan juga langsung ikut terdaftar.

### Yang butuh tag

| Sistem | Tag yang ditempel | Detail |
|---|---|---|
| **Enemy AI** | **`Monster`** pada Model NPC | Syarat: punya `Humanoid` + `HumanoidRootPart`, `Health` > 0. Untuk NPC mesh tunggal, `MonsterRig` otomatis bikin proxy. → [`ENEMY_AI.md`](ENEMY_AI.md) |
| **Key System** | `KeyPickup` → `LockedDoor` → `PowerSwitch` → `CarnivalLight` | Tanpa mengisi Attribute apa pun sudah nyambung jadi satu rantai puzzle (id default `"control_room"`). → [`KEY_SYSTEM.md`](KEY_SYSTEM.md) |
| **Safe Zone** | **`SafeZone`** pada Part bilik | Putar Part-nya supaya muka depan = arah pintu. Tekan **E** untuk sembunyi: kamera mengintip dari balik pintu, monster tidak bisa menarget **dan tidak bisa masuk** — cuma **20 detik**, kapasitas **1 orang**. → [`SAFE_ZONE.md`](SAFE_ZONE.md) |
| **Battery Puzzle** | `BatteryPickup` (4×), `BatterySlot` (4×), `BatteryCase` (1×), `AssemblyPickup` (3×), `AssemblySlot` (3×) | Di `Workspace["control room 3"]`. → [`BATTERY_PUZZLE.md`](BATTERY_PUZZLE.md) |

### Yang otomatis

- **Knock & Revive** — aktif untuk semua pemain, tanpa tag. → [`KNOCK_SYSTEM.md`](KNOCK_SYSTEM.md)
- **DamageEffect** — aktif saat monster ber-tag `Monster` mendekat. → [`DAMAGE_EFFECT.md`](DAMAGE_EFFECT.md)
- **Generator SFX** — menyala sendiri saat generator dihidupkan. → [`GENERATOR_SFX.md`](GENERATOR_SFX.md)

---

## 🏷️ Daftar Tag Lengkap

| Tag | Sistem | Ditempel pada |
|---|---|---|
| `Monster` | Enemy AI | Model NPC (rig ber-`Humanoid` atau mesh tunggal) |
| `SafeZone` | Safe Zone | Part bilik toilet (tekan E untuk sembunyi, napas 20s, 1 orang) |
| `KeyPickup` | Key System | Kunci yang bisa diambil |
| `LockedDoor` | Key System | Pintu yang butuh kunci |
| `PowerSwitch` | Key System | Tuas/tombol power |
| `CarnivalLight` | Key System | Lampu yang menyala saat power on |
| `BatteryPickup` | Battery Puzzle | `Battery` yang bisa dibawa (4 objek) |
| `BatterySlot` | Battery Puzzle | Slot baterai di dalam `BatteryCase` (4 objek) |
| `BatteryCase` | Battery Puzzle | Wadah baterai pada generator (1 objek) |
| `AssemblyPickup` | Battery Puzzle | `Panel_01/02`, `Engine` yang bisa dibawa (3 objek) |
| `AssemblySlot` | Battery Puzzle | Slot target panel/engine di generator (3 objek) |

> Knock & Revive **tanpa tag** — berlaku ke semua pemain otomatis.

### Attribute yang Paling Sering Dipakai

| Attribute | Pada | Fungsi |
|---|---|---|
| `ChaseMode` | Model `Monster` | `NEAREST` (default) / `PERSISTENT` / `ITEM_HOLDER` |
| `ShareTarget` | Model `Monster` | Bebas dari aturan "satu monster satu korban" |
| `MonsterBait` | `Tool` apa pun | Pembawanya diprioritaskan monster mode `ITEM_HOLDER` |
| `NoAutoAnimations` | Model `Monster` | Animasi diurus script NPC sendiri (via `AIState`/`AISignal`) |
| `BreathTime` | Part `SafeZone` | Lama bilik melindungi, detik (default 20) |
| `TouchToEnter` | Part `SafeZone` | Masuk cukup berdiri di dalam, tanpa prompt & kamera intip |
| `NoBreath` | Part `SafeZone` | Bilik aman selamanya (tanpa timer napas) |
| `KeyId` | Objek `KeyPickup` | Id kunci; harus cocok dengan `RequiredKey` pintu |

Attribute *read-only* lintas sistem: `Knocked`, `KnockBleedOut`, `KnockReviveProgress`
(karakter) · `AIState` (monster) · `GeneratorAssembled`, `GeneratorPowered`,
`BatteryPuzzleProgress`, `BatteryPuzzleComplete` (generator).

---

## 🗂️ Struktur di Studio

Sistem kita dikelompokkan dalam folder **`Aer`**, terpisah dari punya tim:

```
ServerScriptService/
├── SilencioServer/     ← MILIK TIM (framework + manager)
├── Feature/            ← MILIK TIM (TeleprotHandler)
└── Aer/                ← MILIK KITA
    ├── EnemyController            ├── KnockController
    ├── KeySystemController        ├── BatteryPuzzleController
    ├── SafeZoneController         ├── AssemblyController
    └── GeneratorSFXController

StarterPlayer/
├── StarterPlayerScripts/
│   ├── SilencioClient/   ← MILIK TIM (LocalScript + 9 modul)
│   ├── Boba/             ← MILIK TIM (Teleport)
│   └── Aer/              ← MILIK KITA
│       ├── KnockUI              ├── SafeZoneUI
│       ├── RevivePromptFilter   ├── JumpscareHandler
│       └── PuzzleInputClient
└── StarterCharacterScripts/
    └── DamageEffect      ← MILIK KITA

ReplicatedStorage/Modules/    ← modul KITA (5 sistem)
├── EnemyController/   (10 modul)
├── KnockSystem/       ( 8 modul)
├── KeySystem/         ( 8 modul)
├── SafeZone/          (11 modul)
├── BatteryPuzzle/     ( 8 modul)
└── GeneratorSFX / GeneratorElectricFX / CustomPromptHelper / TeleportData
```

---

## ⚠️ Alur Kerja & Drift Repo↔Studio

| | |
|---|---|
| **Repo** | Git repo biasa (branch `main`), remote `origin`. |
| **Sync ke Studio** | **MCP** (`set_script_source`, `execute_luau`). |
| **Rojo** | **TIDAK DIPAKAI lagi.** `default.project.json` = artefak mati. |
| **Playtest** | Manual oleh Aer di Studio. |

### Drift-nya DUA ARAH

Repo dan Studio **belum sepenuhnya sinkron**, dan bukan cuma satu sisi yang lebih baru.
**Kalau ragu, baca `Source` dari Studio lewat MCP dulu** — jangan asumsikan salah satu
sisi paling benar.

| Arah | File | Yang berbeda |
|---|---|---|
| **Studio lebih baru** | `DamageEffect` | fitur `UiDikejar` + ambang `65/25/12` (repo masih `22/13/8`) |
| | `BatteryService` | fallback `defaultWalkSpeed` / `Movement.WalkSpeed` |
| | `CaseService` | fallback lintas-modul + `registerCase` |
| | `AssemblyService` | `AssemblyService.insert`, slot `CanCollide = false`, prompt hold `0` |
| | `ActiveButtonService` | `ActiveButtonService.activate`, prompt hold `0` |
| | `ZoneService` | `ZoneService:triggerZone` (dipakai CustomPromptController) |
| | `EnemyController/Config` | `ChaseSpeed 20`, `DetectionRadius 95`, `FieldOfView 360`, dll |
| | `BatteryPuzzle/Config` | `InsertDuration 0` (repo masih `1.0`) |
| **Repo lebih baru** | `EnemyController` | print diagnostik + komentar (Studio sudah dibersihkan) |
| | `TargetFinder` | cek Attribute `Knocked` — **monster mengabaikan pemain tumbang** |

> **Konsekuensi gameplay:** karena cek `Knocked` hanya ada di repo, di Studio monster
> **masih mengejar pemain yang tumbang**. Kalau perilaku "abaikan yang tumbang" diinginkan,
> versi repo perlu didorong ke Studio.

---

## 🤝 Catatan untuk Tim

- **Script di Studio yang TIDAK ada di folder `src/` repo ini = milik tim** (framework
  `SilencioHoror`, `SilencioServer`, `SilencioClient`, `Boba/Teleport`, pipe puzzle,
  prompt billboard, HUD). Sistem kita berdiri sendiri; **jangan saling ubah tanpa koordinasi**.
- `ReplicatedStorage.Events` **dipakai bersama**: `TeleportFade` & `JumpscareEvent` milik tim,
  `BatteryPuzzleEvent` milik kita. `ReplicatedStorage.Remotes` (GateCinematic*) dikelola tim.
- **`WalkSpeed` di-reset ke 12 oleh `PlayerManager` tim setiap karakter spawn.** Sistem carry
  (8) dan crawl knock (6) menyetel ulang setelah respawn — jangan kaget kalau angkanya beda.
- Sistem kita menyediakan jalur integrasi untuk Safe Zone:
  `SilencioClient.CameraController.SetEnabled` dan `SilencioClient.HUD.SetAllGameplayUIVisible`
  dipakai untuk mematikan FPP + HUD sementara saat pemain mengintip dari bilik.
