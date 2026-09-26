# Silencio — Battery Puzzle (Generator Control Room 3)

Puzzle dua fase untuk menyalakan generator: **kumpulkan baterai** → **rakit panel & engine** →
**tekan tombol**. Semua digerakkan **tag**; tidak perlu menempel script.

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`ENEMY_AI.md`](ENEMY_AI.md) · [`KEY_SYSTEM.md`](KEY_SYSTEM.md) ·
> [`SAFE_ZONE.md`](SAFE_ZONE.md) · [`KNOCK_SYSTEM.md`](KNOCK_SYSTEM.md) ·
> [`DAMAGE_EFFECT.md`](DAMAGE_EFFECT.md) · [`GENERATOR_SFX.md`](GENERATOR_SFX.md)

> **Semua angka & jumlah objek di dokumen ini dibaca langsung dari Studio.**
> Sumber: `ReplicatedStorage.Modules.BatteryPuzzle.Config` + tag `CollectionService`
> pada `Workspace["control room 3"]`.

---

## Letak Objek di Studio

```
Workspace["control room 3"]
├── Batteries/                  ← 4 × Battery (MeshPart)      tag: BatteryPickup
└── Generator/                  (Folder, 5 anak)
    ├── BatteryCase             (Model)                        tag: BatteryCase
    │   └── AA_Battery_low.002_M_AA_Battery_0                  tag: BatterySlot (×4)
    ├── Generator               (Model)
    │   ├── Case                (MeshPart)
    │   │   └── ActiveButton    (Attachment)  ← tombol nyalakan
    │   ├── Panel_01            (MeshPart)   tag: AssemblySlot
    │   ├── Panel_02            (MeshPart)   tag: AssemblySlot
    │   └── Engine              (MeshPart)   tag: AssemblySlot
    ├── Panel_01                (MeshPart)   tag: AssemblyPickup
    ├── Panel_02                (MeshPart)   tag: AssemblyPickup
    └── Engine                  (MeshPart)   tag: AssemblyPickup
```

| Tag | Jumlah di place | Fungsi |
|---|---|---|
| `BatteryPickup` | **4** | Baterai yang bisa diambil pemain |
| `BatterySlot` | **4** | Slot di dalam `BatteryCase` |
| `BatteryCase` | **1** | Wadah baterai pada generator |
| `AssemblyPickup` | **3** | `Panel_01`, `Panel_02`, `Engine` yang bisa dibawa |
| `AssemblySlot` | **3** | Slot target di `Generator.Generator` |

---

## 📐 Arsitektur

```
ServerScriptService/
└── Aer/
    ├── BatteryPuzzleController      ← orchestrator fase baterai
    └── AssemblyController           ← orchestrator fase panel & engine

StarterPlayer/StarterPlayerScripts/
└── Aer/
    └── PuzzleInputClient            ← input client (hint tombol)

ReplicatedStorage/Modules/BatteryPuzzle/   ← 8 modul
├── Config               (12867 b)  ← semua tuning
├── BatteryService       ( 9826 b)  ← ambil / bawa / drop baterai
├── CaseService          ( 9273 b)  ← logika wadah baterai + progres
├── PuzzleService        ( 3414 b)  ← kanal event & broadcast progres
├── AssemblyService      (32828 b)  ← panel & engine: bawa, pasang, drop
├── CarryAnimator        ( 2173 b)  ← animasi carry (kini dikosongkan)
├── HandIK               ( 7134 b)  ← IKControl: tangan menempel attachment
└── ActiveButtonService  ( 4503 b)  ← tombol nyalakan generator
```

---

## Fase 1 — Baterai

1. Pemain mendekat `Battery` (tag `BatteryPickup`) → prompt **"Pick Up"** (jarak 8 stud).
2. Baterai **terbawa di depan dada** (`HandCarryOffset` = `CFrame.new(0, -0.6, -0.4) *
   CFrame.Angles(math.rad(90), 0, 0)`).
   Baterai asli disembunyikan (`HideOriginalWhileCarried`), `CarryVisualScale` = 1.
3. Pemain jalan ke `BatteryCase` → prompt **"Insert"** (jarak 8 stud) di slot `BatterySlot`.
4. `InsertDuration` = **0** → **instan**, tidak perlu menahan tombol.
5. Tiap baterai masuk → Attribute **`BatteryPuzzleProgress`** diperbarui & dibroadcast
   ke semua client (`BroadcastProgress` = true).
6. Semua slot terisi → Attribute **`BatteryPuzzleComplete`** = `true`, dan
   `BindableEvent` **`BatteryPuzzleCompleted`** di dalam case di-fire.

**Attribute pembawa**: **`CarryingBattery`** (Bool) di karakter pemain.

> `PuzzleService.getEvent(case)` mengembalikan BindableEvent `BatteryPuzzleCompleted` —
> itu jalur integrasi kalau sistem lain mau tahu puzzle baterai selesai.

---

## Fase 2 — Panel & Engine

