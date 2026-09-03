# Silencio — The Dark Story

Game horror co-op escape di karnaval terbengkalai, dibuat dengan Roblox Studio.

| Sistem | Dokumen |
|---|---|
| **Enemy AI** — NPC monster: patrol, chase, attack, animasi | [`ENEMY_AI.md`](ENEMY_AI.md) |
| **Key System** — kunci → pintu → power switch → lampu | [`KEY_SYSTEM.md`](KEY_SYSTEM.md) |
| **Safe Zone** — bilik aman berbatas napas (toilet/lemari) | [`SAFE_ZONE.md`](SAFE_ZONE.md) |

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

**Banyak monster:** satu player hanya dikejar **satu** monster (target eksklusif, aktif secara
default). Monster lain mencari korban lain; kalau kehabisan korban, mereka tetap patroli.
Bos yang harus selalu mengejar: Attribute `ShareTarget = true`.

→ Atribut per-NPC, animasi per-state, mode chase: [`ENEMY_AI.md`](ENEMY_AI.md)

### Key System

Tempel keempat tag ini, lalu Play — tanpa mengisi Attribute apa pun sudah nyambung jadi satu
rantai puzzle (semua id default `"control_room"`):

`KeyPickup` → `LockedDoor` → `PowerSwitch` → `CarnivalLight`

→ Atribut, multi-puzzle, master key: [`KEY_SYSTEM.md`](KEY_SYSTEM.md)

### Safe Zone

Tempel **`SafeZone`** pada Part bilik (toilet, lemari). Pemain di dalamnya tidak bisa ditarget
**dan monster tidak bisa masuk** — tapi cuma **20 detik**, kapasitas **1 orang**, lalu bilik hangus
15 detik. Bar napas muncul otomatis di layar pemain.

Aman selamanya seperti perilaku lama: Attribute `NoBreath = true`.

→ Siklus bilik, Attribute, tukar modul UI: [`SAFE_ZONE.md`](SAFE_ZONE.md)

---

## Daftar Tag

| Tag | Sistem | Ditempel pada |
|---|---|---|
| `Monster` | Enemy AI | Model NPC (rig ber-`Humanoid`) |
| `MonsterSkin` | Enemy AI | Model mesh visual (pola driver+skin) |
| `SafeZone` | Safe Zone | Part bilik aman (napas 20s, 1 orang, monster ditahan) |
| `KeyPickup` | Key System | Kunci yang bisa diambil |
| `LockedDoor` | Key System | Pintu yang butuh kunci |
| `PowerSwitch` | Key System | Tuas/tombol power |
| `CarnivalLight` | Key System | Lampu yang menyala saat power on |

Attribute opsional per tag ada di dokumen sistem masing-masing. Attribute yang paling sering
dipakai untuk Enemy AI:

| Attribute | Pada | Fungsi singkat |
|---|---|---|
| `ChaseMode` | Model `Monster` | `NEAREST` (default) / `PERSISTENT` / `ITEM_HOLDER` |
| `ShareTarget` | Model `Monster` | Bebas dari aturan "satu monster satu korban" |
| `MonsterBait` | `Tool` apa pun | Pembawanya diprioritaskan monster mode `ITEM_HOLDER` |
| `BreathTime` | Part `SafeZone` | Lama bilik melindungi, detik (default 20) |
| `NoBreath` | Part `SafeZone` | Bilik aman selamanya (tanpa timer napas) |
| `KeyId` | Objek `KeyPickup` | Id kunci; harus cocok dengan `RequiredKey` pintu |

---

## Letak Kode

```
src/
├── ServerScriptService/                 ← Script orchestrator (jalan otomatis)
│   ├── EnemyController.server.luau
│   ├── KeySystemController.server.luau
│   └── SafeZoneController.server.luau
├── ReplicatedStorage/Modules/           ← ModuleScript (logika)
│   ├── EnemyController/                 ← 11 modul Enemy AI
│   ├── KeySystem/                       ← 8 modul Key System
│   └── SafeZone/                        ← 7 modul Safe Zone
├── StarterPlayer/
│   ├── StarterCharacterScripts/
│   │   └── DamageEffect.client.luau     ← efek horor client (vignette + camera shake)
│   └── StarterPlayerScripts/
│       └── SafeZoneUI.client.luau       ← bar napas Safe Zone
└── ServerStorage/
    └── NPCAnimationTemplate.server.luau ← contoh opsional
```

**Jangan pindahkan** Script orchestrator keluar dari `ServerScriptService` — Script di
`ReplicatedStorage` tidak dijalankan engine, sistemnya akan mati tanpa error.

Folder lokal ini adalah **sumber kebenaran**; perubahan didorong ke Studio, bukan sebaliknya.
