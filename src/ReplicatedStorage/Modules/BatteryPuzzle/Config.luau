--!strict
--[[
	Config — Battery Puzzle (Control Room 3)
	Semua angka yang bisa di-tune ada di sini. Modul lain membaca dari sini.
]]

local Config = {}

-- ============================================================
-- IDENTIFIKASI (pakai CollectionService tag — tahan rename)
-- ============================================================

Config.CaseTag = "BatteryCase"          -- Model wadah baterai
Config.SlotTag = "BatterySlot"          -- BasePart placeholder = titik pasang
Config.PickupTag = "BatteryPickup"      -- BasePart baterai yang bisa diambil

-- ============================================================
-- 1. BERAT — bawa baterai jadi lambat
-- ============================================================

-- BATERAI (kecil) — masih bisa lari, cuma sedikit lebih lambat.
Config.CarryWalkSpeedMultiplier = 0.9   -- 0.9x kecepatan normal pemain (bukan angka tetap)

-- ENGINE / PANEL (berat) — jauh lebih lambat, angka tetap.
Config.CarryWalkSpeed = 8               -- dari default 16 -> setengah
Config.CarryJumpPower = 30              -- dari default 50
Config.RestoreSpeedOnDrop = true        -- pulihkan ke nilai SEBELUM bawa

-- Tombol untuk MENARUH (store/drop) item yang sedang dibawa.
Config.StoreKey = Enum.KeyCode.Q

-- Animasi "pose angkat 2 tangan" — HANYA saat membawa PANEL.
-- Baterai (kecil) & Engine TIDAK pakai animasi ini.
--
-- Aer (23 Sep 2026): "animnya pake default roblox aja gitu maksud gua gausah ada
-- carry pose dll" -> SEMUA animasi carry DIKOSONGKAN. Karakter memakai animasi
-- bawaan Roblox (idle / walk / run) seperti biasa; panel tetap terbawa karena
-- di-weld ke HumanoidRootPart, jadi TIDAK butuh animasi sama sekali.
-- CarryAnimator.play() langsung `return` kalau ID kosong -> aman, tidak error.
Config.PanelCarryAnimId = ""

-- PANEL di-weld ke HumanoidRootPart (bukan satu tangan).
-- CATATAN posisi (biar gampang tune sendiri):
--   Sumbu 1 (X) : geser KIRI(-)/KANAN(+)
--   Sumbu 2 (Y) : geser TURUN(-)/NAIK(+)
--   Sumbu 3 (Z) : -Z = MAJU ke depan badan, +Z = mundur
--   Angles(pitch X, yaw Y, roll Z) dalam radian (math.rad(derajat))
--
-- ===== PANEL DIBAWA REBAH DI ATAS KEPALA (23 Sep 2026) =====
-- KENAPA DI ATAS KEPALA: game ini FPP. Posisi lama (Z = -1.84) menaruh panel
-- TEPAT DI DEPAN MATA -> menutup pandangan. Di atas kepala (Z = 0) pandangan
-- depan bebas.
--
-- KENAPA HARUS REBAH (rotasi -90 derajat X), BUKAN DITEGAKKAN:
--   Diukur pada rig R15 (angka nyata, bukan perkiraan):
--     - jangkauan lengan (sendi bahu -> telapak) = 1.803 stud
--     - puncak kepala (rel HumanoidRootPart)     = 2.187 stud
--     - tinggi maks telapak (lengan lurus ke atas) = 2.756 stud
--     - Panel Size = 4.873 x 3.580 x 0.054 (tipis, bidang di sumbu Z)
--   Kalau TEGAK di atas kepala: dasar panel harus >= 2.187, jadi panel
--   berpusat di Y >= 2.187 + 3.580/2 = 3.977. Attachment-nya lalu berjarak
--   3.263 stud dari sendi bahu -> BUTUH reach 1.81x lipat kemampuan lengan.
--   MUSTAHIL: tangan tidak akan pernah sampai, IK akan memaksa lengan
--   melar/melintang.
--   Kalau REBAH: bentang panel jadi horizontal (tebal 0.054 -> sumbu Y),
--   attachment berjarak 1.54-1.59 stud -> MASIH TERJANGKAU.
--
-- JENDELA AMAN hasil sweep (kedua syarat: tidak nabrak kepala DAN terjangkau):
--   Y = 2.265 .. 2.670 stud.
--
-- Y = 2.55 (naik dari 2.45, 23 Sep 2026): Aer minta panel "aga kurang ke atas
-- dikit lagi, gua mau pas di telapak tangannya". Referensinya (Dead Rails):
-- telapak rata menahan panel dari bawah, lengan SEDIKIT nekuk (tidak lurus
-- penuh). Persentase panjang lengan yang terpakai:
--     2.45 -> 88.2%  (lengan masih terlalu nekuk)
--     2.55 -> 93.5%  <- dipilih, paling dekat dengan referensi
--     2.60 -> 96.1%
--     2.67 -> 99.8%  (lengan lurus penuh, mentok jangkauan -> jangan)
-- Naikkan lagi kalau masih kurang, tapi JANGAN lewat 2.67.
Config.PanelCarryOffset = CFrame.new(0, 2.55, 0) * CFrame.Angles(math.rad(-90), 0, 0)