Tiga objek: `Panel_01`, `Panel_02`, `Engine` — masing-masing bisa **dibawa**
(`AssemblyPickup`) dan punya **slot target** (`AssemblySlot`) di `Generator.Generator`.

### Cara membawa

| Objek | Cara bawa | Offset |
|---|---|---|
| **Panel** | **Di atas kepala, rebah** | `CFrame.new(0, 2.55, 0) * CFrame.Angles(math.rad(-90), 0, 0)` |
| **Engine** (solo) | Dibawa di depan | `CFrame.new(0, -0.6, -1.6)` |
| **Engine** (co-op, 2 orang) | Kiri & kanan | `CFrame.new(0.145, -1.266, -3.298) * CFrame.Angles(0, math.rad(90), 0)`<br>`CFrame.new(-0.145, -1.266, -2.958) * CFrame.Angles(0, math.rad(-90), 0)` |

Kecepatan saat membawa: `CarryWalkSpeed` = **8**, pengali `CarryWalkSpeedMultiplier` = 0.9,
`CarryJumpPower` = 30. Engine punya kecepatan sendiri: **solo 8**, **co-op 14**.

**Tangan diangkat lewat IK** — `UseHandIK` = `true`, `UsePanelHandIK` = `true`,
`IKWeight` / `PanelIKWeight` = **1**, `PanelIKType` = `Position`, `IKChainLength` = 2.
Attachment di panel dibaca `HandIK.attachBoth`, sisinya ditentukan dari **posisi X**
(bukan nama), supaya panel yang attachment-nya tertukar tetap benar.

> **Animasi carry dikosongkan** (`PanelCarryAnimId` / `EngineLeftAnimId` / `EngineRightAnimId`
> = `""`) atas permintaan Aer — karakter memakai animasi default Roblox, sementara
> **pose lengan tetap terangkat oleh IK**. Detail: [`ENEMY_AI.md`](ENEMY_AI.md) bagian animasi,
> dan `references/carry-panel.md` di skill internal.

### Memasang & menyalakan

1. Bawa objek ke slot target → pasang. `slotPart.CanCollide = false` supaya tidak menghalangi.
2. Semua terpasang → Attribute **`GeneratorAssembled`** = `true` di generator.
3. Jumlah pembawa Engine dicatat di Attribute **`EngineCarrierCount`**.
4. Tekan tombol **`ActiveButton`** (di `Generator.Generator.Case.ActiveButton`) →
   Attribute **`GeneratorPowered`** = `true`.
5. Daya nyala → SFX & efek listrik generator aktif. Detail: [`GENERATOR_SFX.md`](GENERATOR_SFX.md).

**Attribute pembawa**: **`CarryingAssemblyPart`** (Bool), plus `Kind` & `AssemblyProgress`.

---

## ⌨️ Kontrol

| Aksi | Tombol |
|---|---|
| Ambil objek | `PickupPromptKey` (default E) |
| Masukkan ke slot | `InsertPromptKey` (default E) |
| **Simpan / drop** | **Q** (`Config.StoreKey = Enum.KeyCode.Q`) |

**Drop panel** → jatuh **rebah rata di tanah** (`PanelDropFlat` = true), jarak **3 stud**
di depan pemain (`PanelDropDistance`), celah tanah **0.03** (`PanelDropGroundGap`).
Ketinggian dihitung dari **tebal** panel (`Size.Z`) + raycast ke tanah, jadi tidak tenggelam
dan tidak berdiri seperti tembok.

---

## ⚙️ Konfigurasi Lengkap (`BatteryPuzzle/Config`)

### Carry & gerak

| Config | Default | Arti |
|---|---|---|
| `CarryWalkSpeed` | `8` | WalkSpeed saat membawa |
| `CarryWalkSpeedMultiplier` | `0.9` | Pengali tambahan |
| `CarryJumpPower` | `30` | JumpPower saat membawa |
| `CarryOffset` | `CFrame.new(0, -0.6, -1.6)` | Offset bawa default (relatif `HumanoidRootPart`) |
| `HandCarryOffset` | `CFrame.new(0, -0.6, -0.4) * CFrame.Angles(math.rad(90), 0, 0)` | Offset bawa baterai (dekat dada) |
| `PanelCarryOffset` | `CFrame.new(0, 2.55, 0) * CFrame.Angles(math.rad(-90), 0, 0)` | Offset bawa **panel** (rebah di atas kepala) |
| `EngineLeftCarryOffset` | `CFrame.new(0.145, -1.266, -3.298) * CFrame.Angles(0, math.rad(90), 0)` | Offset Engine co-op — kiri |
| `EngineRightCarryOffset` | `CFrame.new(-0.145, -1.266, -2.958) * CFrame.Angles(0, math.rad(-90), 0)` | Offset Engine co-op — kanan |
| `EngineSoloSpeed` | `8` | WalkSpeed Engine dibawa 1 orang |
| `EngineCoopSpeed` | `14` | WalkSpeed Engine dibawa 2 orang |
| `MaxCarry` | `1` | Maks objek dibawa sekaligus |
| `CarryVisualScale` | `1` | Skala visual objek yang dibawa |
| `HideOriginalWhileCarried` | `true` | Sembunyikan objek asli saat dibawa |
| `RestoreSpeedOnDrop` | `true` | Kembalikan WalkSpeed saat drop |

