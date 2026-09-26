# Silencio — Enemy AI System

Sistem NPC Enemy AI modular untuk Roblox Studio, pola **Finite State Machine (FSM)**.

**Prinsip desain: versatile.** Tim cukup memberi **tag** (+ Attribute opsional) pada Model NPC —
patrol, chase, idle, damage, dan **animasi** langsung jalan. **Tidak perlu mengubah script AI.**

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`KEY_SYSTEM.md`](KEY_SYSTEM.md) · [`SAFE_ZONE.md`](SAFE_ZONE.md).

---

## 📐 Arsitektur

```
ServerScriptService/
└── Aer/                     ← folder sistem kita (terpisah dari punya tim)
    └── EnemyController      ← Script utama (orchestrator)
ReplicatedStorage/Modules/
└── EnemyController/         ← 10 modul
    ├── Config               ← Default global + resolver override per-NPC
    ├── StateMachine         ← FSM generik & reusable
    ├── MonsterRig           ← Siapkan mesh jadi rig yang bisa dikendalikan (1 model)
    ├── TargetFinder         ← Pencarian target (FOV, LOS, range) + jangkauan adaptif
    ├── TargetClaims         ← Registry "satu monster = satu korban"
    ├── NavigationManager    ← Pathfinding & navigasi
    ├── CombatManager        ← Serangan, damage, cooldown
    ├── PatrolManager        ← Waypoint patrol system
    ├── SafeZoneManager      ← Jembatan ke sistem Safe Zone (SAFE_ZONE.md)
    └── AnimationManager     ← Animasi otomatis via Humanoid (rig)
ServerStorage/
└── NPCAnimationTemplate     ← Contoh untuk tim yang mau animasi berlogika sendiri
```

> Semua controller kita (`EnemyController`, `KeySystemController`, `SafeZoneController`,
> `KnockController`, `BatteryPuzzleController`, `AssemblyController`, `GeneratorSFXController`)
> ada di dalam **`ServerScriptService.Aer`**. Client kita ada di
> **`StarterPlayer.StarterPlayerScripts.Aer`**. Struktur lengkap: [`README.md`](README.md).

Sistem lain: Key System ([`KEY_SYSTEM.md`](KEY_SYSTEM.md)), Safe Zone ([`SAFE_ZONE.md`](SAFE_ZONE.md)),
Knock & Revive + Battery Puzzle ([`README.md`](README.md)).

---

## ⚙️ Setup Cepat

Beri tag **`Monster`** pada Model (View → Tag Editor). Selesai — AI + animasi jalan otomatis,
termasuk untuk NPC yang di-spawn saat runtime.

Syarat Model: punya `Humanoid` + `HumanoidRootPart`, dan `Health > 0`.

### Model mesh tunggal (satu Model saja)

Untuk NPC yang cuma **satu Model mesh** (mis. hasil import, tanpa rig R15 terpisah), cukup beri
tag `Monster` langsung — **tidak perlu dua Model lagi**. Modul `MonsterRig` yang menyesuaikan:

- membuat **`HumanoidRootPart` proxy** — Part kecil tak terlihat yang melayang sesuai `HipHeight`;
- menjadikan **mesh asli sebagai visual** (`CanCollide = false`) yang di-*weld* ke proxy
  (weld bernama `MonsterRigWeld`);
- mematikan script animasi bawaan yang bentrok (`Anim`, `Animate`) supaya tidak rebutan `Animator`;
- memperbaiki `Animator` bila rig tidak punya;
- memutar mesh bila arah hadapnya kebalik (`MeshYawOffset`).

Attribute penyetel (opsional, semua di Model `Monster`):

| Attribute | Tipe | Fungsi |
|---|---|---|
| `HipHeight` | Number | Paksa `HipHeight` proxy (default: 60% tinggi mesh) |
| `ColliderSize` | Vector3 | Ukuran collider proxy (default `(3, tinggiMesh, 3)`) |
| `ColliderOffset` | Vector3 | Geser collider dari pusat mesh |
| `NoProxy` | Bool | Jangan bikin proxy — mesh tetap jadi `HumanoidRootPart` |
| `KeepCollision` | Bool | Jangan sentuh collision sama sekali |
| `MeshYawOffset` | Number | Koreksi yaw mesh, derajat (mis. `180` kalau menghadap mundur) |
| `MeshYawOffsetX` / `MeshYawOffsetZ` | Number | Koreksi pitch / roll mesh, derajat |

> **Penting:** set `Parent` dulu, baru `WorldCFrame` — kalau tidak, `WorldCFrame` diperlakukan
> sebagai CFrame lokal dan posisi meleset jauh.

### (Opsional) Waypoint patroli

