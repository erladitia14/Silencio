# Referensi — Quiz/Challenge Control Room 3 (Baterai Warna-Warni)

Riset referensi untuk fitur **Control Room 3**: ruang kontrol berisi puzzle baterai warna-warni +
tantangan quiz. Dipisah jadi 3 bagian sesuai permintaan: **Concept**, **Script**, **UI**.

---

## 1. CONCEPT — Referensi Desain Puzzle "Control Room"

### 1.1 Control Room Puzzle (trope)
- **TV Tropes — Control Room Puzzle**: <https://tvtropes.org/pmwiki/pmwiki.php/Main/ControlRoomPuzzle>
  - Definisi: ruangan penuh switch/panel, hanya 1 konfigurasi yang benar.
  - **Peringatan penting dari halaman ini**: jangan sampai ruangan jadi *unwinnable by design*
    (pemain salah sekali → gak bisa balik / switch gak bisa di-reverse).
  - **Aksi untuk Silencio**: WAJIB ada tombol **Reset** di ruang kontrol.

### 1.2 Poppy Playtime — Battery + Control Room (referensi terdekat!)
Ini referensi paling nyambung karena **control room + baterai + panel listrik**.

| Referensi | Yang diambil |
|---|---|
| [Ch.4 — Battery in the Control Room](https://gamerant.com/poppy-playtime-chapter-4-find-door-battery-control-room/) | Baterai sebagai item yang di-*carry*, glow neon-hijau biar kelihatan di gelap, lalu di-insert ke panel → pintu kebuka |
| [Ch.5 — Biodiversity Labs Battery Puzzle](https://gamerant.com/poppy-playtime-chapter-5-biodiversity-labs-power-puzzle-battery-solution/) | **Dua slot baterai berdampingan** + switch di tengah. Alur: ambil baterai → insert → aktifkan switch → daya mengalir |
| [Ch.4 — The Doctor's 4 Batteries](https://itemlevel.net/poppy-playtime-the-doctor-4-batteries-hard-puzzle-solution-chapter-4-safe-haven/) | **Breaker box + Power Switcher + battery slot** yang disambung kabel. Pemain harus lacak kabel dari breaker → switcher → slot. Dikejar monster sambil ngerjain (persis pola Silencio!) |

**Pelajaran desain dari Poppy Playtime:**
- Baterai harus **glow** (neon) supaya kelihatan di ruangan gelap — bukan cuma objek matte.
- **Kabel sebagai petunjuk visual**: pemain tahu baterai ini nyambung ke mana dengan melihat kabelnya.
- Puzzle dikerjakan **sambil dikejar** → tekanan waktu = sumber horor, bukan puzzle-nya sendiri.

### 1.3 Zero Escape: Virtue's Last Reward — Control Room (referensi puzzle logika)
- <https://www.thegamer.com/zero-escape-virtues-last-reward-control-room-puzzle-guide-walkthrough/>
- Ruangan penuh panel, lever, dial. Puzzle warna: **hitung persentase tiap warna** di lapisan objek
  (kuning 25%, merah 20%, hijau 30%, biru 25%).
- **Pelajaran**: puzzle warna yang bagus = pemain harus **mengamati & menghitung**, bukan trial-error.

### 1.4 Pola "baterai warna" yang bisa ditiru
Dari [DevForum — electricity-themed grid puzzle](https://devforum.roblox.com/t/help-me-with-my-puzzle/3304549)
(developer bikin puzzle listrik untuk game horror, dapat feedback):

**Skema warna yang dipakai dev itu:**
```
Battery    : Merah
Conductor  : Hijau
Insulator  : Biru
Target     : Kuning
Powered    : Putih
Dynamic    : Oranye
Multiplier : Ungu
Reverser   : Cyan
```

**Masalah yang dia kena (hindari di Silencio):**
1. Puzzle bisa diselesaikan cuma dengan **klik 2 baterai** → terlalu gampang.
2. Bisa bikin state **mustahil diselesaikan** → wajib tombol reset.
3. Kesulitan naik tiap 5 langkah → malah bikin bingung, bukan seru.

**Solusi yang dia terapkan (bagus untuk ditiru):**
- Tiap baterai hanya bisa **diaktifkan sekali**.
- Sebagian konduktor berubah jadi insulator setelah dipakai (jadi puzzle makin sempit).
- Tombol **Reset Circuit** yang jelas kelihatan.

### 1.5 Referensi escape-room fisik (untuk mekanik "insert baterai")
- [Color Sequence Lock — Escape Room Integration Guide](https://crackandreveal.com/en/blog/color-sequence-lock-escape-room-integration-guide)
  → prinsip urutan warna + clue tersembunyi.
- [50 Escape Room Puzzle Ideas with Electronics](https://www.escaperoomsupplier.com/50-escape-room-puzzle-ideas-with-electronics/)
  → ide puzzle elektronik fisik yang bisa diterjemahkan ke 3D.
- [Macabre Manor (itch.io)](https://nurd.itch.io/macabre-manor) → escape room horror 3D, dokumentasi
  solusi tiap room lengkap. Bagus buat lihat **pacing** puzzle per ruangan.

---

## 2. SCRIPT — Referensi Implementasi Roblox

### 2.1 Template siap pakai (Creator Store)
- **[Battery Puzzle Template](https://create.roblox.com/store/asset/18431135024/Battery-Puzzle-Template)**
  oleh `@Sparked_bois` — template puzzle baterai Roblox. Bisa jadi titik awal, tapi **cek dulu**
  apakah logikanya cocok (jangan langsung comot; sistem Silencio pakai pola tag + Attribute).

### 2.2 Pola trigger → gate (backbone puzzle Silencio)
Dari [creation.dev — Roblox Puzzle Template](https://www.creation.dev/templates/puzzle-template):
- **Trigger framework modular**: pakai `ObjectValue` atau **Attribute** untuk menghubungkan
  trigger (tombol/plate/lever) ke target (pintu/platform).
- **Ini persis pola yang sudah dipakai KeySystem Silencio** (`LockedDoor`/`PowerSwitch`/
  `CarnivalLight` via Attribute) → konsisten, jangan bikin pola baru.

### 2.3 Contoh kode yang relevan
**Buka pintu dari tombol** (dari gameoll.com):
```lua
local button = script.Parent
local door = game.Workspace.Door
local function openDoor()
    door.Transparency = 1
    door.CanCollide = false
end
button.ClickDetector.MouseClick:Connect(openDoor)
```

**Toggle switch → ubah warna** (pola feedback visual):
```lua
local switch = script.Parent
local light = game.Workspace.Light
local isOn = false
local function switchToggle()
    isOn = not isOn
    if isOn then
        light.BrickColor = BrickColor.new("Bright green")
    else
        light.BrickColor = BrickColor.new("Really red")
    end
end
switch.ClickDetector.MouseClick:Connect(switchToggle)
```

### 2.4 Feedback wajib (dari panduan puzzle design)
Setiap aksi pemain HARUS ada respons instan:
- **Benar** → kilat hijau + chime positif
- **Salah** → kilat merah + buzzer
- **Puzzle selesai** → suara kemenangan + animasi pintu kebuka

Tanpa ini pemain gak tahu apa yang berhasil/gagal. **Kritis untuk Silencio** karena
ruangannya gelap.

### 2.5 Quiz system (kalau Control Room 3 pakai quiz)
- **[quizbot](https://github.com/Damian-11/quizbot)** — sistem quiz Roblox paling lengkap
  (kategori, poin, autoplay, filter chat). Tapi ini chat-based, bukan 3D.
- **[QuizBase + Roblox classroom guide](https://quizbase.runriva.com/docs/guides/roblox-classroom-experience)**
  — **INI YANG PALING RELEVAN** untuk quiz 3D. Polanya:
  - Pertanyaan tampil di **3D screen** (`SurfaceGui` di Part)
  - Pemain **berdiri di platform A/B/C/D** untuk menjawab
  - Skor dihitung **server-side** saat reveal (cek posisi `PrimaryPart` vs `platform.Position`)
  - Kode contoh lengkap ada di halaman itu (shuffle jawaban, scoring, teacher control)
- **Peringatan dari quizbot**: Roblox sangat sensitif filter chat — hindari soal berisi
  angka beruntun, nama tokoh kontroversial, atau peristiwa dunia.

### 2.6 ProximityPrompt (untuk interaksi insert baterai)
- [ProximityPrompt docs](https://create.roblox.com/docs/reference/engine/classes/ProximityPrompt)
- [ExpressivePrompts](https://devforum.roblox.com/t/expressiveprompts-customizable-proximityprompt-ui-with-animation-sound-and-more/4513598)
  — prompt custom dengan animasi & suara (opsional, kalau mau prompt lebih hidup).
- **Catatan Silencio**: `ProximityPrompt.Triggered` itu `RBXScriptSignal` (bukan BindableEvent) —
  gak bisa di-`:Fire()` untuk testing. Sudah pernah kena jebakan ini di SafeZone.

---

## 3. UI — Referensi Desain Antarmuka

### 3.1 Horror UI yang adaptif ke state gameplay
- **[Brendan Butterworth — Horror Gameplay UI System](https://www.brendanbutterworthportfolio.com/horror-gameplay-ui-system)**
  - UI berubah sesuai kondisi pemain, bukan statis.
  - **Health bar pecah jadi segmen + "bocor"** saat kritis → ide bagus untuk meter daya listrik.
  - **Off-hand UI**: flashlight → indikator baterai; item lain → sisa pemakaian; tangan kosong → UI hilang.
  - **Ini persis pola yang cocok untuk meter baterai Control Room 3.**

### 3.2 Battery depletion UI (langsung relevan)
- **[VHS & Analog Horror Camera GUI](https://thiff.itch.io/vhs-analog-horror-camera-gui)**
  - Animasi **battery depletion** dengan 3 warna: `#E2E5AE` (kuning pudar) → `#E09031` (oranye)
    → `#ED2D2C` (merah). **Palet ini bagus banget** untuk meter baterai warna-warni.
  - Ada demo scene Unity + script battery depletion (bisa dilihat logikanya).

### 3.3 Horror UI kit siap adaptasi
- **[CASE//FILE — Pixel Horror Investigation UI Kit](https://oddbitstudio.itch.io/case-file-ui-kit)**
  - Tema **1990s case files + CRT terminal + evidence room**. Cocok kalau Control Room 3
    bergaya "ruang kontrol tua dengan monitor CRT".
- **[RAIE Horror Game UI Concept (Dribbble)](https://dribbble.com/shots/22675197-RAIE-HORROR-GAME-UI-CONCEPT)**
  - PS1 aesthetic (Silent Hill / Resident Evil). Layout: sisi kiri layar **tetap** saat menu
    inventory kebuka → pemain tetap lihat depan. **Bagus untuk puzzle yang butuh lihat objek.**
- **[The Scourge — Game UI (Contra)](https://contra.com/p/WoR72lLP-the-scourge-game-ui)**
  - UI horror berbasis "restraint, legibility, atmosphere".
  - Ada **minigame UI** khusus — relevan karena puzzle = minigame.
- **[Galdrakona (Chiara Chiroli)](https://www.chiarachiroli.com/galdrakona-project/)**
  - **Color-coding untuk state objek**: glowing icon untuk aktif/nonaktif/terpakai.
  - Tujuan: kurangi beban kognitif pemain saat situasi tegang.

### 3.4 Database UI game (untuk cari referensi lebih lanjut)
- **[Game UI Database 2.0](https://gameuidatabase.com/)** — 1.300+ game, 55.000+ screenshot UI.
  Bisa difilter berdasarkan **kategori, animasi, warna, material, layout, genre**.
  Kalau butuh referensi meter/puzzle UI spesifik, cari di sini.

---

## 4. Rekomendasi untuk Silencio (ringkasan aksi)

### Concept
1. **3–4 slot baterai warna** (mis. merah/biru/kuning/hijau) di panel ruang kontrol.
2. Baterainya **glow** — pakai `Neon` material + `PointLight`, bukan Part matte.
3. **Kabel sebagai petunjuk visual** dari baterai → panel (pola Poppy Playtime).
4. **Tombol Reset wajib** (pelajaran dari TV Tropes + DevForum).
5. Puzzle dikerjakan **sambil dikejar badut** → pakai SafeZone/monster yang sudah ada.

### Script
1. Ikuti **pola tag + Attribute KeySystem** yang sudah jalan — jangan bikin sistem baru.
2. **Feedback wajib**: benar = kilat hijau + chime, salah = merah + buzzer.
3. Kalau ada quiz: pakai pola **QuizBase** (pertanyaan di 3D screen, jawab dengan berdiri di platform).
4. Hati-hati: `ProximityPrompt.Triggered` gak bisa di-simulate di test.

### UI
1. **Palet baterai** dari VHS Camera GUI: `#E2E5AE` → `#E09031` → `#ED2D2C`.
2. **Meter berbasis segmen** yang pecah/bocor saat daya kritis (pola Brendan Butterworth).
3. **Color-coding state**: glowing = aktif, redup = mati, kedip = error.
4. Gaya visual: CRT terminal tua (CASE//FILE) cocok dengan tema karnaval terbengkalai.

---

## 5. Catatan Riset & Status Link

**Hasil cek otomatis (22 link unik):**
- **13 link terverifikasi hidup** (HTTP 200/202) — bisa langsung dibuka.
- **9 link tidak bisa diverifikasi otomatis** — bukan berarti mati:

| Link | Kode | Artinya |
|---|---|---|
| TV Tropes, Game UI Database | 403 | Blokir bot (situsnya hidup, buka manual di browser) |
| GameRant ×2, TheGamer | koneksi ditutup | Blokir anti-scrape; buka manual |
| Roblox docs ProximityPrompt | 502 | Server Roblox lagi error sesaat |
| crackandreveal | 429 | Rate limit (keseringan diakses) |
| chiarachiroli | SSL error | Masalah sertifikat di sisi kita, bukan situsnya |
| contra.com | 404 | **Sudah diperbaiki** — ID typo (`WoR72lpLP` → `WoR72lLP`) |

**Link prioritas untuk dibaca duluan:**
1. [Poppy Playtime Ch.4 battery](https://gamerant.com/poppy-playtime-chapter-4-find-door-battery-control-room/) — concept
2. [Poppy Playtime Ch.4 4-batteries puzzle](https://itemlevel.net/poppy-playtime-the-doctor-4-batteries-hard-puzzle-solution-chapter-4-safe-haven/) — concept
3. [QuizBase classroom guide](https://quizbase.runriva.com/docs/guides/roblox-classroom-experience) — script 3D quiz
4. [VHS Camera GUI](https://thiff.itch.io/vhs-analog-horror-camera-gui) — UI meter baterai
5. [Battery Puzzle Template](https://create.roblox.com/store/asset/18431135024/Battery-Puzzle-Template) — Roblox Creator Store

**Belum diverifikasi:** isi/kualitas tiap sumber (baru status HTTP yang dicek). Kalau ada link
yang isinya gak nyambung atau mati, kabari — gua ganti.