### Prompt & jarak

| Config | Default |
|---|---|
| `PickupPromptDistance` | `8` |
| `InsertPromptDistance` | `8` |
| `PickupPromptText` | `"Pick Up"` |
| `InsertPromptText` | `"Insert"` |
| `StoreKey` | `Enum.KeyCode.Q` |
| `RequireLineOfSight` | `false` |

### Insert & drop

| Config | Default | Arti |
|---|---|---|
| `InsertDuration` | **`0`** | Detik menahan prompt — **0 = instan** |
| `DropCooldown` | `1.5` | Jeda minimal antar-drop (detik) |
| `DroppedBatteryLifetime` | `0` | Umur baterai yang di-drop (0 = selamanya) |
| `DropOnDamage` | `true` | Drop saat kena damage |
| `CancelInsertOnDamage` | `true` | Insert batal kalau kena damage |
| `CancelInsertOnMove` | `false` | Insert batal kalau bergerak |

### Panel drop

| Config | Default |
|---|---|
| `PanelDropFlat` | `true` |
| `PanelDropDistance` | `3` |
| `PanelDropGroundGap` | `0.03` |

### Keselamatan & return

| Config | Default | Arti |
|---|---|---|
| `ReturnOnDeath` | `true` | Objek balik ke tempat asal saat mati |
| `ReturnOnLeave` | `true` | Balik saat pemain keluar server |
| `ReturnOnRespawn` | `true` | Balik saat respawn |
| `KeepBatteryOnDeath` | `false` | Baterai tetap dipegang saat mati |

### IK & lain-lain

| Config | Default |
|---|---|
| `UseHandIK` / `UsePanelHandIK` | `true` / `true` |
| `IKWeight` / `PanelIKWeight` | `1` / `1` |
| `PanelIKType` | `Enum.IKControlType.Position` |
| `IKChainLength` | `2` |
| `BroadcastProgress` | `true` |
| `Debug` | `false` |

### Tag & attribute

| Config | Nilai |
|---|---|
| `PickupTag` | `"BatteryPickup"` |
| `SlotTag` | `"BatterySlot"` |
| `CaseTag` | `"BatteryCase"` |
| `CarryingAttribute` | `"CarryingBattery"` |
| `ProgressAttribute` | `"BatteryPuzzleProgress"` |
| `CompletedAttribute` | `"BatteryPuzzleComplete"` |

---

## 🔌 Integrasi ke Sistem Lain

| Dari | Ke | Lewat |
|---|---|---|
| `PuzzleService` | sistem lain | `BindableEvent` **`BatteryPuzzleCompleted`** di dalam case |
| `GeneratorSFX` | `ReplicatedStorage` | `BindableEvent` **`HighVoltage`** |
| `GeneratorSFX` | generator | Attribute **`BatteryPuzzleComplete`** pada objek tag `BatteryCase` |
| Klien | server | `RemoteEvent` **`BatteryPuzzleEvent`** di `ReplicatedStorage.Events` |

> `ReplicatedStorage.Events` **dipakai bersama** dengan tim: `TeleportFade` & `JumpscareEvent`
> milik tim, `BatteryPuzzleEvent` milik sistem ini.

---

## 🐛 Jebakan yang Sudah Kena

- **Panel mustahil dibawa tegak.** Tinggi panel 3.58 stud; lengan rig R15 cuma punya reach
  1.803 stud dari sendi bahu. Menegakkan butuh **3.263 stud** → mustahil secara geometri.
  Karena itu panel dibawa **rebah** (diputar −90° di sumbu X).
- **Attachment panel bisa tertukar sisi.** `Panel_02` di place punya Left X=+1.736 /
  Right X=−1.764 (kebalikan). `HandIK.attachBoth` menormalkan dengan mengurutkan
  **berdasarkan posisi X**, bukan nama — jadi tidak perlu rename manual.
- **IK `Type = Transform` bikin pergelangan nekuk.** Pakai **`Position`**: telapak mengikuti
  posisi attachment tanpa dipaksa ikut orientasinya.
- **`BillboardGui.StudsOffsetWorldSpace` dihitung di ruang LOKAL.** Kalau induknya berputar
  (mis. panel yang dibawa), UI ikut miring. Pakai `Attachment` + `WorldCFrame`.
- **Animasi carry gagal load.** Aset animasi di-upload akun **pribadi** padahal game berjalan
  di bawah **grup** → `The experience doesn't have access permission to use asset id ...`.
  Karakter tampak kaku. Solusi: grant izin di Creator Hub, atau kosongkan animasinya.
- **`require` meng-cache modul.** Setelah push perubahan, sesi Play yang sudah jalan masih
  pakai kode lama. Stop dulu, lalu Play ulang.
- **`GetExtentsSize` bukan member `MeshPart`** — hanya ada di `Model`. Untuk panel yang
  `MeshPart`, pakai `.Size`.
