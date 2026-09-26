# Silencio — The Dark Story

Game horror co-op escape di karnaval terbengkalai, dibuat dengan Roblox Studio.

| Sistem | Dokumen |
|---|---|
| **Enemy AI** — NPC monster: patrol, chase, attack, animasi | [`ENEMY_AI.md`](ENEMY_AI.md) |
| **Key System** — kunci → pintu → power switch → lampu | [`KEY_SYSTEM.md`](KEY_SYSTEM.md) |
| **Safe Zone** — bilik aman berbatas napas (toilet/lemari) | [`SAFE_ZONE.md`](SAFE_ZONE.md) |
| **Knock & Revive** — pemain tumbang, merangkak, dibangunkan rekan | _(bagian di bawah)_ |
| **Battery Puzzle** — rakit baterai + panel generator untuk nyalakan daya | _(bagian di bawah)_ |

---

## ⚠️ Struktur di Studio (fakta per 23 Sep 2026)

Sistem kita dikelompokkan dalam folder **`Aer`**, terpisah dari punya tim:

```
ServerScriptService/
├── SilencioServer/     ← MILIK TIM (framework + manager)
├── Feature/            ← MILIK TIM (TeleprotHandler)
└── Aer/                ← MILIK KITA
    ├── EnemyController
    ├── KeySystemController
    ├── SafeZoneController
    ├── KnockController
    ├── BatteryPuzzleController
    ├── AssemblyController
    └── GeneratorSFXController

StarterPlayer/
├── StarterPlayerScripts/
│   ├── SilencioClient/   ← MILIK TIM (LocalScript + 9 modul)
│   ├── Boba/             ← MILIK TIM (Teleport)
│   └── Aer/              ← MILIK KITA
│       ├── KnockUI
│       ├── RevivePromptFilter
│       ├── PuzzleInputClient
│       ├── SafeZoneUI
│       └── JumpscareHandler
└── StarterCharacterScripts/
    └── DamageEffect      ← MILIK KITA

ReplicatedStorage/Modules/    ← modul KITA
├── EnemyController/   (10 modul)
├── KeySystem/         (8 modul)
├── SafeZone/          (11 modul)
├── KnockSystem/       (8 modul)
├── BatteryPuzzle/     (8 modul)
├── GeneratorSFX / GeneratorElectricFX / CustomPromptHelper / TeleportData
```

> **Catatan penting — repo git ini belum sepenuhnya sinkron dengan Studio, dan drift-nya
> DUA ARAH.** Beberapa file di Studio lebih baru dari repo, beberapa justru sebaliknya.
> **Kalau ragu, baca `Source` dari Studio lewat MCP dulu** — jangan asumsikan salah satu
> sisi paling benar.
>
> | Arah | File | Yang berbeda |
> |---|---|---|
> | **Studio lebih baru** | `DamageEffect` | fitur `UiDikejar` + ambang `65/25/12` (repo masih `22/13/8`) |
> | | `BatteryService` | fallback `defaultWalkSpeed` / `Movement.WalkSpeed` |
> | | `CaseService` | fallback lintas-modul + `registerCase` |
> | | `AssemblyService` | `AssemblyService.insert`, slot `CanCollide = false`, prompt hold `0` |
> | | `ActiveButtonService` | `ActiveButtonService.activate`, prompt hold `0` |
> | | `ZoneService` | `ZoneService:triggerZone` (dipakai CustomPromptController) |
> | | `EnemyController/Config` | `ChaseSpeed 20`, `DetectionRadius 95`, `FieldOfView 360`, dll |
> | | `BatteryPuzzle/Config` | `InsertDuration 0` (repo masih `1.0`) |
> | **Repo lebih baru** | `EnemyController` | print diagnostik + komentar (Studio sudah dibersihkan) |
> | | `TargetFinder` | cek Attribute `Knocked` — **monster mengabaikan pemain tumbang** |
>
> **Konsekuensi gameplay dari yang terakhir:** karena cek `Knocked` hanya ada di repo,
> di Studio monster **masih mengejar pemain yang tumbang**. Kalau perilaku "abaikan yang
> tumbang" memang diinginkan, versi repo perlu didorong ke Studio.

