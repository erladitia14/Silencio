# Silencio — Enemy AI System

Sistem NPC Enemy AI modular untuk Roblox Studio, pola **Finite State Machine (FSM)**.

**Prinsip desain: versatile.** Tim cukup memberi **tag** (+ Attribute opsional) pada Model NPC —
patrol, chase, idle, damage, dan **animasi** langsung jalan. **Tidak perlu mengubah script AI.**

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`KEY_SYSTEM.md`](KEY_SYSTEM.md).

---

## 📐 Arsitektur

```
ServerScriptService/
├── EnemyController          ← Script utama (orchestrator)
ReplicatedStorage/Modules/
└── EnemyController/         ← Semua module
    ├── Config               ← Default global + resolver override per-NPC
    ├── StateMachine         ← FSM generik & reusable
    ├── SafeZoneManager      ← Jembatan ke sistem Safe Zone (SAFE_ZONE.md)
    ├── TargetFinder         ← Pencarian target (FOV, LOS, range) + jangkauan adaptif
    ├── NavigationManager    ← Pathfinding & navigasi
    ├── CombatManager        ← Serangan, damage, cooldown
    ├── PatrolManager        ← Waypoint patrol system
    ├── TargetClaims         ← Registry "satu monster = satu korban"
    ├── AnimationManager     ← Animasi otomatis via Humanoid (rig)
    ├── SkinBinder           ← Pasangkan rig + mesh visual (pola driver+skin)
    └── SkinAnimator         ← Animasi mesh visual via AnimationController
ServerStorage/
└── NPCAnimationTemplate     ← Contoh untuk tim yang mau animasi berlogika sendiri
```

Key System — sistem terpisah, lihat [`KEY_SYSTEM.md`](KEY_SYSTEM.md).

---

## ⚙️ Setup Cepat

### NPC biasa (satu Model ber-Humanoid)

Beri tag **`Monster`** pada Model (View → Tag Editor). Selesai — AI + animasi jalan otomatis,
termasuk untuk NPC yang di-spawn saat runtime.

Syarat Model: punya `Humanoid` + `HumanoidRootPart`, dan `Health > 0`.

### NPC pola "driver + skin" (mesh import, mis. Mixamo)

Untuk karakter yang tidak bisa jadi rig R15 (mesh ber-tulang sendiri): pakai **dua** Model
di **folder yang sama** — rig yang menyetir, mesh yang menempel.

```
Folder induk (mis. "Clown")
├── Hitbox   ← tag "Monster"      : rig R15 + Humanoid. Jalan, damage, tabrakan.
└── Clown    ← tag "MonsterSkin"  : mesh visual + animasi. Cuma tampilan.
```

`SkinBinder` otomatis: weld skin ke rig, matikan collision skin, **luruskan arah hadap skin**,
sembunyikan rig **saat Play**, matikan script animasi lama yang bentrok, dan pasang `SkinAnimator`.

### (Opsional) Waypoint patroli

`Folder` bernama **`Waypoints`** di `Workspace` atau di dalam Model monster; isi Part
(`Waypoint1`, `Waypoint2`, …). Tanpa waypoint, NPC memakai pola patrol otomatis.

### (Opsional) Safe Zone

Tag **`SafeZone`** pada Part, atau `Folder` **`SafeZones`** di `Workspace`.
Player yang **dilindungi** bilik tidak akan ditarget, dan monster ditahan di luar.

Perlindungan itu **berbatas waktu dan harus disengaja**: pemain menekan **E** untuk sembunyi
(default 20 detik, kapasitas 1 orang), dan **dikeluarkan paksa** saat napas habis. Jadi berdiri di
dalam Part tidak otomatis berarti aman. Sistemnya berdiri sendiri: [`SAFE_ZONE.md`](SAFE_ZONE.md).
Untuk perilaku lama (aman selamanya, tanpa prompt), beri Attribute `NoBreath = true` dan
`TouchToEnter = true` pada Part-nya.

---

## 🎮 State Flow

```
┌──────┐     target found     ┌─────────┐
│ IDLE │ ──────────────────► │ CHASING │
└──┬───┘                      └────┬────┘
   │ wait done                     │ in range
   ▼                               ▼
┌────────┐    target found   ┌───────────┐
│ PATROL │ ────────────────► │ ATTACKING │
└────────┘                   └───────────┘
   ▲                               │
   │    target lost / safe zone    │
   └───────────────────────────────┘
```

Deteksi: akuisisi awal (IDLE/PATROL) menghormati FOV; begitu sudah mengejar → **360°**.

---

## 🎬 Animasi

Animasi **otomatis** — cukup tag. Sistem membaca ID animasi dari dalam Model itu sendiri:
folder `Animations` → paket `Animate` milik rig → default Roblox.

