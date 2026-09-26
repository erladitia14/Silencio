# Silencio The Dark Story — Roblox Horror Game

## Project Type
- **Platform:** Roblox Studio
- **Genre:** Co-op horror escape game
- **Setting:** Karnaval terbengkalai dengan puzzle & monster
- **Collaboration:** KARIS Studio × OnBlox Studio
- **Target Release:** End of September 2026

## Chapter 1: The Mask Maze
- **Puzzle Type:** Wheel of Fate trivia games
- **Key Assets:** Topeng + lukisan paintings
- **Tracker Sheet:** Google Sheet "TRACKER Silencio KARIS X OnBlox"
  - ID: `1GhFfDhEyBIKM9ypWBdlBXgLayqgViNT_W3vvAtHS_WA`
  - gid=1158016091
  - Total tasks: 33

---

## ⚠️ Alur Kerja — BACA DULU

**Repo ini dan Studio belum sepenuhnya sinkron — dan drift-nya DUA ARAH.** Sebagian file di
Studio lebih baru dari repo (mis. `DamageEffect`, `BatteryService`, `CaseService`, `ZoneService`,
`AssemblyService`, kedua `Config`), tapi ada juga yang sebaliknya (mis. `TargetFinder` di repo
punya cek Attribute `Knocked` yang **belum ada** di Studio).

**Kalau ragu, baca `Source` dari Studio lewat MCP dulu.** Jangan asumsikan salah satu sisi
paling benar. Tabel drift lengkap: [`README.md`](README.md).

| | |
|---|---|
| **Repo** | Git repo biasa (branch `main`), remote `origin`. Commit & push seperti normal. |
| **Sync ke Studio** | **MCP** (`set_script_source` untuk ModuleScript, `execute_luau` untuk instance). |
| **Rojo** | **TIDAK DIPAKAI lagi.** `default.project.json` = artefak mati, jangan diandalkan. |
| **Playtest** | Manual oleh Aer di Studio. |

> **Jangan pakai `rojo serve` / `rojo build`** — pipeline-nya sudah tidak dipakai, dan
> `default.project.json` sudah tidak mencerminkan struktur place asli (`BUILD Chapter 1`).

### ⚠️ Script yang ada di Studio tapi TIDAK ada di `src/`

Itu **milik tim** (framework `SilencioHoror`, `SilencioServer`, `SilencioClient`,
`Boba/Teleport`, pipe puzzle, prompt billboard, HUD). **Jangan diubah tanpa koordinasi.**

- Jangan tambah remote ke `ReplicatedStorage.Remotes` (dikelola tim).
- Jangan bikin `ScreenGui` bernama sama dengan punya tim (`SilencioHUD`, `UiDialogTemplate`, `TeleportFadeGui`).
- `ReplicatedStorage.Events` dipakai bersama (`TeleportFade`/`JumpscareEvent` tim,
  `BatteryPuzzleEvent` kita).
- **`WalkSpeed` di-reset ke 12 oleh `PlayerManager` tim tiap karakter spawn** — sistem carry (8)
  dan crawl knock (6) menyetel ulang setelah respawn.

### Struktur di Studio (per 23 Sep 2026)

Sistem kita dikelompokkan dalam folder **`Aer`**:

```
ServerScriptService/
├── SilencioServer/     ← TIM
├── Feature/            ← TIM (TeleprotHandler)
└── Aer/                ← KITA
    ├── EnemyController          ├── KnockController
    ├── KeySystemController      ├── BatteryPuzzleController
    ├── SafeZoneController       ├── AssemblyController
    └── GeneratorSFXController

StarterPlayer/StarterPlayerScripts/
├── SilencioClient/     ← TIM (LocalScript + 9 modul)
├── Boba/               ← TIM (Teleport)
└── Aer/                ← KITA
    ├── KnockUI              ├── SafeZoneUI
    ├── RevivePromptFilter   └── JumpscareHandler
    └── PuzzleInputClient

StarterPlayer/StarterCharacterScripts/DamageEffect   ← KITA
ReplicatedStorage/Modules/                            ← KITA (5 sistem, 45 modul)
```

### Sistem yang Sudah Jadi

| Sistem | Dokumen | Controller |
|---|---|---|
| **Enemy AI** — FSM monster, patrol/chase/attack, animasi | [`ENEMY_AI.md`](ENEMY_AI.md) | `Aer/EnemyController` |
| **Key System** — kunci → pintu → power switch → lampu | [`KEY_SYSTEM.md`](KEY_SYSTEM.md) | `Aer/KeySystemController` |
| **Safe Zone** — bilik sembunyi berbatas napas | [`SAFE_ZONE.md`](SAFE_ZONE.md) | `Aer/SafeZoneController` |
| **Knock & Revive** — pemain tumbang, merangkak, dibangunkan rekan | [`README.md`](README.md) | `Aer/KnockController` |
| **Battery Puzzle** — rakit baterai + panel generator | [`README.md`](README.md) | `Aer/BatteryPuzzleController` + `Aer/AssemblyController` |

Riwayat lengkap tiap perubahan + commit hash: [`PROGRESS.md`](PROGRESS.md).

### Task #10: NPC Monster Script (selesai)
- `ServerScriptService/Aer/EnemyController` — FSM modular
- 10 modul di `ReplicatedStorage/Modules/EnemyController/`:
  `Config`, `StateMachine`, `MonsterRig`, `TargetFinder`, `TargetClaims`,
  `NavigationManager`, `CombatManager`, `PatrolManager`, `SafeZoneManager`, `AnimationManager`
- Pola rig: **1 model** (mesh tunggal) — `MonsterRig` bikin proxy `HumanoidRootPart`.
  Pola lama "driver + skin" (`MonsterSkin`/`SkinBinder`/`SkinAnimator`) sudah **dihapus**.

### Task #16: KEY SYSTEM (selesai)
- **Progression:** Control room key → Power switch → Carnival lights
- **Purpose:** Gating system for chapter completion

---

## Documentation
- **MoM PDF:** `Silencio MoM_0_.pdf` in project folder
- **Game Design:** Keep all rules documented in AGENTS.md
- **Never assume** — always ask for clarification on requirements

## Security Rules
- Never commit .env files or credentials to Git
- Tracker sheet access limited to team members only
- **Jangan pernah menjalankan playtest sendiri** — Aer yang playtest. Agent hanya boleh
  verifikasi edit-mode (baca `Source`, cek Attribute, jalankan harness di `_tools/`).