---

## Cara Pakai

Sistem digerakkan **tag** + **Attribute**. Kamu **tidak perlu menempel script** ke objek apa pun.

1. Buka **View → Tag Editor**
2. Pilih objek di Explorer
3. Tempel tag sesuai tabel di bawah
4. **Play**

Objek yang di-tag saat game sedang jalan juga langsung ikut terdaftar.

### Enemy AI

Tempel **`Monster`** pada Model NPC. Selesai — patrol, chase, attack, dan animasi jalan otomatis.

Syarat Model: punya `Humanoid` + `HumanoidRootPart`, dan `Health` > 0.

Untuk NPC **mesh tunggal** (satu Model saja), cukup tag `Monster` langsung — `MonsterRig`
otomatis bikin proxy `HumanoidRootPart` dan menjadikan mesh sebagai visual.
→ [`ENEMY_AI.md`](ENEMY_AI.md)

**Banyak monster:** satu player hanya dikejar **satu** monster (target eksklusif, aktif secara
default). Monster lain mencari korban lain; kalau kehabisan korban, mereka tetap patroli.
Bos yang harus selalu mengejar: Attribute `ShareTarget = true`.

### Key System

Tempel keempat tag ini, lalu Play — tanpa mengisi Attribute apa pun sudah nyambung jadi satu
rantai puzzle (semua id default `"control_room"`):

`KeyPickup` → `LockedDoor` → `PowerSwitch` → `CarnivalLight`

→ Atribut, multi-puzzle, master key: [`KEY_SYSTEM.md`](KEY_SYSTEM.md)

### Safe Zone

Tempel **`SafeZone`** pada Part bilik toilet, lalu putar Part-nya supaya muka depannya = arah pintu.
Pemain menekan **E** untuk **sembunyi** di dalam: kamera jadi mengintip dari balik pintu, monster
tidak bisa menarget **dan tidak bisa masuk** — tapi cuma **20 detik**, kapasitas **1 orang**. Napas
habis → pemain **dikeluarkan paksa**, bilik hangus 15 detik. Bar napas muncul otomatis.

Aman selamanya tanpa prompt (perilaku lama): Attribute `NoBreath = true` + `TouchToEnter = true`.

Safe Zone juga terintegrasi dengan FPP tim — saat masuk bilik, kamera FPP & HUD gameplay
dimatikan sementara, lalu dipulihkan saat keluar.

→ Siklus bilik, Attribute, titik presisi: [`SAFE_ZONE.md`](SAFE_ZONE.md)

### Knock & Revive (co-op down state)

Tidak perlu tag apa pun — **otomatis aktif untuk semua pemain**. Monster ber-tag `Monster`
yang menyerang (lewat `AISignal` event `Attack`) akan **menumbangkan** pemain, bukan langsung membunuh.

Alur pemain tumbang (Attribute **`Knocked`** = true):

1. Pemain **merangkak** (`CrawlSpeed` = 6, animasi `2506281703`, jump dimatikan) selama
   **bleed-out 30 detik**. Tool yang dipegang di-drop (`DropTools`).
2. Rekan berdiri di dekatnya (≤ `ReviveDistance` 9 stud) dan **tahan tombol E 5 detik**
   (`ReviveHoldTime`) untuk revive. Prompt berbunyi **"Revive"**.
3. Revive selesai → pemain bangun dengan **`ReviveHealth` = 50**.
4. Kalau bleed-out habis → pemain **mati beneran**.
5. Sisa waktu ≤ `BleedOutWarningTime` (10 detik) → sinyal `WARNING` dikirim ke tim.

State dibaca dari Attribute karakter: **`Knocked`** (Bool), **`KnockBleedOut`** (Number, detik
sisa), **`KnockReviveProgress`** (Number, 0..1). Sinyal antar-modul lewat BindableEvent
**`KnockSignal`**: `DOWNED` / `REVIVED` / `BLEED_OUT` / `WARNING`.

