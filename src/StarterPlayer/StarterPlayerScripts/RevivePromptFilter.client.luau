--[[
	RevivePromptFilter.client.luau
	------------------------------
	Menyembunyikan ProximityPrompt "Revive" pada KARAKTER SENDIRI.

	Kenapa perlu: ProximityPrompt itu GLOBAL — prompt yang ditempel di
	HumanoidRootPart pemain tumbang terlihat oleh SEMUA pemain, termasuk
	pemain tumbang itu sendiri (jarak 0 stud). Server sudah MENOLAK
	self-revive (lihat ReviveManager.canRevive), jadi ini murni soal tampilan:
	jangan tawarkan tombol yang tidak bisa dipakai.

	Cara kerja: setiap kali ada ProximityPrompt bernama "RevivePrompt" muncul
	di workspace, matikan secara LOKAL kalau karakternya milik player ini.
	Matikan lewat `Enabled = false` hanya di client — server tidak terpengaruh,
	dan pemain lain tetap melihat prompt di badan kita.

	Tidak menyentuh sistem lain. Tidak ada tag. Nol konfigurasi.
--]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local PROMPT_NAME = "RevivePrompt"
local localPlayer = Players.LocalPlayer

--- Matikan prompt secara lokal bila ia milik karakter player ini.
local function filter(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt.Name ~= PROMPT_NAME then
		return
	end

	local character = prompt:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	-- Karakter ini milikku?
	if Players:GetPlayerFromCharacter(character) == localPlayer then
		prompt.Enabled = false
	end
end

-- Prompt yang sudah ada (mis. karakter sudah tumbang sebelum script jalan).
for _, d in workspace:GetDescendants() do
	filter(d)
end

-- Prompt yang muncul kemudian.
workspace.DescendantAdded:Connect(filter)