### Animasi per-state (opsional)

Buat **folder bernama `Animations`**, isi `Animation` dengan nama berikut:

| Nama Animation | Dipakai saat |
|---|---|
| `Idle` | state `IDLE` |
| `Walk` | state `PATROL` |
| `Run` | state `CHASING` |
| `Attack` | event serangan (diputar sekali, tidak loop) |
| `Death` | NPC mati |

Nama folder & animasi **tidak case-sensitive** (`animations/idle` juga kebaca).
Isi sebagian saja boleh — nama yang tidak ada jatuh ke fallback, tidak error.

**Letak folder menentukan siapa yang memutar:**

| Jenis NPC | Folder `Animations` ditaruh di | Diputar oleh |
|---|---|---|
| Model biasa (rig ber-Humanoid) | Model itu sendiri | `AnimationManager` |
| Pola driver + skin | **Model skin** (ber-tag `MonsterSkin`) | `SkinAnimator` |

```
workspace.Clown
├── Hitbox          ← tag "Monster"      (folder animasi TIDAK di sini)
└── Clown           ← tag "MonsterSkin"
    └── Animations  ← folder di SKIN
        ├── Idle    (Animation → isi AnimationId)
        ├── Walk
        ├── Run
        ├── Attack
        └── Death
```

> **Jebakan:** me-*rename* `Animation` yang sudah ada (mis. yang nempel di dalam script `Anim`)
> menjadi `Idle` **tidak cukup**. Resolver mencari **folder** `Animations` sebagai anak Model;
> Animation di luar folder itu hanya kepungut sebagai *fallback tunggal*, sehingga semua state
> memakai animasi yang sama. Foldernya wajib ada.

> **Aset skinned mesh:** animasi R15 Roblox **tidak cocok** untuk mesh ber-tulang sendiri
> (mis. `mixamorig:*`). Animasi harus di-publish terhadap rig mesh itu, dan di-upload oleh
> akun/grup yang sama dengan tempat game berjalan.

### Tim mau animasi berlogika sendiri

Set Attribute `NoAutoAnimations = true`, lalu ikuti kanal yang disiarkan core AI:

- **Attribute `AIState`** → `IDLE` / `PATROL` / `CHASING` / `ATTACKING` / `DEAD` (keadaan)
- **BindableEvent `AISignal`** → `Attack`, `TargetAcquired`, `TargetLost`, `Died` (kejadian)

Contoh siap pakai: `ServerStorage/NPCAnimationTemplate`. **Jangan ubah `EnemyController`.**

---

## 🔧 Konfigurasi

### Default global (`Config` module)

```lua
Config.PatrolSpeed      = 10    -- Kecepatan patroli
Config.ChaseSpeed       = 18    -- Kecepatan mengejar
Config.DetectionRadius  = 45    -- Jarak deteksi (studs)
Config.LoseTargetRadius = 58    -- Jarak kehilangan target
Config.FieldOfView      = 160   -- Sudut pandang (derajat)
Config.AttackRadius     = 4     -- Jangkauan serang minimum (studs)
Config.AttackCooldown   = 1.5   -- Cooldown serang (detik)
Config.Damage           = 25    -- Damage per serangan
Config.PatrolWaitTime   = 2     -- Waktu idle di waypoint (detik)
Config.MonsterTag       = "Monster"
```

### Spesifikasi per-NPC (Attribute pada Model)

Nilai di atas adalah **default**. Kalau sebuah NPC mau berbeda, **tambahkan Attribute** di
Properties Model NPC tersebut — nama Attribute sama dengan nama field Config.
**Tidak perlu mengubah script**, dan NPC lain tidak terpengaruh.

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `PatrolSpeed` | Number | 10 | WalkSpeed saat patroli / idle |
| `ChaseSpeed` | Number | 18 | WalkSpeed saat mengejar |
| `DetectionRadius` | Number | 45 | Jarak maksimum melihat player |
| `LoseTargetRadius` | Number | 58 | Jarak target dianggap lepas |
| `FieldOfView` | Number | 160 | Sudut pandang; `360` = waspada segala arah |
| `AttackCooldown` | Number | 1.5 | Jeda antar serangan (detik) |
| `Damage` | Number | 25 | Damage per serangan; `0` = tidak melukai |
| `PatrolWaitTime` | Number | 2 | Lama diam di waypoint (detik) |

Contoh monster bos: `ChaseSpeed = 26`, `Damage = 40`, `DetectionRadius = 80`.

Aturan nilai: Number **≥ 0**. `0` sah (mis. `Damage = 0` untuk monster yang cuma menakuti).
Negatif atau salah tipe **diabaikan** → pakai default, dan dilaporkan `warn` sekali saat init
supaya salah ketik tidak senyap.

### Attribute perilaku lain

