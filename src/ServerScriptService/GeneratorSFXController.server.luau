--!strict
--[[
	GeneratorSFXController — Script tipis (ServerScriptService).

	Menyalakan dua modul MANDIRI yang saling terhubung:
	  1. GeneratorElectricFX — efek visual busur listrik (SUMBER sinyal)
	  2. GeneratorSFX        — suara generator (pengikut sinyal)

	Hubungannya: efek listrik men-fire BindableEvent "HighVoltage" di
	ReplicatedStorage; GeneratorSFX mendengarnya dan memutar
	high_voltage_electricity.
	Jadi efek & suara selalu muncul BERSAMAAN, tidak mungkin lepas sinkron.

	TIDAK menyentuh BatteryPuzzleController / AssemblyController / sistem lain.

	Suara & efek:
	  tombol power    -> pressing_a_large_industrial_button
	  4 baterai       -> electrical_contacts
	  generator nyala -> old_industrial_generator (startup) lalu
	                     steady_industrial_generator (loop mesin)
	  efek listrik    -> high_voltage_electricity (ikut sinyal efek, one-shot)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsServer() then
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")

-- GeneratorSFX dulu: ia yang MEMBUAT BindableEvent "HighVoltage" di
-- ReplicatedStorage kalau belum ada, jadi GeneratorElectricFX menemukan event sama.
local GeneratorSFX = require(Modules:WaitForChild("GeneratorSFX"))
local GeneratorElectricFX = require(Modules:WaitForChild("GeneratorElectricFX"))

-- buttonOnSuccess = false -> suara tombol bunyi TIAP ditekan (termasuk saat
-- gating masih menolak, mis. "Install all the batteries first!").
-- Ubah ke true kalau maunya hanya bunyi saat generator benar-benar nyala.
GeneratorSFX.start({
	buttonOnSuccess = false,
})

GeneratorElectricFX.start()
