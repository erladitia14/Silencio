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
-- Tanpa rotasi = muka lebar panel ngadep depan (kayak nyangga papan besar).
-- Panel gede (4.87 stud) -> pasti nembus badan; sengaja dipeluk DEKAT di dada
-- biar keliatan "dipeluk 2 tangan", bukan ngambang jauh. Collision sudah mati
-- saat dibawa jadi tembusan tak mendorong physics.
Config.PanelCarryOffset = CFrame.new(0, 0.2, -1.0) * CFrame.Angles(math.rad(-8), 0, 0)

-- Engine (berat, satu genggaman) tetap di tangan kanan.
Config.HandCarryOffset = CFrame.new(0, -0.6, -0.4) * CFrame.Angles(math.rad(90), 0, 0)

-- ============================================================
-- 2. WAKTU PASANG — harus diam, gak bisa gerak
-- ============================================================

Config.InsertDuration = 2.0             -- detik tahan prompt
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