-- ============================================================
-- PENEMPATAN PANEL SAAT DI-STORE (tombol Q) — 23 Sep 2026
-- ============================================================
-- MASALAH YANG DIPERBAIKI: jalur drop lama menaruh panel memakai ROTASI BADAN
-- pemain apa adanya (tegak), jadi panel berdiri seperti TEMBOK setinggi 3.58
-- stud dengan tebal hanya 0.054 stud — mustahil berdiri wajar — lalu di-anchor.
-- Dasar panel juga TENGGAM ke terrain (terukur 0.10 stud) karena posisinya
-- dihitung dari tinggi badan, bukan dari permukaan tanah.
--
-- SOLUSI: pakai rotasi REBAH yang SAMA seperti waktu dibawa (PanelCarryOffset
-- memutar -90 derajat di sumbu X), tapi diratakan ke permukaan tanah:
--   sumbu lokal X (bentang 4.873) -> melintang mengikuti arah hadap pemain
--   sumbu lokal Y (bentang 3.580) -> searah hadap pemain (maju/mundur)
--   sumbu lokal Z (tebal  0.054) -> VERTIKAL  => panel rebah rata
-- Tinggi diambil dari RAYCAST ke tanah, jadi aman di terrain miring.
Config.PanelDropFlat = true        -- false = kembali ke perilaku lama (panel tegak)
Config.PanelDropDistance = 3       -- jarak titik jatuh di depan pemain (stud)
Config.PanelDropGroundGap = 0.03   -- celah tipis di atas tanah (anti z-fighting)

-- ============================================================
-- ENGINE CO-OP CARRY (1 ORANG VS 2 ORANG)
-- Diukur langsung dari posisi Rig Left & Rig Right buatan Aer (19 Sep 2026).
-- ============================================================

Config.EngineSoloSpeed = 8                 -- WalkSpeed saat engine dibawa 1 orang (lambat)
Config.EngineCoopSpeed = 14                -- WalkSpeed saat engine dibawa 2 orang (cepat)

-- Animasi Engine Carry per sisi.
-- Aer (23 Sep 2026): pakai animasi default Roblox saja -> DIKOSONGKAN.
-- (EngineLeftAnimId lama 87931646245 sudah 404/tidak ada di Roblox.)
Config.EngineLeftAnimId = ""
Config.EngineRightAnimId = ""

-- Offset relatif Engine terhadap HumanoidRootPart masing-masing carrier
Config.EngineLeftCarryOffset = CFrame.new(0.145, -1.266, -3.298) * CFrame.Angles(0, math.rad(90), 0)
Config.EngineRightCarryOffset = CFrame.new(-0.145, -1.266, -2.958) * CFrame.Angles(0, math.rad(-90), 0)

-- ============================================================
-- IK TANGAN KE ATTACHMENT (biar tangan SELALU nempel walau
-- ukuran badan / panjang lengan pemain berbeda-beda)
-- ============================================================
-- Animasi R15 menyimpan SUDUT sendi, jadi tangan pemain bertubuh
-- besar/kecil bisa meleset dari Attachment Engine. IKControl
-- menyelesaikannya: Roblox menghitung sendiri sudut bahu/siku
-- supaya TELAPAK TANGAN menyentuh titik Attachment.
--
-- Urutan eksekusi Roblox: Animasi dulu -> baru IKControl.
-- Karena itu IK TIDAK bertabrakan dengan animasi; ia hanya
-- memenangkan lengan, sedangkan kaki tetap dari animasi jalan.
Config.UseHandIK = true
Config.IKWeight = 1.0                      -- 0 = mati, 1 = penuh