`Folder` bernama **`Waypoints`** di `Workspace` atau di dalam Model monster; isi Part
(`Waypoint1`, `Waypoint2`, …). Tanpa waypoint, NPC memakai pola patrol otomatis
(`WaypointSpacing` = 4 stud).

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
┌──────┐     target found     ┌──────────┐
│ IDLE │ ──────────────────► │ CHASING  │
└──┬───┘                      └────┬─────┘
   │ wait done                     │ in range
   ▼                               ▼
┌────────┐    target found   ┌───────────┐
│ PATROL │ ────────────────► │ ATTACKING │
└────────┘                   └───────────┘
   ▲                               │
   │    target lost / safe zone    │
   └───────────────────────────────┘
                        (kematian) ──► DEAD
```

State resmi: **`IDLE`** · **`PATROL`** · **`CHASING`** · **`ATTACKING`** · **`DEAD`**

Deteksi: `FieldOfView` = **360** secara default (waspada segala arah). Kalau mau NPC punya sudut
pandang terbatas, turunkan lewat Attribute per-NPC (mis. `160`).

---

## 🎬 Animasi

Animasi **otomatis** — cukup tag. Sistem membaca ID animasi dari dalam Model itu sendiri:
folder `Animations` → paket `Animate` milik rig → default Roblox.

### Animasi per-state (opsional)

Buat **folder bernama `Animations`** di dalam Model `Monster`, isi `Animation` dengan nama berikut:

| Nama Animation | Dipakai saat |
|---|---|
| `Idle` | state `IDLE` |
| `Walk` | state `PATROL` |
| `Run` | state `CHASING` |
| `Attack` | event serangan (diputar sekali, tidak loop) |
| `Death` | NPC mati |

Nama folder & animasi **tidak case-sensitive** (`animations/idle` juga kebaca).
Isi sebagian saja boleh — nama yang tidak ada jatuh ke fallback, tidak error.

```
workspace.Clown              ← tag "Monster"
└── Animations               ← folder WAJIB, di dalam Model monster
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
> akun/grup yang sama dengan tempat game berjalan — kalau tidak, animasi gagal load dan karakter
> tampak kaku (pesan: `The experience doesn't have access permission to use asset id ...`).

### Tim mau animasi berlogika sendiri

Set Attribute `NoAutoAnimations = true` pada Model, lalu ikuti kanal yang disiarkan core AI:

- **Attribute `AIState`** → `IDLE` / `PATROL` / `CHASING` / `ATTACKING` / `DEAD` (keadaan)
- **BindableEvent `AISignal`** (otomatis dibuat di dalam Model) → `Attack`, `TargetAcquired`,
  `TargetLost`, `Died` (kejadian)

Contoh siap pakai: `ServerStorage/NPCAnimationTemplate`. **Jangan ubah `EnemyController`.**

> **`AISignal` juga dipakai sistem Knock & Revive** — event `Attack` di situ yang memicu pemain
> tumbang. Kalau Model tidak punya `AISignal`, knock tidak akan terpicu (lihat bagian di bawah).

---

## 🔧 Konfigurasi

### Default global (`Config` module)

```lua
Config.PatrolSpeed      = 10    -- Kecepatan patroli
Config.ChaseSpeed       = 20    -- Kecepatan mengejar
Config.DetectionRadius  = 95    -- Jarak deteksi (studs)
Config.LoseTargetRadius = 160   -- Jarak kehilangan target
Config.FieldOfView      = 360   -- Sudut pandang (derajat)
Config.AttackRadius     = 4     -- Jangkauan serang (studs)
Config.AttackCooldown   = 1.5   -- Cooldown serang (detik)
Config.Damage           = 25    -- Damage per serangan
Config.PatrolWaitTime   = 0.5   -- Waktu idle di waypoint (detik)
Config.MonsterTag       = "Monster"
Config.WaypointFolder   = "Waypoints"
Config.WaypointSpacing  = 4
Config.SafeZoneFolder   = "SafeZones"
Config.SafeZoneTag      = "SafeZone"
```

Tuning navigasi (jarang diubah): `PathTimeout = 8`, `AgentRadius = 2.5`, `AgentHeight = 5`,
`AgentCanJump = true`, `AgentJumpHeight = 10`.

Tuning retarget (anti-thrash): `RetargetInterval = 1`, `RetargetCommitTime = 2.5`,
`RetargetHysteresis = 0.3`, `RetargetMinGap = 8`, `PersistentGiveUpTime = 0`.

### Spesifikasi per-NPC (Attribute pada Model)

Nilai di atas adalah **default**. Kalau sebuah NPC mau berbeda, **tambahkan Attribute** di
Properties Model NPC tersebut — nama Attribute sama dengan nama field Config.
**Tidak perlu mengubah script**, dan NPC lain tidak terpengaruh.

