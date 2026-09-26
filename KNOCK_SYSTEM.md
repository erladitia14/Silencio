# Silencio — Knock & Revive System

Sistem **co-op down state**: pemain yang dipukul monster **tumbang** (bukan langsung mati),
merangkak pelan, dan harus **dibangunkan rekan** sebelum bleed-out habis.

**Tanpa tag, tanpa konfigurasi.** Otomatis aktif untuk semua pemain begitu game jalan.

> Bagian dari **Silencio – The Dark Story**. Indeks semua sistem: [`README.md`](README.md).
> Sistem lain: [`ENEMY_AI.md`](ENEMY_AI.md) · [`KEY_SYSTEM.md`](KEY_SYSTEM.md) ·
> [`SAFE_ZONE.md`](SAFE_ZONE.md) · [`BATTERY_PUZZLE.md`](BATTERY_PUZZLE.md) ·
> [`DAMAGE_EFFECT.md`](DAMAGE_EFFECT.md) · [`GENERATOR_SFX.md`](GENERATOR_SFX.md)

> **Semua angka di dokumen ini dibaca langsung dari Studio** (bukan dari file lokal repo,
> yang sebagian tertinggal). Sumber: `ReplicatedStorage.Modules.KnockSystem.Config`.

---

## Alur Singkat

1. Monster ber-tag `Monster` menyerang → `KnockService` **memutuskan** apakah pemain tumbang
   atau cuma kena damage.
2. Pemain tumbang → Attribute **`Knocked`** = `true` di karakter.
3. Pemain **merangkak** (`CrawlSpeed` = **6**, jump dimatikan), animasi knock
   `rbxassetid://2506281703` (bawaan Roblox `SitV2`), Tool yang dipegang **di-drop**.
4. **Bleed-out 30 detik**. Sisa ≤ 10 detik → sinyal `Warning` dikirim ke tim.
5. Rekan datang (≤ **9 stud**) → `ProximityPrompt` **"Revive"** muncul → **tahan E 5 detik**.
6. Berhasil → pemain bangun dengan Health **50**. Gagal (bleed-out habis) → **mati beneran**.

---

## 📐 Arsitektur

```
ServerScriptService/
└── Aer/
    └── KnockController              ← Script orchestrator

StarterPlayer/StarterPlayerScripts/
└── Aer/
    ├── KnockUI                      ← billboard bleed-out di atas kepala
    └── RevivePromptFilter           ← sembunyikan prompt "Revive" di diri sendiri

ReplicatedStorage/Modules/KnockSystem/    ← 8 modul
├── Config          (8893 b)   ← semua tuning + nama attribute/signal
├── Signal          ( 896 b)   ← helper BindableEvent
├── DownedState     (6327 b)   ← state pemain tumbang (register/unregister)
├── CrawlController (3610 b)   ← kecepatan merangkak + kunci jump
├── ReviveManager   (7891 b)   ← ProximityPrompt "Revive" + logika menahan E
├── KnockAnimator   (2974 b)   ← animasi knock
├── KnockService    (11558 b)  ← OTAK: deteksi serangan monster & keputusan knock
└── KnockHud        (10035 b)  ← modul presentasi billboard
```

---

## 🔌 Kontrak Data (tanpa RemoteEvent baru)

Semua state **dibaca dari Attribute karakter** — replikasi otomatis, jadi UI klien tidak
butuh remote apa pun.

| Attribute | Tipe | Isi |
|---|---|---|
| **`Knocked`** | Bool | `true` = sedang tumbang |
| **`KnockBleedOut`** | Number | Sisa detik bleed-out |
| **`KnockReviveProgress`** | Number | Progres revive `0..1` |

**Sinyal antar-modul**: `BindableEvent` bernama **`KnockSignal`**
(`Config.SignalName`) di dalam karakter. Event yang di-fire (`Config.SignalEvent`):

| Event | Kapan |
|---|---|
| `Downed` | Pemain baru tumbang |
| `Revived` | Pemain berhasil dibangunkan |
| `BleedOut` | Bleed-out habis → mati |
| `Warning` | Sisa waktu ≤ `BleedOutWarningTime` |

> Dipakai sistem lain (SFX/UI) untuk bereaksi tanpa mengubah KnockSystem.

---

## ⚙️ Konfigurasi (`KnockSystem/Config`)

### Deteksi knock

| Config | Default | Arti |
|---|---|---|
| `KnockOnlyFromMonster` | `true` | Knock hanya dari monster, bukan damage lain |
| `MonsterTag` | `"Monster"` | Tag monster yang bisa menumbangkan |
| `MonsterSignal` | `"AISignal"` | BindableEvent yang didengar (dari EnemyController) |
| `MonsterAttackEvent` | `"Attack"` | Event yang memicu knock |
| `MonsterHitWindow` | `2` | Jendela waktu (detik) setelah `Attack` dianggap sah |
| `MonsterSignalTimeout` | `10` | Batas tunggu `AISignal` muncul di Model |
| `KnockDecisionDelay` | `0.2` | Jeda sebelum memutuskan knock |

### Tumbang

