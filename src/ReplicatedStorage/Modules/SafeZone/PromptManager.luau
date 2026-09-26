--[[
	PromptManager.luau
	------------------
	Integrasi SafeZone ke CustomPromptController bawaan tim SilencioClient.
	Tidak lagi membuat ProximityPrompt instance baru (agar tidak membajak tombol E di PC).
--]]

local Config = require(script.Parent.Config)

local PromptManager = {}

-- zonePart -> boolean
local registeredZones: { [BasePart]: boolean } = {}

---------------------------------------------------------------------

--- Pasang prompt pada sebuah bilik via atribut & CustomPromptController.
--- @param onTrigger  fungsi(zonePart, player) — dipanggil saat ditekan
function PromptManager.attach(zonePart: BasePart, onTrigger: (BasePart, Player) -> ())
	if registeredZones[zonePart] then
		return
	end

	-- Hapus ProximityPrompt lama jika pernah dibuat agar tidak bentrok
	local oldPrompt = zonePart:FindFirstChild("SafeZonePrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	-- Pasang atribut konfigurasi untuk CustomPromptController tim
	zonePart:SetAttribute("InteractDistance", Config.PromptDistance or 14)
	zonePart:SetAttribute("HoldDuration", Config.PromptHoldDuration or 0.05)
	zonePart:SetAttribute("InstantPrompt", (Config.PromptHoldDuration or 0) <= 0.05)
	zonePart:SetAttribute("PromptScale", 1.1)
	zonePart:SetAttribute("SilentPrompt", true)

	registeredZones[zonePart] = true
end

--- Lepas prompt (bilik di-untag / dihapus).
function PromptManager.detach(zonePart: BasePart)
	registeredZones[zonePart] = nil
	local oldPrompt = zonePart:FindFirstChild("SafeZonePrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end
end

--- Perbarui teks prompt sesuai keadaan bilik.
--- @param occupied  true = pemain sedang di dalam -> tawarkan "Keluar"
function PromptManager.setOccupied(zonePart: BasePart, occupied: boolean)
	-- CustomPromptController di client membaca state SafeZone
	-- Teks switch ditangani oleh ZoneService & HUD
end

--- Apakah bilik ini punya prompt terpasang.
function PromptManager.has(zonePart: BasePart): boolean
	return registeredZones[zonePart] ~= nil
end

--- KHUSUS UJI
function PromptManager.get(zonePart: BasePart): any?
	return nil
end

return PromptManager
