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
-- Kosongkan ("") kalau tidak mau pakai animasi sama sekali.
Config.PanelCarryAnimId = "rbxassetid://71893510212987"

-- PANEL di-weld ke TENGAH DEPAN badan (HumanoidRootPart), bukan satu tangan,
-- supaya cocok dengan pose angkat 2 tangan. Offset relatif ke HumanoidRootPart.
-- CATATAN posisi (biar gampang tune sendiri):
--   Sumbu 1 (X) : geser KIRI(-)/KANAN(+)
--   Sumbu 2 (Y) : geser TURUN(-)/NAIK(+)
--   Sumbu 3 (Z) : -Z = MAJU ke depan badan, +Z = mundur
--   Angles(pitch X, yaw Y, roll Z) dalam radian (math.rad(derajat))
-- PanelCarryOffset: HASIL PENGUKURAN LANGSUNG DARI PLAYTEST AER (19 Sep 2026).
-- Diukur saat Aer memposisikan panel paling pas di tangannya:
--   Posisi: X = +0.21 (sedikit kanan), Y = +1.20 (setinggi dada/bahu), Z = -1.84 (di depan tangan)
--   Sudut: pitch = -7.8°, yaw = -6.3°, roll = 1.8°
Config.PanelCarryOffset = CFrame.new(0.207, 1.198, -1.844) * CFrame.Angles(math.rad(-7.8), math.rad(-6.3), math.rad(1.8))

-- ============================================================
-- ENGINE CO-OP CARRY (1 ORANG VS 2 ORANG)
-- Diukur langsung dari posisi Rig Left & Rig Right buatan Aer (19 Sep 2026).
-- ============================================================

Config.EngineSoloSpeed = 8                 -- WalkSpeed saat engine dibawa 1 orang (lambat)
Config.EngineCoopSpeed = 14                -- WalkSpeed saat engine dibawa 2 orang (cepat)

-- Animasi Engine Carry per sisi
Config.EngineLeftAnimId = "rbxassetid://87931635446245"
Config.EngineRightAnimId = "rbxassetid://124217715255364"

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
