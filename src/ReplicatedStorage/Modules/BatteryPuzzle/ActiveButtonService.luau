--!strict
--[[
	ActiveButtonService — tombol AKHIR untuk MENYALAKAN generator.

	Lokasi tombol: Attachment "ActiveButton" pada MeshPart Case di dalam
	Model generator (game.Workspace.Generator.Generator.Case.ActiveButton).

	Syarat nyala (dua-duanya harus terpenuhi):
	  1. Genset sudah dirakit  -> Attribute "GeneratorAssembled" = true
	     (di-set AssemblyService pada Model "Generator" bagian dalam)
	  2. 4 baterai terpasang    -> Attribute "BatteryPuzzleComplete" = true
	     (di-set PuzzleService/CaseService pada Model "BatteryCase")

	Perilaku:
	  - Prompt "Nyalakan Generator" SELALU tampil di tombol (biar pemain tahu
	    tombolnya ada), tapi kalau syarat belum lengkap -> tampilkan WARNING dan
	    tolak (pola sama dengan gating Panel: prompt ada, tapi kasih peringatan).
	  - Kalau syarat lengkap -> set Attribute "GeneratorPowered" = true pada Model
	    generator + fire BindableEvent "GeneratorPowered" supaya sistem lain
	    (lampu / pintu) boleh MENYAMBUNG tanpa mengubah file ini.

	Berdiri sendiri: tidak require modul luar selain Config.
]]

local Config = require(script.Parent.Config)

local ActiveButtonService = {}

local prompt: ProximityPrompt? = nil
local generatorModel: Model? = nil
local batteryCaseModel: Instance? = nil
local powered = false

local onWarnCallback: ((player: Player, message: string) -> ())? = nil
local onPoweredCallback: ((genModel: Model) -> ())? = nil

function ActiveButtonService.setWarnCallback(cb: (player: Player, message: string) -> ())
	onWarnCallback = cb
end

function ActiveButtonService.setPoweredCallback(cb: (genModel: Model) -> ())
	onPoweredCallback = cb
end

local function warn_(player: Player, message: string)
	if onWarnCallback then
		onWarnCallback(player, message)
	end
end

-- ----------------------------------------------------------------------
-- Cek syarat
-- ----------------------------------------------------------------------

local function isAssembled(): boolean
	return generatorModel ~= nil and generatorModel:GetAttribute("GeneratorAssembled") == true
end

local function isBatteryComplete(): boolean
	if not batteryCaseModel then return false end
	return batteryCaseModel:GetAttribute(Config.CompletedAttribute) == true
end

-- ----------------------------------------------------------------------
-- Aktivasi
-- ----------------------------------------------------------------------

local function tryActivate(player: Player)
	if powered then return end

	if not isAssembled() then
		warn_(player, "Rakit generator dulu (Engine + 2 Panel)!")
		return
	end
	if not isBatteryComplete() then
		warn_(player, "Pasang semua baterai dulu!")
		return
	end

	-- Nyalakan.
	powered = true
	if generatorModel then
		generatorModel:SetAttribute("GeneratorPowered", true)
	end
	if prompt then
		prompt.Enabled = false
	end
	Config.log("GENERATOR POWERED via ActiveButton")

	if onPoweredCallback and generatorModel then
		onPoweredCallback(generatorModel)
	end
end

-- ----------------------------------------------------------------------
-- Setup tombol
-- ----------------------------------------------------------------------

-- opts:
--   generator: Model      (Model generator dalam yang menyimpan Case + attribute)
--   batteryCase: Instance  (Model BatteryCase)
--   button: Attachment | BasePart  (titik tempat menaruh prompt)
function ActiveButtonService.start(opts: {
	generator: Model,
	batteryCase: Instance?,
	button: Instance,
})
	generatorModel = opts.generator
	batteryCaseModel = opts.batteryCase

	local button = opts.button
	local existing = button:FindFirstChild("GeneratorActivatePrompt") :: ProximityPrompt?
	if existing then
		prompt = existing
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GeneratorActivatePrompt"
		prompt.Parent = button
	end

	assert(prompt)
	prompt.ActionText = "Nyalakan Generator"
	prompt.ObjectText = "Generator"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = Config.PickupPromptDistance + 2
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true

	prompt.Triggered:Connect(tryActivate)

	-- Kalau generator sudah pernah powered (mis. re-run), matikan prompt.
	if generatorModel and generatorModel:GetAttribute("GeneratorPowered") == true then
		powered = true
		prompt.Enabled = false
	end
end

function ActiveButtonService.isPowered(): boolean
	return powered
end

return ActiveButtonService
