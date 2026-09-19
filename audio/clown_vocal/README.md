# Vokal Badut — suara dari mulutnya sendiri

26 file CC0 (public domain, tanpa atribusi), 5.8 MB. Ini **beda lapisan** dari
`audio/chase/`: yang di sana musik & sting untuk telinga pemain, yang di sini
keluar dari badan badutnya.

Karena keluar dari badan, semuanya harus **3D positional** — taruh `Sound` di
dalam `Hitbox.HumanoidRootPart`, bukan di `SoundService`. Jadi pemain bisa
mendengar dari arah mana suaranya datang, dan itu bagian dari ketegangannya.

| Folder | Kapan | Isi |
|---|---|---|
| `notice/` | baru sadar ada pemain | 4 |
| `shriek/` | jeritan saat menemukan/menyerang | 4 |
| `laugh/` | tawa sambil mengejar | 5 |
| `vocal/` | geraman/erangan selama mengejar | 4 |
| `breath/` | napas ngos-ngosan (badan gendut) | 4 |
| `growl/` | geram peringatan, monster dekat | 5 |

## Dengar dulu

Reel di `_preview/`, satu per momen. **Jumlah pip = nomor klip.** Urutan di
`_preview/URUTAN.json`.

## Yang perlu kamu tahu

**Aku pakai penyaring "apakah ini benar suara mulut".** Musik dan mesin bisa
lolos kalau cuma dinilai dari bass — pelajaran dari paket badut sebelumnya, di
mana rekaman kemacetan lalu lintas hampir menang di kategori klakson. Jadi tiap
aset kuukur *harmonisitas*-nya: seberapa kuat pola periodik di gelombangnya.
Pita suara menghasilkan pola berulang yang rapi; noise dan mesin tidak. Nilai di
bawah 0.30 kupenalti. Semua yang masuk paket ini di atas itu.

**Angka f0 tidak kulaporkan untuk geraman, karena pengukurku salah di sana.**
14 dari 169 aset terbaca "900 Hz" — persis nilai batas atas pencarianku. Kucek
ulang dengan rentang diperluas: 9 dari 10 tetap 900. Itu bukan pitch, itu
argmax yang mendarat di ujung rentang karena periode aslinya lebih panjang dari
yang kucari. `Monster Low Rumble` centroid-nya 34 Hz — jelas sangat rendah — tapi
f0-nya terbaca 900. Kontradiksi itu bukti alat ukurnya, bukan audionya. Jadi
untuk kategori ini aku pakai **centroid** (statistik agregat, sudah terverifikasi
akurat 2.6% di uji pitch-shift sebelumnya).

**Tawa badut tetap tipis, sama seperti temuan sebelumnya.** `laugh_clown_01`
centroid 704 Hz. Yang paling berat justru `laugh_spooky` (435 Hz) yang bukan
ber-tag clown. Kalau mau badut tapi berat: turunkan `PlaybackSpeed` ke 0.7 —
terukur, seluruh spektrum menyusut proporsional, tapi durasinya memanjang 1/0.7.

**`growl_rumble` centroid 34 Hz itu sangat rendah.** Bagus untuk kesan raksasa,
tapi frekuensi segitu hilang di speaker laptop dan HP. Kalau target pemainnya
mobile, `growl_large` (63 Hz) atau `growl_short` (137 Hz) lebih aman.

## Pemetaan yang kusarankan

```lua
-- Semua Sound diparent ke HumanoidRootPart = 3D positional
AISignal "TargetAcquired" -> notice/  (one-shot)
AIState  = CHASING        -> laugh/ atau vocal/ (loop atau acak berjeda)
                             + breath/ sebagai layer terus-menerus
AISignal "Attack"         -> shriek/
AIState  = PATROL/IDLE    -> growl/ sesekali (bikin pemain tahu dia dekat)
AISignal "TargetLost"     -> growl/ (kesal kehilangan jejak)
```

`RollOffMaxDistance` sekitar 60–80 studs untuk vokal — badut segede itu harus
kedengaran sebelum kelihatan.

## Belum dikerjakan

- Belum upload ke Roblox. Sebut nomor yang lolos.
- Belum ada script. Pemetaan di atas sketsa, bukan file.
- Belum di-commit.

## Lisensi

26/26 diverifikasi CC0 dengan membuka halaman Freesound-nya. Kredit pembuat di
`MANIFEST.json`.