-- ============================================================
-- IK TANGAN UNTUK PANEL (23 Sep 2026)
-- ============================================================
-- Aer menambahkan 2 Attachment di setiap Panel (Panel_01 & Panel_02) sebagai
-- titik pegang tangan. Sebelumnya attachment itu TIDAK dibaca kode sama
-- sekali: jalur Panel hanya memakai weld + offset (PanelCarryOffset), jadi
-- attachment-nya menganggur.
--
-- Attachment Panel TIDAK memakai pola "<Sisi>(<Tangan>)" seperti Engine
-- (karena Panel dibawa 1 orang, tidak ada sisi carrier). Namanya polos
-- "Left" dan "Right", jadi HandIK.attach() yang berbasis pola akan
-- MELEWATKANNYA DIAM-DIAM. Karena itu dipakai HandIK.attachBoth() yang
-- menerima Attachment secara eksplisit.
--
-- Sisi ditentukan dari POSISI X, bukan dari nama: attachment dengan X lebih
-- kecil (paling kiri di ruang lokal part) dipasangkan ke LeftArm. Ini sekaligus
-- MENORMALKAN Panel yang attachment-nya tertukar — ditemukan pada Panel_02
-- (Left X=+1.736, Right X=-1.764, terbalik dibanding Panel_01). Kalau memakai
-- nama apa adanya, tangan akan menyilang.
-- Aer (23 Sep 2026): "gausah di timpa anim itu aja bisa ngga?" lalu "gua mau tetep
-- tangannya megang ke atas bro bisa ngga?" -> IK DIBIARKAN NYALA.
--
-- Jadi: TIDAK ada animasi carry pose (badan/kaki pakai animasi DEFAULT Roblox),
-- tapi TANGAN TETAP DIANGKAT & menempel ke Attachment Panel — itu kerjaan
-- IKControl, bukan animasi. IKControl dievaluasi SETELAH animasi, jadi ia
-- menang untuk lengan saja; kaki tetap dari animasi default.
--
-- Inilah kenapa animasi + IK itu DUA hal terpisah:
--   PanelCarryAnimId  = pose badan/gerak (sekarang kosong -> default Roblox)
--   UsePanelHandIK    = lengan diangkat ke Attachment (sekarang true)
Config.UsePanelHandIK = true
-- Type IK: Position = telapak ditarik ke TITIK attachment, rotasi pergelangan
-- dibiarkan natural (anti-nekuk). Sama seperti Engine.
Config.PanelIKType = Enum.IKControlType.Position
Config.PanelIKWeight = 1.0                 -- 0 = mati, 1 = penuh
-- Type IK:
--   Position  = tangan ditarik ke TITIK attachment, rotasi pergelangan NATURAL (default, anti-nekuk)
--   Transform = tangan ikut posisi + ORIENTASI attachment (perlu attachment yang diputar pas)
Config.IKType = Enum.IKControlType.Position
Config.IKChainLength = 2                   -- 2 sendi: Bahu + Siku (UpperArm, LowerArm)

-- Suffix nama Attachment di Engine: "<Sisi>(<Tangan>)"
-- Contoh: "Left(LeftArm)", "Right(RightArm)"
Config.IKAttachmentSides = { Left = "Left", Right = "Right" }

-- Offset halus titik IK terhadap Attachment (kalau perlu digeser tipis).
Config.IKPositionOffset = Vector3.new(0, 0, 0)

-- Offset bawa tangan satu (baterai kecil)
Config.HandCarryOffset = CFrame.new(0, -0.6, -0.4) * CFrame.Angles(math.rad(90), 0, 0)

-- ============================================================
-- 2. WAKTU PASANG — harus diam, gak bisa gerak
-- ============================================================

Config.InsertDuration = 1.0             -- detik tahan prompt (dipercepat dari 2.0)
Config.CancelInsertOnMove = false       -- true = batal kalau pemain jalan
Config.CancelInsertOnDamage = true      -- batal kalau kena damage

-- ============================================================
-- 3. INTERUPSI — baterai JATUH, bukan hilang
-- ============================================================

Config.DropOnDamage = true
Config.DropCooldown = 1.5               -- detik, cegah drop beruntun
Config.DroppedBatteryLifetime = 0       -- 0 = selamanya (jangan hilang!)

-- ============================================================
-- 4. SATU TANGAN — gak bisa pakai item lain
-- ============================================================

Config.MaxCarry = 1                     -- 1 baterai per pemain
-- Attribute yang diterbitkan ke Character saat membawa baterai.
-- Sistem lain (mis. flashlight) boleh MEMBACA ini untuk memblokir item.
-- Modul ini TIDAK mengubah script sistem lain.
Config.CarryingAttribute = "CarryingBattery"

-- ============================================================
-- 5. FAILURE & RECOVERY — puzzle tidak boleh macet
-- ============================================================

Config.ReturnOnDeath = true             -- baterai balik ke posisi awal
Config.ReturnOnLeave = true             -- pemain keluar server
Config.ReturnOnRespawn = true
Config.KeepBatteryOnDeath = false       -- false = kembali ke spawn

-- ============================================================
-- INTERAKSI
-- ============================================================

Config.PickupPromptText = "Pick Up"
Config.InsertPromptText = "Insert"
Config.PickupPromptDistance = 8
Config.InsertPromptDistance = 8
Config.PickupPromptKey = Enum.KeyCode.E
Config.InsertPromptKey = Enum.KeyCode.E
Config.RequireLineOfSight = false

-- ============================================================
-- VISUAL SAAT DIBAWA
-- ============================================================

-- Baterai asli TIDAK diubah ukurannya (biar tetap pas dengan slot).
-- Kalau perlu dikecilkan saat dibawa, set < 1. 1 = tidak diubah.
Config.CarryVisualScale = 1.0
Config.CarryOffset = CFrame.new(0, -0.6, -1.6)   -- relatif ke HumanoidRootPart
Config.HideOriginalWhileCarried = true           -- sembunyikan mesh asli, tampilkan salinan

-- ============================================================
-- PROGRESS
-- ============================================================

Config.CompletedAttribute = "BatteryPuzzleComplete"   -- di-set di Model case
Config.ProgressAttribute = "BatteryPuzzleProgress"    -- "2/4"
Config.BroadcastProgress = true         -- kirim progress ke semua client

-- ============================================================
-- DEBUG
-- ============================================================

Config.Debug = false
function Config.log(...: any)
	if Config.Debug then
		print("[BatteryPuzzle]", ...)
	end
end

return Config
