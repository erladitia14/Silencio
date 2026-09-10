--[[
	CustomPromptHelper.luau
	-----------------------
	Utility kecil: pasang konfigurasi CustomPrompt Handler pada sebuah
	ProximityPrompt yang baru dibuat, supaya otomatis pakai UI custom
	milik tim (Prompt1) tanpa mengubah kode CustomPrompt Handler itu sendiri.

	Pemakaian (di module kita yang bikin prompt):
		local CPHelper = require(game.ReplicatedStorage.Modules.CustomPromptHelper)
		local prompt = Instance.new("ProximityPrompt")
		-- ... set property prompt ...
		prompt.Parent = part
		CPHelper.apply(prompt)   -- selesai

	Kalau prompt SUDAH punya CustomPromptConf (misal tim taruh manual),
	apply() tidak menimpa — idempotent.
--]]

local CustomPromptHelper = {}

--- Nama modul prompt di folder Prompts (CustomPrompt Handler).
--- "Prompt1" = prompt universal yang sudah ada di place.
local DEFAULT_PROMPT_MODULE = "Prompt1"

--- Pasang tree CustomPromptConf pada sebuah ProximityPrompt.
--- Setelah ini, CustomPrompt Handler akan otomatis meng-hook prompt ini.
function CustomPromptHelper.apply(prompt: ProximityPrompt, options: {
	promptModule: string?,
	beam: boolean?,
	highlight: boolean?,
	highlightColor: Color3?,
	highlightTransparency: number?,
	beamWidth: number?,
	beamColor: Color3?,
	beamTransparency: number?,
}?)
	-- Sudah ada? Jangan timpa.
	if prompt:FindFirstChild("CustomPromptConf") then
		return
	end

	local opts = options or {}
	prompt.Style = Enum.ProximityPromptStyle.Custom

	-- Bangun tree sesuai kontrak CustomPrompt Handler
	local conf = Instance.new("Configuration")
	conf.Name = "CustomPromptConf"

	-- ObjectValue (diisi runtime oleh handler untuk referensi clone GUI)
	local objVal = Instance.new("ObjectValue")
	objVal.Name = "ObjectValue"
	objVal.Parent = conf

	-- CustomPrompt flag
	local cpFlag = Instance.new("BoolValue")
	cpFlag.Name = "CustomPrompt"
	cpFlag.Value = true
	cpFlag.Parent = conf

	local pName = Instance.new("StringValue")
	pName.Name = "PromptName"
	pName.Value = opts.promptModule or DEFAULT_PROMPT_MODULE
	pName.Parent = cpFlag

	-- Beam (default off)
	local beamFlag = Instance.new("BoolValue")
	beamFlag.Name = "Beam"
	beamFlag.Value = opts.beam == true
	beamFlag.Parent = conf

	local bw = Instance.new("NumberValue")
	bw.Name = "BeamWidth"
	bw.Value = opts.beamWidth or 0.05
	bw.Parent = beamFlag

	local bc = Instance.new("Color3Value")
	bc.Name = "BeamColor"
	bc.Value = opts.beamColor or Color3.new(1, 1, 1)
	bc.Parent = beamFlag

	local bt = Instance.new("NumberValue")
	bt.Name = "BeamTransparency"
	bt.Value = opts.beamTransparency or 0.2
	bt.Parent = beamFlag

	-- Highlight (default off)
	local hlFlag = Instance.new("BoolValue")
	hlFlag.Name = "Highlight"
	hlFlag.Value = opts.highlight == true
	hlFlag.Parent = conf

	local hc = Instance.new("Color3Value")
	hc.Name = "HighlightColor"
	hc.Value = opts.highlightColor or Color3.new(1, 1, 1)
	hc.Parent = hlFlag

	local ht = Instance.new("NumberValue")
	ht.Name = "HighlightTransparency"
	ht.Value = opts.highlightTransparency or 0
	ht.Parent = hlFlag

	conf.Parent = prompt
end

return CustomPromptHelper
