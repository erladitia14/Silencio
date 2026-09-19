--!strict
--[[
	BatteryPuzzleController — orchestrator SERVER (Script di ServerScriptService).

	Menyambung 4 modul BatteryPuzzle. Berdiri SENDIRI:
	- tidak require EnemyController / KeySystem / SafeZone
	- tidak mengubah script sistem lain

	Cara pakai (nol konfigurasi, cukup tag di Tag Editor):
	  Model wadah   -> tag "BatteryCase"
	  Placeholder   -> tag "BatterySlot"   (BasePart, diposisikan manual)
	  Baterai asli  -> tag "BatteryPickup" (BasePart yang bisa diambil)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BatteryPuzzle = Modules:WaitForChild("BatteryPuzzle")

local Config = require(BatteryPuzzle:WaitForChild("Config"))
local BatteryService = require(BatteryPuzzle:WaitForChild("BatteryService"))
local CaseService = require(BatteryPuzzle:WaitForChild("CaseService"))
local PuzzleService = require(BatteryPuzzle:WaitForChild("PuzzleService"))

-- ============================================================
-- RemoteEvent (progress ke client; opsional dipakai UI)
-- ============================================================

local remote = ReplicatedStorage:FindFirstChild("BatteryPuzzleEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "BatteryPuzzleEvent"
	remote.Parent = ReplicatedStorage
end

-- ============================================================
-- START (hanya di server)
-- ============================================================

if not RunService:IsServer() then
	return
end

-- PuzzleService dulu: menyiapkan event per-case
PuzzleService.start()

-- CaseService butuh fungsi dari BatteryService (lewat orchestrator,
-- supaya modul tidak saling require)
CaseService.start({
	isBatteryInserted = function(battery)
		return BatteryService.isInserted(battery)
	end,
	getCarried = function(player)
		return BatteryService.getCarried(player)
	end,
	markInserted = function(player, battery, cf)
		BatteryService.markInserted(player, battery, cf)
	end,
	onSlotFilled = function(player, case, slot, battery)
		local filled, total = CaseService.getProgress(case)
		PuzzleService.reportSlotFilled(case, slot, filled, total)
	end,
})

-- BatteryService
BatteryService.start(function(player, carrying)
	-- Terbitkan status bawa baterai ke semua client (UI boleh pakai)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients("carry", player, carrying)
	end
end)

-- ============================================================
-- SAAT GAME BERJALAN: sembunyikan placeholder
-- ============================================================

-- Di Studio edit mode placeholder TETAP terlihat supaya bisa ditata.
-- Begitu game jalan, baru disembunyikan (tidak dihapus).
CaseService.hidePlaceholders()

Config.log("BatteryPuzzleController ready")