| Config | Default | Arti |
|---|---|---|
| `BleedOutTime` | `30` | Detik sampai mati bila tak ditolong |
| `BleedOutWarningTime` | `10` | Sisa ≤ ini → sinyal `Warning` |
| `CrawlSpeed` | `6` | WalkSpeed saat merangkak (pemain normal 16) |
| `DisableJump` | `true` | Jump dimatikan saat tumbang |
| `DropTools` | `true` | Tool yang dipegang di-drop |
| `ClampHealthWhileDowned` | `true` | Health dikunci saat tumbang |
| `PlayKnockAnimation` | `true` | Putar animasi knock |
| `KnockAnimId` | `rbxassetid://2506281703` | Animasi knock (Roblox `SitV2`) |

### Revive

| Config | Default | Arti |
|---|---|---|
| `ReviveHoldTime` | `5` | Detik menahan tombol |
| `ReviveHealth` | `50` | Health setelah dibangunkan |
| `ReviveDistance` | `9` | `MaxActivationDistance` ProximityPrompt (stud) |
| `ReviveBreakDistance` | `13` | Jarak yang membatalkan revive |
| `ReviveKey` | `Enum.KeyCode.E` | Tombol revive |
| `ReviveActionText` | `"Revive"` | Teks aksi prompt |
| `ReviveObjectText` | `""` | Nama objek di prompt (kosong = tidak tampil) |
| `ReviveRequiresLineOfSight` | `false` | Wajib melihat korban |
| `CancelReviveOnDamage` | `true` | Revive batal kalau yang merevive kena damage |
| `DownedCannotRevive` | `true` | Pemain tumbang tidak bisa revive rekan |

### Tampilan & tick

| Config | Default | Arti |
|---|---|---|
| `KnockHudHeight` | `6` | Tinggi billboard di atas root (stud) |
| `BleedOutTick` | `0.2` | Interval pengurangan bleed-out (detik) |
| `CrawlTick` | `0.25` | Interval penjaga kecepatan merangkak |
| `ReviveTick` | `0.1` | Interval pembaruan progres revive |

> Ada juga tabel `NumberOverrides` / `BoolOverrides` di Config — jalur override per-kondisi.
> **Semua angka di atas bisa berubah; cek Config di Studio kalau ragu.**

---

## 🖥️ Sisi Klien

### `KnockUI` (LocalScript) — **tipis, nol logika tampilan**

Memantau **semua** karakter ber-Attribute `Knocked = true`, lalu menampilkan billboard
sisa bleed-out di atas kepala mereka. Kalau tim mau desain UI sendiri, **cukup ganti
konstanta `UI_MODULE`** (atau isi modulnya) — server & mekanisme knock tidak perlu disentuh.

**Kontrak modul UI** (dipenuhi `KnockHud`):

```lua
HudClass.new(adornee, height) -> objek
objek:update(payload)   -- { name, bleedOut, total, fraction, reviveProgress }
objek:tick(now)         -- tiap frame; JAGA anchor tetap tegak ke atas
objek:destroy()
```

Catatan desain penting: `tick()` **bukan cuma denyut** — rig tumbang bisa merangkak/berputar,
jadi `tick()` juga menjaga posisi anchor billboard tetap lurus ke sumbu dunia.

> Script ini sengaja **tidak** me-`require` `Config` (biar UI tetap jalan walau modul server
> tak dimuat). Nama Attribute ditulis ulang sebagai konstanta lokal.

### `RevivePromptFilter` (LocalScript) — sembunyikan prompt di diri sendiri

`ProximityPrompt` itu **global** — prompt di `HumanoidRootPart` pemain tumbang terlihat oleh
**semua** pemain, termasuk pemain tumbang itu sendiri (jarak 0 stud). Server **sudah menolak**
self-revive (`ReviveManager.canRevive`), jadi ini murni soal tampilan: jangan tawarkan tombol
yang tidak bisa dipakai.

Cara kerja: setiap `ProximityPrompt` bernama **`RevivePrompt`** muncul di Workspace, matikan
secara **lokal** (`Enabled = false`) kalau karakternya milik player ini. Server tidak terpengaruh —
pemain lain **tetap** melihat prompt di badan kita.

---

## 🤝 Hubungan dengan Enemy AI

`EnemyController` meng-emit event `Attack` lewat `BindableEvent` **`AISignal`** di dalam Model
monster. `KnockService` mendengarkannya, lalu memutuskan knock dalam `MonsterHitWindow`
(2 detik) sejak serangan.

**Konsekuensi untuk tim:** kalau Model monster **tidak punya `AISignal`**, atau script NPC
tidak meng-emit `Attack` (mis. karena `NoAutoAnimations` di-set tapi script tidak mengirim
event), pemain **tidak akan tumbang** — hanya kena damage biasa.

→ Detail kanal `AIState` / `AISignal`: [`ENEMY_AI.md`](ENEMY_AI.md)

> **Catatan drift:** cek Attribute `Knocked` di `TargetFinder` (supaya monster **melepas
> klaim** & mencari korban lain saat targetnya tumbang) **ada di repo tapi belum ada di
> Studio**. Artinya di Studio monster **masih mengejar** pemain yang tumbang.
> Lihat tabel drift di [`README.md`](README.md).
