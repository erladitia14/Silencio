# SFX Kejar-kejaran — momen ketauan & dikejar

28 file CC0 (public domain, tanpa atribusi), 24.6 MB. Dari Freesound.

Dipecah **per momen**, bukan satu tumpukan, karena kriteria tiap peran beda:

| Folder | Dipicu oleh | Sifat yang dicari |
|---|---|---|
| `detect/` | `AISignal` → `"TargetAcquired"` | one-shot, attack tajam, pendek |
| `chase/` | `AIState` = `"CHASING"` | loop mulus, ritmis |
| `heartbeat/` | jarak monster (layer) | periodik 50–130 bpm |
| `drone/` | monster dekat tapi belum lihat | energi rata, bisa di-loop |
| `alarm/` | opsional, ketauan gaya karnaval | periodik, keras |
| `relief/` | `AISignal` → `"TargetLost"` | energi menurun |

Semua sinyal itu **sudah** diterbitkan `EnemyController` — sound handler nanti
murni listener, nol perubahan di core AI. Sama polanya dengan animasi.

## Dengar dulu

Reel di `_preview/`, satu per momen. **Jumlah pip = nomor klip.** Loop dipotong
14 detik, one-shot dibiarkan penuh. Urutan di `_preview/URUTAN.json`.

## Yang perlu kamu tahu

**Juara otomatis di kategori `chase` itu chiptune.** "Playground Runaround"
(skor 98) loop-nya paling mulus — gap cuma 0.8 dB — tapi tag-nya 8bit/80s/90s.
Karakternya arcade, bukan horror karnaval. Kutaruh paling bawah (`chase_8bit`)
kalau ternyata kamu mau gaya retro. Yang kutaruh di atas: `chase_dark_action`
(tag action+chase+dark+drone, 10.5rb unduhan) dan `chase_maze` (gap 0.0 dB,
bass 0.87).

**Kategori `relief` lemah, dan aku tidak mau memaksakan.** Dari 37 kandidat CC0,
cuma satu yang benar-benar relevan (`relief_1`, "breathe.mp3", skor 100).
Sisanya latihan vokal dan efek transisi trailer — kusertakan supaya kamu bisa
menilai sendiri, tapi jujur: **untuk momen lolos, lebih baik hentikan musik
kejar dengan fade-out daripada memutar aset yang salah.** Keheningan mendadak
setelah musik intens itu efeknya lebih kuat dari sting apa pun.

**`detect/` sengaja kucampur karakter.** Skor teratas semuanya seri "Riser Hit
sfx" dari satu uploader dengan tag identik — empat file mirip itu pilihan
sempit. Kuambil satu yang terbaik (`detect_riser_hit`, puncak di 11% durasi,
crest 13.1) lalu tiga karakter berbeda: boom sinematik, braam ala Inception, dan
piano stinger yang bernada.

## Cara pakai (belum kubuat scriptnya)

Sketsa pemetaannya, supaya kamu tahu arahnya:

```lua
-- Server: listener murni, tidak menyentuh EnemyController
local sig = monster:WaitForChild("AISignal")
sig.Event:Connect(function(kind)
    if kind == "TargetAcquired" then
        detectSting:Play()          -- one-shot dari detect/
    elseif kind == "TargetLost" then
        chaseMusic:Stop()           -- fade-out lebih baik
    end
end)

monster:GetAttributeChangedSignal("AIState"):Connect(function()
    if monster:GetAttribute("AIState") == "CHASING" then
        chaseMusic.Looped = true
        chaseMusic:Play()
    end
end)
```

Musik kejar sebaiknya **2D** (di `SoundService`, bukan di part) supaya tidak
mengecil saat pemain kabur. Sting deteksi juga 2D. Heartbeat/drone yang
dipetakan ke jarak — itu client-side, mirip `DamageEffect` yang sudah ada.

## Belum dikerjakan

- **Belum upload ke Roblox.** Bilang nomor mana yang lolos.
- **Belum ada script.** Sketsa di atas bukan file — belum ditulis, belum diuji.
- Belum di-commit (24.6 MB biner, keputusanmu).

## Lisensi

28/28 aset diverifikasi CC0 dengan membuka halaman Freesound-nya satu per satu.
Kredit pembuat tercatat di `MANIFEST.json` sebagai etika, bukan kewajiban.