| Attribute | Tipe | Fungsi |
|---|---|---|
| `ChaseMode` | String | `PERSISTENT` / `NEAREST` / `ITEM_HOLDER` |
| `ShareTarget` | Bool | Bebas dari sistem target eksklusif (boleh mengejar korban yang sudah dikejar monster lain) |
| `AttackRadius` | Number | Kunci jangkauan serang (default: dihitung dari ukuran NPC) |
| `NoAutoAnimations` | Bool | Animasi diurus script NPC sendiri |
| `KeepRigVisible` | Bool | Rig tetap tampak saat Play |
| `KeepSkinCollision` | Bool | Jangan matikan collision skin |
| `KeepSkinOrientation` | Bool | Jangan luruskan orientasi skin |
| `SkinYawOffset` | Number | Koreksi arah hadap skin, derajat (mis. `180` kalau mesh menghadap mundur) |

**Mode `ITEM_HOLDER`:** monster memprioritaskan player yang membawa `Tool` ber-Attribute
`MonsterBait` = `true` (Bool). Nama Tool bebas dan boleh banyak item sekaligus; kalau tidak ada
pemegang, monster jatuh ke target terdekat.

**Jangkauan serang adaptif:** `AttackRadius` dihitung otomatis dari ukuran NPC, jadi monster
raksasa tetap bisa memukul tanpa tuning manual. Attribute `AttackRadius` mengunci nilainya.

### Target eksklusif — satu monster, satu korban

Dengan beberapa monster aktif, semuanya memakai logika yang sama sehingga cenderung
**menumpuk di satu player**. Modul `TargetClaims` mencegah itu: player yang sudah dikunci
satu monster **dilewati** monster lain saat mencari target.

| Config | Default | Fungsi |
|---|---|---|
| `ExclusiveTargets` | `true` | `false` = perilaku lama (semua monster boleh mengejar player yang sama) |
| `AllowClaimSteal` | `true` | `false` = korban tidak bisa direbut sama sekali |

Aturan perebutan (kalau `AllowClaimSteal = true`):

- korban hanya bisa direbut monster yang **signifikan lebih dekat** — memakai ambang
  `RetargetHysteresis` (30%) / `RetargetMinGap` (8 studs) yang sama dengan anti-thrash;
- klaim monster mode **`PERSISTENT` tidak bisa direbut** siapa pun;
- monster mode **`ITEM_HOLDER` selalu boleh menyambar** pembawa `MonsterBait` dari monster
  non-`ITEM_HOLDER`, seberapa jauh pun (prioritas item mutlak).

Klaim dilepas otomatis saat: target mati/hilang/masuk Safe Zone, monster mati, monster
di-untag, atau player keluar server. Ada juga pembersihan berkala tiap 5 detik sebagai
jaring pengaman.

**Konsekuensi yang perlu disadari:** kalau monster lebih banyak daripada player, monster
sisanya tetap **patroli** — bukan bug, itu memang tujuan mode ini. Untuk bos yang wajib
selalu mengejar, beri Attribute `ShareTarget = true` pada Model-nya.

Knob tuning sistem (`RetargetMinGap`, `PathTimeout`, `AgentRadius`, dst) **tidak** bisa
di-override per-NPC — ubah di `Config.luau` bila perlu.

---

## 🧩 Prinsip "satu penyetir"

Hanya **satu** sistem yang boleh menyetir `Animator`/`Humanoid` sebuah NPC. Dua penyetir pada
Animator yang sama = animasi kejang. Karena itu `SkinBinder` otomatis mematikan script animasi
lama di skin (mis. `Anim`, `Animate`) saat memasang skin.

---

## 🐛 Jebakan yang sudah pernah kena

- **`MaxHealth`/`Health` = 0** → NPC diam total **tanpa error**, karena main loop `while Health > 0`
  tidak pernah jalan. Sudah ada guard + `warn` + perbaikan otomatis.
- **Monster raksasa tak bisa memukul** → jangkauan sekarang proporsional terhadap ukuran NPC.
- **Monster buta permanen** → raycast LOS dulu hanya memfilter rig, padahal skin adalah *sibling*
  di luar Model rig, jadi ray menabrak badan sendiri. `SkinBinder:getIgnoreList()` memfilter keduanya.
- **Badut jalan menyamping** → `WeldConstraint` membekukan offset saat dibuat; orientasi skin
  sekarang diluruskan **sebelum** weld. Kalau "depan" mesh kebalik, pakai `SkinYawOffset`.
- **Perubahan ModuleScript tidak berlaku pada sesi Play yang sudah jalan** (`require` di-cache) —
  Stop dulu, lalu Play ulang.

Detail riwayat perubahan & hasil verifikasi: lihat [`PROGRESS.md`](PROGRESS.md).