| Aturan | Nilai | Arti |
|---|---|---|
| `KnockOnlyFromMonster` | `true` | Knock hanya dari monster, bukan damage lain |
| `DownedCannotRevive` | `true` | Pemain tumbang tidak bisa revive rekan |
| `CancelReviveOnDamage` | `true` | Revive batal kalau yang merevive kena damage |
| `MonsterHitWindow` | 2 detik | Jendela waktu setelah `Attack` dianggap sah |
| `ReviveBreakDistance` | 13 stud | Jarak yang membatalkan revive |

> **Penting untuk tim:** monster **wajib punya `AISignal`** di dalam Model-nya (otomatis dibuat
> core AI kalau tidak ada). Kalau Model tidak punya, atau script NPC tidak meng-emit `Attack`,
> pemain **tidak akan tumbang** — hanya kena damage biasa.

### Battery Puzzle (generator Control Room 3)

Rantai: **Battery** + **Panel & Engine** → **Generator** → **daya nyala**. Dua fase:

**Fase 1 — Baterai** — di `Workspace["control room 3"].Batteries` + `.Generator.BatteryCase`:

| Objek | Tag | Jumlah di place |
|---|---|---|
| `Battery` (MeshPart) | `BatteryPickup` | **4** |
| slot di `BatteryCase` | `BatterySlot` | **4** |
| `BatteryCase` (Model) | `BatteryCase` | **1** |

- Pemain ambil `Battery` (walk carry, offset `HandCarryOffset`, `CarryWalkSpeed` = 8).
- Bawa ke `BatteryCase` → masukkan ke slot (`Insert`). Prompt jarak 8 stud.
- `InsertDuration` = **0** (instan — prompt tidak perlu ditahan).
- Progres disimpan di Attribute **`BatteryPuzzleProgress`**; selesai → **`BatteryPuzzleComplete`**.
- Attribute pembawa: **`CarryingBattery`**.

**Fase 2 — Panel & Engine** — di `Workspace["control room 3"].Generator`:

| Objek | Tag `AssemblyPickup` (bisa dibawa) | Tag `AssemblySlot` (target) |
|---|---|---|
| `Panel_01` | ✔ | ✔ (di `Generator.Generator.Panel_01`) |
| `Panel_02` | ✔ | ✔ (di `Generator.Generator.Panel_02`) |
| `Engine` | ✔ | ✔ (di `Generator.Generator.Engine`) |

- Pemain **bawa di atas kepala** — `PanelCarryOffset` Y = **2.55** (rebah), tangan diangkat
  lewat IK (`UsePanelHandIK` = `true`, `PanelIKWeight` = 1).
- `CarryWalkSpeed` = **8**; Engine punya kecepatan sendiri: solo **8**, co-op **14**.
- Dipasang ke slot → Attribute **`GeneratorAssembled`** = true. Jumlah pembawa Engine dicatat di
  **`EngineCarrierCount`**.
- Tekan tombol **`ActiveButton`** (di `Generator.Generator.Case.ActiveButton`) →
  **`GeneratorPowered`** = true → lampu & SFX generator nyala.
- Store pakai **Q** (`StoreKey`) → objek **jatuh rebah rata di tanah** (`PanelDropFlat` = true,
  jarak 3 stud, celah tanah 0.03).
- Attribute pembawa: **`CarryingAssemblyPart`**, `Kind`, `AssemblyProgress`.

Fitur keselamatan: `ReturnOnDeath` / `ReturnOnLeave` / `ReturnOnRespawn` (baterai balik ke
tempat asal), `DropOnDamage`, `DropCooldown` 1.5 s, `CancelInsertOnDamage`.

### DamageEffect — efek horor saat dikejar (client)

`StarterCharacterScripts/DamageEffect` (LocalScript) — **aktif otomatis**, tidak perlu tag.
Monster dicari lewat tag `Monster` (CollectionService), jadi mendukung banyak monster;
yang terdekat & masih hidup yang mengendalikan efek. Jarak dihitung adaptif
(`effectiveDistance`) supaya monster raksasa (mis. Clown) tetap bisa mencapai intensitas penuh.

