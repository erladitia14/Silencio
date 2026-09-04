--[[
	PromptManager.luau
	------------------
	ProximityPrompt pada tiap bilik: "Sembunyi" saat kosong, "Keluar" saat
	pemain sedang di dalamnya.

	SATU prompt per bilik, dibuat otomatis. Tim tidak perlu menempel apa pun
	— cukup tag Part-nya (prinsip yang sama dengan seluruh project ini).

	KENAPA prompt-nya juga dipakai untuk KELUAR: pemain yang sembunyi
	karakternya di-anchor, jadi ia tidak bisa jalan keluar. Harus ada jalan
	keluar sadar, kalau tidak ia terkurung sampai napas habis.

	CATATAN: `Enabled` prompt tidak dipakai untuk menyembunyikan bilik yang
	hangus, karena prompt yang mendadak hilang membingungkan pemain. Yang
	diubah adalah teksnya; penolakan tetap diputuskan server (ZoneService).
--]]

local Config = require(script.Parent.Config)

local PromptManager = {}

-- zonePart -> ProximityPrompt
local prompts: { [BasePart]: ProximityPrompt } = {}
-- zonePart -> RBXScriptConnection
local conns: { [BasePart]: RBXScriptConnection } = {}

--- Nama instance prompt. Diberi awalan supaya tidak tertukar dengan
--- prompt buatan tim di objek yang sama.
local PROMPT_NAME = "SafeZonePrompt"

---------------------------------------------------------------------

--- Pasang prompt pada sebuah bilik.
--- @param onTrigger  fungsi(zonePart, player) — dipanggil saat ditekan
function PromptManager.attach(zonePart: BasePart, onTrigger: (BasePart, Player) -> ())
	if prompts[zonePart] then
		return
	end

	-- Pakai prompt yang sudah ada kalau tim sengaja menaruhnya (mis. supaya
	-- posisi/ikon-nya khusus), jangan bikin duplikat.
	local prompt = zonePart:FindFirstChild(PROMPT_NAME)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.Parent = zonePart
	end

	prompt.ActionText = Config.PromptActionText
	prompt.ObjectText = Config.PromptObjectText
	prompt.KeyboardKeyCode = Config.PromptKey
	prompt.MaxActivationDistance = Config.PromptDistance
	prompt.HoldDuration = Config.PromptHoldDuration
	prompt.RequiresLineOfSight = Config.PromptRequiresLineOfSight
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton

	prompts[zonePart] = prompt
	conns[zonePart] = prompt.Triggered:Connect(function(player)
		onTrigger(zonePart, player)
	end)
end

--- Lepas prompt (bilik di-untag / dihapus).
function PromptManager.detach(zonePart: BasePart)
	local c = conns[zonePart]
	if c then
		c:Disconnect()
		conns[zonePart] = nil
	end

	local p = prompts[zonePart]
	if p and p.Parent then
		p:Destroy()
	end
	prompts[zonePart] = nil
end

--- Perbarui teks prompt sesuai keadaan bilik.
--- @param occupied  true = pemain sedang di dalam -> tawarkan "Keluar"
function PromptManager.setOccupied(zonePart: BasePart, occupied: boolean)
	local p = prompts[zonePart]
	if not p then
		return
	end
	p.ActionText = occupied and Config.PromptExitText or Config.PromptActionText
end

--- Apakah bilik ini punya prompt terpasang.
function PromptManager.has(zonePart: BasePart): boolean
	return prompts[zonePart] ~= nil
end

--- KHUSUS UJI: akses prompt sebuah bilik.
function PromptManager.get(zonePart: BasePart): ProximityPrompt?
	return prompts[zonePart]
end

return PromptManager
