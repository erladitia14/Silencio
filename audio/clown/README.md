# SFX Badut — paket audio Silencio

33 file, semuanya **CC0 / public domain** (bebas pakai komersial, tanpa
atribusi). Diambil dari Freesound, bukan Creator Store Roblox — jadi kamu yang
meng-upload, dan asset ID-nya milik akun kita sendiri.

Kenapa bukan dari Toolbox: pencarian audio Creator Store dari MCP mengembalikan
hasil sampah untuk kata kunci ini (klakson badut → rekaman kemacetan lalu
lintas). Freesound punya filter lisensi CC0 yang bisa diandalkan, dan setiap
aset di sini sudah diverifikasi CC0 dengan membuka halaman aslinya.

## Cara cepat memilih

Dengar reel di `_preview/` — satu file per kategori, semua kandidat berurutan.
**Jumlah pip di awal tiap klip = nomor klip.** Urutan lengkapnya di
`_preview/URUTAN.json`.

| Reel | Isi | Durasi |
|---|---|---|
| `reel_laugh.mp3` | 7 tawa | 47s |
| `reel_footstep.mp3` | 5 langkah berat | 33s |
| `reel_breath.mp3` | 4 napas | 39s |
| `reel_growl.mp3` | 4 geraman | 15s |
| `reel_hit.mp3` | 4 impact/jumpscare | 23s |
| `reel_clownhorn.mp3` | 5 klakson badut | 28s |
| `reel_ambience.mp3` | 4 musik karnaval | 44s |

Bilang nomornya, sisanya aku urus.

## Yang perlu kamu tahu sebelum memilih

**Tawa badut asli semuanya tipis.** Ini temuan yang mengubah rencana: dari 44
kandidat tawa CC0, yang benar-benar ber-tag `clown` semuanya ber-pitch 300–630 Hz
— badut kecil yang ceria, bukan badut gendut. Yang pitch-nya rendah justru bukan
tawa badut (geraman monster, suara runtuhan).

Jadi ada dua jalur, dan dua-duanya kusiapkan:

- `laugh_deepman_*`, `laugh_monster`, `laugh_darkhall` — sudah berat dari asalnya
  (f0 80–101 Hz). Tidak perlu diapa-apakan.
- `laugh_clown_*` — tawa badut asli yang **sudah kuturunkan pitch-nya**
  (0.7×/0.75×). File di folder ini adalah versi yang sudah diproses, jadi
  `PlaybackSpeed` di Roblox biarkan `1`.

**Langkah kaki: hati-hati yang metalik.** Lima skor akustik teratas semuanya
"Big robot footstep" — bass-nya bagus tapi tag-nya clang/clank/metal. Untuk
badut dari daging itu salah karakter. Yang kutaruh di urutan atas
(`step_thud_A`, `step_thud_B`, `step_floor`) gedebuk tumpul tanpa denting.
`step_robot` tetap kusertakan kalau ternyata badutnya memang mekanis.

**Klakson badut memang cerah, dan itu wajar.** Skor akustikku menaruh rekaman
kemacetan India di puncak kategori ini karena bass-nya besar — jelas salah.
Klakson badut centroid-nya 1200–2900 Hz, dan kontras cerah-di-atas-suara-berat
itu justru yang bikin serem. Pilihan di sini murni dari tag, bukan skor.

## Isi paket

```
audio/clown/
├── laugh/        7 file   tawa
├── footstep/     5 file   langkah berat
├── breath/       4 file   napas ngos-ngosan
├── growl/        4 file   geraman
├── hit/          4 file   impact & jumpscare
├── clownhorn/    5 file   klakson badut
├── ambience/     4 file   musik karnaval
├── _preview/     7 reel + URUTAN.json
└── MANIFEST.json          metadata lengkap tiap file
```

Nama file: `nama__fs<freesound_id>.mp3`. ID itu bisa kamu pakai untuk membuka
halaman asalnya (`freesound.org/s/<id>`) kalau mau cek sendiri.

Yang berakhiran `__x0.7` / `__x0.75` / `__x0.6` = sudah diturunkan pitch-nya.

`MANIFEST.json` memuat, per file: judul asli, pembuat, link halaman, lisensi,
durasi, dan ukuran akustik (centroid, bass ratio, f0) plus alasan kenapa dia
masuk daftar.

## Cara pakai di Roblox

Upload dulu (belum kulakukan — butuh persetujuanmu, lihat catatan di bawah), lalu:

```lua
local s = Instance.new("Sound")
s.SoundId = "rbxassetid://<ID_HASIL_UPLOAD>"
s.RollOffMaxDistance = 80      -- badut besar harus kedengaran dari jauh
s.RollOffMode = Enum.RollOffMode.InverseTapered
s.Parent = hitbox.HumanoidRootPart   -- di dalam BasePart = 3D positional
s:Play()
```

Kalau mau menurunkan pitch lagi tanpa file baru: `s.PlaybackSpeed = 0.8`.
Terukur di mesin ini — seluruh spektrum menyusut tepat sebesar faktornya
(galat rata-rata 2.6%), dan **durasinya memanjang** 1/faktor. Jadi 0.7× membuat
klip 3.6s jadi 5.1s. Itu konsekuensi yang tidak bisa dihindari dengan
`PlaybackSpeed`; kalau durasi harus tetap, butuh pitch-shift beneran di DAW.

## Batas impor Roblox (sudah diverifikasi semua file lolos)

- < 20 MB, < 7 menit, sample rate ≤ 48 kHz → semua file di sini jauh di bawah
  batas (terbesar 1.97 MB / 86s)
- Akun **ID-verified**: 2000 impor audio per 30 hari. Belum verified: 100.
- Audio yang kamu upload otomatis privat. Untuk dipakai tim, kamu harus memberi
  izin ke experience-nya lewat asset privacy system.

## Belum dikerjakan

- **Upload ke Roblox belum kulakukan.** 33 aset akan memakan kuota impor
  bulananmu dan asset ID-nya menempel permanen ke akun. Bilang mau yang mana
  saja, aku upload yang itu — atau bilang "upload semua" kalau memang mau.
- Belum ada script yang memutarnya. `EnemyController` sudah menerbitkan
  `AIState` + `AISignal`, jadi sound handler bisa dibuat sebagai listener tanpa
  menyentuh core AI sama sekali.

## Lisensi

Semua 32 aset unik terkonfirmasi CC0 dengan membuka halaman Freesound-nya
satu per satu (32/32 lolos). CC0 = public domain, tidak wajib atribusi, boleh
komersial. Kredit pembuatnya tetap tercatat di `MANIFEST.json` sebagai etika,
bukan kewajiban hukum.
