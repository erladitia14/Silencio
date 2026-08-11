# 📋 PROGRESS — Silencio "The Dark Story"

> Game horror co-op Roblox · KARIS Studio × OnBlox Studio
> Target rilis: **akhir September 2026** · Chapter 1: *The Mask Maze*
>
> **Aturan catat progress:** file ini HANYA di-update ketika Aer bilang "catat progress".
> Bukan otomatis. Entri terbaru di atas.

---

## Konvensi

- **Source of truth:** folder lokal `C:\Users\erlan\Documents\Silencio` (Rojo) → di-push ke Studio.
- **Repo:** `erladitia14/Silencio` (private) · branch `main`.
- **Verifikasi tanpa playtest:** struktural + compile-check Studio + behavioral test. Playtest = Aer.
- Format tanggal: entri diberi label commit hash + ringkasan.

---

## 🗓️ Log Progress

### Entri #2 — Fix feedback playtest ITEM_HOLDER · commit `f2fdb4f`
**Fitur/Task:** Monster AI — perbaikan berdasarkan playtest mode ITEM_HOLDER.

**Masalah yang dilaporkan Aer:**
1. **Bug A** — 1 orang pegang MonsterBait, 1 tidak. Monster tetap ngejar yang **tidak** pegang MonsterBait walau pemegang bait muter-muter di dekat.
2. **Bug B** — setelah monster membunuh player, dia **patroli dulu** (jeda lama) sebelum ngejar target berikutnya.

**Diagnosis:**
- **Bug A = A2 (bug logika, bukan salah setting).** Attribute monster sudah benar `ChaseMode=ITEM_HOLDER` (diverifikasi via MCP). Akar: `evaluateRetarget` memberlakukan hysteresis jarak (30%/8studs) ke SEMUA pergantian target — termasuk saat mau pindah dari non-holder ke holder. Karena pemegang bait tidak "cukup lebih dekat", monster nggak mau pindah.
- **Bug B** — saat target mati (di state ATTACKING/CHASING), kode langsung `setState("PATROL")` + `task.wait(0.5)`. Korban berikutnya baru ke-detect saat kebetulan masuk FOV/radius sambil patroli.

**Solusi yang diterapkan:**
- **Fix A2:** `evaluateRetarget` mode ITEM_HOLDER → **SWITCH INSTAN** ke pemegang bait saat target sekarang bukan holder (bypass commit time + hysteresis; item = prioritas mutlak). Kalau dua-duanya holder → tetap pakai hysteresis (anti-thrash, biar monster nggak kejang).
- **Fix B:** helper baru `reacquireOrPatrol()` dipanggil di CHASING & ATTACKING saat target invalid → langsung akuisisi ulang & lanjut CHASING kalau ada korban lain; buang `task.wait(0.5)`.
- **360° saat berburu:** `TargetFinder` dapat param `ignoreFOV`. Saat retarget & re-acquire pasca-kill, FOV dilewati (monster waspada penuh 360° setelah mulai mengejar). Akuisisi awal di IDLE/PATROL **tetap FOV** (realistis) — sesuai keputusan Aer.

**File berubah:**
- `src/MonsterAI/TargetFinder.luau` — param `ignoreFOV` mengalir ke `_hasLineOfSight`/`findNearest`/`findItemHolder`/`acquireTarget`.
- `src/MonsterController.server.luau` — `evaluateRetarget` prioritas holder instan, helper `reacquireOrPatrol`, dipakai di CHASING & ATTACKING.

**Verifikasi:** ad-hoc lokal (struktural 2/2, marker 11/11, sim logika 5/5 — T1 bug report → SWITCH_HOLDER) + Studio (3 script COMPILE_OK, source match, Attribute monster terbaca). **Belum playtest** (Aer yang tes).

---

### Entri #1 — Chasing mode selectable (3 mode) · commit `5c400ad` → refactor `63e6b67`
**Fitur/Task:** Task #10 NPC Monster Script — tambah pilihan mode pengejaran monster.

**Yang dikerjakan:**
- **3 chase mode** dipilih per-monster via Attribute `ChaseMode` (String) di Model, fallback ke `Config.ChaseMode`:
  - **PERSISTENT** — kunci 1 target sampai MATI/hilang; abaikan jarak & LOS; Safe Zone tetap dihormati. `PersistentGiveUpTime=0` = kejar selamanya.
  - **NEAREST** (default) — kejar terdekat, retarget dinamis dengan anti-thrash.
  - **ITEM_HOLDER** — prioritas pemegang Tool ber-Attribute `MonsterBait=true` (nama Tool bebas), fallback ke NEAREST bila tak ada holder.
- **Anti-thrash 3 lapis** (mencegah monster "di-main-mainin" 2 player oper-operan): commit time 2.5s + hysteresis 30%/8studs + interval 1s. Dipakai di NEAREST & ITEM_HOLDER, TIDAK di PERSISTENT.
- **ITEM_HOLDER pakai Attribute `MonsterBait`** (bukan match nama Tool) — lebih fleksibel, banyak item beda bisa memicu monster cukup dengan tag Attribute.

**Parameter Config (di-tune sendiri oleh Aer):**
`ChaseMode`, `BaitAttribute="MonsterBait"`, `PersistentGiveUpTime=0`, `RetargetCommitTime=2.5`, `RetargetInterval=1.0`, `RetargetHysteresis=0.30`, `RetargetMinGap=8`.

**Verifikasi:** struktural + compile-check Studio + 8 behavioral test (8/8 lulus).

---

## 📌 Cara pakai fitur Monster AI (referensi cepat)

1. **Pilih mode per-monster:** set Attribute `ChaseMode` (String) di Model monster → `PERSISTENT` / `NEAREST` / `ITEM_HOLDER`. Kosong = pakai default `Config.ChaseMode`.
2. **Tag item umpan (mode ITEM_HOLDER):** kasih Attribute `MonsterBait` (Bool, centang) di Tool umpan. Nama Tool bebas, bisa banyak item.
3. **Tune angka:** semua di `src/MonsterAI/Config.luau` (blok CHASE MODE & ANTI-THRASH).
4. **Perilaku deteksi:** akuisisi awal (IDLE/PATROL) pakai FOV realistis; begitu sudah mengejar → deteksi 360°.

---

## 🐞 Catatan bug diketahui (harmless)

- **Bug #6** — `SafeZoneManager` mutasi return API. Belum diubah, tapi harmless (`GetTagged` return array baru + guard `table.find`).