| Efek | Ambang | Detail |
|---|---|---|
| Bayangan & getar mulai terasa | `START_DIST` = **65** stud | Vignette 4-sisi + guncangan kamera halus |
| **`UiDikejar`** — overlay dikejar | ikut `START_DIST` | ScreenGui `UiDikejar` dengan `IgnoreGuiInset` (aman HP/mobile); Background 0.85, dengung 0.5, "bcak" 0.5 saat intensitas penuh |
| Denyut jantung | `PULSE_DIST` = **25** stud | Vignette berdenyut seirama detak |
| Penglihatan mengabur | `BLUR_DIST` = **12** stud | `Lighting.BlurEffect` (maks `MAX_BLUR` = 10) |

Konstanta lain: `MAX_SHAKE` 0.11 rad, `SHAKE_SPEED` 11, `MAX_VIGNETTE` 0.82,
`SCAN_INTERVAL` 0.1 s (scan monster 10×/detik). Semua pakai `math.noise` — tanpa gambar eksternal.

---

## Daftar Tag

| Tag | Sistem | Ditempel pada |
|---|---|---|
| `Monster` | Enemy AI | Model NPC (rig ber-`Humanoid`) |
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

Attribute yang paling sering dipakai:

| Attribute | Pada | Fungsi singkat |
|---|---|---|
| `ChaseMode` | Model `Monster` | `NEAREST` (default) / `PERSISTENT` / `ITEM_HOLDER` |
| `ShareTarget` | Model `Monster` | Bebas dari aturan "satu monster satu korban" |
| `MonsterBait` | `Tool` apa pun | Pembawanya diprioritaskan monster mode `ITEM_HOLDER` |
| `NoAutoAnimations` | Model `Monster` | Animasi diurus script NPC sendiri (lihat `AISignal`) |
| `BreathTime` | Part `SafeZone` | Lama bilik melindungi, detik (default 20) |
| `TouchToEnter` | Part `SafeZone` | Masuk cukup berdiri di dalam, tanpa prompt & kamera intip |
| `NoBreath` | Part `SafeZone` | Bilik aman selamanya (tanpa timer napas) |
| `KeyId` | Objek `KeyPickup` | Id kunci; harus cocok dengan `RequiredKey` pintu |
| `Knocked` | Character pemain | (read) Bool: sedang tumbang |
| `KnockBleedOut` | Character pemain | (read) Number: sisa detik bleed-out |
| `KnockReviveProgress` | Character pemain | (read) Number: progres revive 0..1 |
| `AIState` | Model `Monster` | (read) `IDLE`/`PATROL`/`CHASING`/`ATTACKING`/`DEAD` |
| `GeneratorAssembled` | Generator | (read) Bool: panel & engine terpasang |
| `GeneratorPowered` | Generator | (read) Bool: daya sudah nyala |

---

## Catatan untuk Tim

- **Script di Studio yang TIDAK ada di folder `src/` repo ini = milik tim** (framework
  `SilencioHoror`, `SilencioServer`, `SilencioClient`, `Boba/Teleport`, teleport, pipe puzzle,
  prompt billboard, HUD). Sistem kita berdiri sendiri; **jangan saling ubah tanpa koordinasi**.
- `ReplicatedStorage.Events` dipakai bersama: `TeleportFade` & `JumpscareEvent` milik tim,
  `BatteryPuzzleEvent` milik kita. `ReplicatedStorage.Remotes` (GateCinematic*) dikelola tim.
- **`WalkSpeed` di-reset ke 12 oleh `PlayerManager` tim setiap karakter spawn.** Sistem carry
  (8) dan crawl knock (6) menyetel ulang setelah respawn — jangan kaget kalau angkanya beda.
- Sistem kita menyediakan **`SetEnabled(false/true)`** lewat `SilencioClient.CameraController`
  dan `SetAllGameplayUIVisible` lewat `SilencioClient.HUD` yang dipakai Safe Zone untuk
  mematikan FPP + HUD sementara saat pemain mengintip dari bilik.