| Attribute | Tipe | Default | Fungsi |
|---|---|---|---|
| `PatrolSpeed` | Number | 10 | WalkSpeed saat patroli / idle |
| `ChaseSpeed` | Number | 20 | WalkSpeed saat mengejar |
| `DetectionRadius` | Number | 95 | Jarak maksimum melihat player |
| `LoseTargetRadius` | Number | 160 | Jarak target dianggap lepas |
| `FieldOfView` | Number | 360 | Sudut pandang; `360` = waspada segala arah |
| `AttackCooldown` | Number | 1.5 | Jeda antar serangan (detik) |
| `Damage` | Number | 25 | Damage per serangan; `0` = tidak melukai |
| `PatrolWaitTime` | Number | 0.5 | Lama diam di waypoint (detik) |

Contoh monster bos: `ChaseSpeed = 26`, `Damage = 40`, `DetectionRadius = 120`.

Aturan nilai: Number **≥ 0**. `0` sah (mis. `Damage = 0` untuk monster yang cuma menakuti).
Negatif atau salah tipe **diabaikan** → pakai default, dan dilaporkan `warn` sekali saat init
supaya salah ketik tidak senyap.

### Attribute perilaku lain

| Attribute | Tipe | Fungsi |
|---|---|---|
| `ChaseMode` | String | `NEAREST` (default) / `PERSISTENT` / `ITEM_HOLDER` |
| `ShareTarget` | Bool | Bebas dari sistem target eksklusif (boleh mengejar korban yang sudah dikejar monster lain) |
| `AttackRadius` | Number | Kunci jangkauan serang (default: dihitung dari ukuran NPC) |
| `NoAutoAnimations` | Bool | Animasi diurus script NPC sendiri |

Attribute khusus rig mesh: `HipHeight`, `ColliderSize`, `ColliderOffset`, `NoProxy`,
`KeepCollision`, `MeshYawOffset`, `MeshYawOffsetX`, `MeshYawOffsetZ` (lihat bagian Setup).

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

## 🤝 Hubungan dengan Knock & Revive

Monster **tidak langsung membunuh** pemain. `CombatManager` memanggil `TakeDamage`, lalu sistem
**KnockSystem** memutuskan apakah pemain **tumbang** (knocked) atau mati.

Cara KnockSystem mendengar monster (dari `KnockSystem/Config`):

| Config Knock | Default | Arti |
|---|---|---|
| `MonsterTag` | `Monster` | Hanya monster ber-tag ini yang bisa menumbangkan |
| `MonsterSignal` | `AISignal` | Nama BindableEvent yang didengar |
| `MonsterAttackEvent` | `Attack` | Event yang memicu knock |
| `MonsterHitWindow` | 2 | Jendela waktu (detik) setelah `Attack` dianggap sah |
| `MonsterSignalTimeout` | 10 | Batas tunggu `AISignal` muncul di Model |
| `KnockOnlyFromMonster` | `true` | Knock hanya dari monster, bukan damage lain |

**Konsekuensi untuk tim:** kalau Model monster **tidak punya `AISignal`**, atau
`NoAutoAnimations` tidak di-set sementara script NPC tidak meng-emit `Attack`, pemain
**tidak akan tumbang** — hanya kena damage biasa.

---

## 🧩 Prinsip "satu penyetir"

Hanya **satu** sistem yang boleh menyetir `Animator`/`Humanoid` sebuah NPC. Dua penyetir pada
Animator yang sama = animasi kejang. Karena itu `MonsterRig` otomatis mematikan script animasi
lama di mesh (mis. `Anim`, `Animate`) dan menyeragamkan `Animator` saat menyiapkan rig.

---

## 🐛 Jebakan yang sudah pernah kena

- **`MaxHealth`/`Health` = 0** → NPC diam total **tanpa error**, karena main loop `while Health > 0`
  tidak pernah jalan. Sudah ada guard + `warn` + perbaikan otomatis.
- **Monster raksasa tak bisa memukul** → jangkauan sekarang proporsional terhadap ukuran NPC.
- **Monster buta permanen** → raycast LOS dulu hanya memfilter rig, padahal mesh visual adalah
  *sibling* di luar Model rig, jadi ray menabrak badan sendiri. Sekarang keduanya difilter.
- **Karakter jalan menyamping** → `WeldConstraint` membekukan offset saat dibuat; orientasi mesh
  sekarang diluruskan **sebelum** weld. Kalau "depan" mesh kebalik, pakai `MeshYawOffset`.
- **Animasi gagal load** (`The experience doesn't have access permission to use asset id ...`) →
  aset animasi di-upload akun **pribadi** padahal game berjalan di bawah **grup**. Izin harus
  di-grant di Creator Hub, atau animasi dikosongkan dan pakai default Roblox.
- **Perubahan ModuleScript tidak berlaku pada sesi Play yang sudah jalan** (`require` di-cache) —
  Stop dulu, lalu Play ulang.

Detail riwayat perubahan & hasil verifikasi: lihat [`PROGRESS.md`](PROGRESS.md).
