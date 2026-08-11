# Silencio — Monster AI System v2.0

Arsitektur modular profesional untuk sistem NPC Monster AI di Roblox Studio.
Menggunakan **Finite State Machine (FSM)** pattern dengan modul terpisah untuk setiap tanggung jawab.

---

## 📐 Arsitektur

```
ServerScriptService/
├── MonsterController        ← Script utama (orchestrator)
└── MonsterAI/               ← Folder berisi semua module
    ├── Config               ← Konfigurasi terpusat
    ├── StateMachine         ← FSM generik & reusable
    ├── SafeZoneManager      ← Deteksi area aman (OBB check)
    ├── TargetFinder         ← Pencarian target (FOV, LOS, range)
    ├── NavigationManager    ← Pathfinding & navigasi
    ├── CombatManager        ← Serangan, damage, cooldown, animasi
    └── PatrolManager        ← Waypoint patrol system
```

---

## 📦 Deskripsi Setiap Module

### `Config`
Konfigurasi terpusat. Semua nilai tuning (speed, radius, cooldown, dll)
disimpan di satu tempat agar mudah diubah tanpa menyentuh logic.

### `StateMachine`
FSM generik yang bisa dipakai ulang. Setiap state memiliki callback:
- `onEnter(context)` — saat masuk state
- `onUpdate(context)` — setiap tick
- `onExit(context)` — saat keluar state

### `SafeZoneManager`
Mendeteksi apakah karakter berada di area aman menggunakan:
- **CollectionService Tag** (`"SafeZone"`)
- **Folder** `Workspace.SafeZones`
- **OBB (Oriented Bounding Box)** untuk akurasi tinggi

### `TargetFinder`
Mencari dan memvalidasi target player:
- **Distance check** dengan Detection Radius
- **Field of View (FOV)** angle check
- **Line of Sight (LOS)** raycasting
- **Safe Zone filtering** (player di safe zone tidak ditarget)
- **LoseTargetRadius** (hysteresis untuk mencegah flickering state)

### `NavigationManager`
Navigasi NPC menggunakan `PathfindingService`:
- Path computation dengan agent parameters dari Config
- Fallback ke `MoveTo` langsung jika pathfinding gagal
- **Abort callback** untuk interrupt saat target terdeteksi
- Jump handling otomatis

### `CombatManager`
Sistem combat per-monster:
- Cooldown tracker per instance
- Damage dealing via `TakeDamage`
- Animasi attack otomatis (opsional)

### `PatrolManager`
Sistem waypoint patrol:
- Auto-collect waypoint dari folder di model/Workspace
- Sort by name (Waypoint1, Waypoint2, dst.)
- Fallback ke pola patrol otomatis jika waypoint tidak ada
- Cyclic iteration & runtime refresh

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

---

## ⚙️ Setup Cepat

### 1. Beri Tag pada Model Monster
- Di Roblox Studio, pilih Model monster
- Buka **Tag Editor** (View → Tag Editor)
- Tambahkan tag `"Monster"` pada model

### 2. (Opsional) Buat Waypoint Patroli
- Buat `Folder` bernama **`Waypoints`** di `Workspace` atau di dalam Model monster
- Masukkan Part-Part sebagai titik patroli (`Waypoint1`, `Waypoint2`, dst.)
- Set Part: `CanCollide = false`, `Anchored = true`, `Transparency = 1`

### 3. (Opsional) Buat Safe Zone
**Metode A — Folder:**
- Buat `Folder` bernama **`SafeZones`** di `Workspace`
- Masukkan Part transparan yang mencakup area aman

**Metode B — Tag:**
- Beri tag `"SafeZone"` pada Part area aman via Tag Editor

### 4. Selesai!
Script akan otomatis mendeteksi dan menginisialisasi AI untuk semua model
dengan tag `"Monster"`, termasuk yang ditambahkan saat runtime (respawn/spawn).

---

## 🔧 Konfigurasi (`Config` Module)

```lua
Config.PatrolSpeed      = 10    -- Kecepatan patroli
Config.ChaseSpeed       = 18    -- Kecepatan mengejar
Config.DetectionRadius  = 45    -- Jarak deteksi (studs)
Config.LoseTargetRadius = 58    -- Jarak kehilangan target
Config.FieldOfView      = 160   -- Sudut pandang (derajat)
Config.AttackRadius     = 4     -- Jarak serang (studs)
Config.AttackCooldown   = 1.5   -- Cooldown serang (detik)
Config.Damage           = 25    -- Damage per serangan
Config.PatrolWaitTime   = 2     -- Waktu idle di waypoint (detik)
Config.MonsterTag       = "Monster"  -- Tag untuk auto-init
```
