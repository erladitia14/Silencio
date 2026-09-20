--!strict
--[[
	GeneratorSFXController — Script tipis (ServerScriptService).

	Tugasnya cuma satu: menyalakan modul pendengar suara generator.
	TIDAK menyentuh BatteryPuzzleController / AssemblyController / sistem lain.

	Suara yang didengarkan:
	  tombol power  -> pressing_a_large_industrial_button
	  4 baterai     -> electrical_contacts
	  generator nyala -> old_industrial_generator (startup, one-shot)
	                    lalu steady_industrial_generator + high_voltage_electricity (loop)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsServer() then
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GeneratorSFX = require(Modules:WaitForChild("GeneratorSFX"))

-- buttonOnSuccess = false -> suara tombol bunyi TIAP ditekan (termasuk saat
-- gating masih menolak, mis. "Install all the batteries first!").
-- Ubah ke true kalau maunya hanya bunyi saat generator benar-benar nyala.
GeneratorSFX.start({
	buttonOnSuccess = false,
})
