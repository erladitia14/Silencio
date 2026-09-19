--!strict
--[[
	AssemblyController — orchestrator SERVER untuk perakitan genset.

	Berdiri SENDIRI:
	- tidak require EnemyController / KeySystem / SafeZone / BatteryService
	- hanya menjalankan AssemblyService

	Cara pakai (nol koordinat, cukup tag di Tag Editor):
	  Slot placeholder (di dalam Model Generator) -> tag "AssemblySlot" + Attribute Kind = "Engine"/"Panel"
	  Mesh yang diambil pemain                     -> tag "AssemblyPickup" + Attribute Kind = "Engine"/"Panel"

	Saat 3/3 terpasang (1 Engine + 2 Panel), Model Generator diberi
	Attribute "GeneratorAssembled" = true. Sistem lain (baterai / lampu)
	boleh MEMBACA attribute ini tanpa perlu diubah file ini.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsServer() then
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BatteryPuzzle = Modules:WaitForChild("BatteryPuzzle")
local AssemblyService = require(BatteryPuzzle:WaitForChild("AssemblyService"))

AssemblyService.start({
	onAssembled = function(genModel)
		-- Genset selesai dirakit. Hook untuk tahap berikutnya (baterai / lampu).
		-- Sengaja tidak menyentuh sistem lain; cukup terbitkan attribute + print.
		print("[Assembly] Generator dirakit penuh:", genModel:GetFullName())
	end,
})
