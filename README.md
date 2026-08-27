# Silencio — The Dark Story

Game horror co-op escape di karnaval terbengkalai, dibuat dengan Roblox Studio.

| Sistem | Dokumen |
|---|---|
| **Enemy AI** — NPC monster: patrol, chase, attack, animasi | [`ENEMY_AI.md`](ENEMY_AI.md) |
| **Key System** — kunci → pintu → power switch → lampu | [`KEY_SYSTEM.md`](KEY_SYSTEM.md) |

---

## Cara Pakai

Kedua sistem digerakkan **tag**. Kamu **tidak perlu menempel script** ke objek apa pun.

1. Buka **View → Tag Editor**
2. Pilih objek di Explorer
3. Tempel tag sesuai tabel di bawah
4. **Play**

Objek yang di-tag saat game sedang jalan juga langsung ikut terdaftar.

### Enemy AI

Tempel **`Monster`** pada Model NPC. Selesai — patrol, chase, attack, dan animasi jalan otomatis.

Syarat Model: punya `Humanoid` + `HumanoidRootPart`, dan `Health` lebih dari 0.

Untuk karakter mesh import (Mixamo dsb) yang tidak bisa jadi rig R15, pakai dua Model dalam satu
folder: rig ber-tag `Monster` sebagai penggerak, mesh ber-tag `MonsterSkin` sebagai tampilan.

→ Atribut per-NPC, animasi per-state, mode chase: [`ENEMY_AI.md`](ENEMY_AI.md)

### Key System

Tempel keempat tag ini, lalu Play — tanpa mengisi Attribute apa pun sudah nyambung jadi satu
rantai puzzle (semua id default `"control_room"`):

`KeyPickup` → `LockedDoor` → `PowerSwitch` → `CarnivalLight`

→ Atribut, multi-puzzle, master key: [`KEY_SYSTEM.md`](KEY_SYSTEM.md)

---

## Daftar Tag

| Tag | Sistem | Ditempel pada |
|---|---|---|
| `Monster` | Enemy AI | Model NPC (rig ber-`Humanoid`) |
| `MonsterSkin` | Enemy AI | Model mesh visual (pola driver+skin) |
| `SafeZone` | Enemy AI | Part area aman; player di dalamnya tidak ditarget |
| `KeyPickup` | Key System | Kunci yang bisa diambil |
| `LockedDoor` | Key System | Pintu yang butuh kunci |
| `PowerSwitch` | Key System | Tuas/tombol power |
| `CarnivalLight` | Key System | Lampu yang menyala saat power on |

Attribute opsional per tag ada di dokumen sistem masing-masing.

---

## Letak Kode

```
src/
├── ServerScriptService/                 ← Script orchestrator (jalan otomatis)
│   ├── EnemyController.server.luau
│   └── KeySystemController.server.luau
├── ReplicatedStorage/Modules/           ← ModuleScript (logika)
│   ├── EnemyController/
│   └── KeySystem/
└── ServerStorage/
    └── NPCAnimationTemplate.server.luau ← contoh opsional
```

**Jangan pindahkan** Script orchestrator keluar dari `ServerScriptService` — Script di
`ReplicatedStorage` tidak dijalankan engine, sistemnya akan mati tanpa error.
