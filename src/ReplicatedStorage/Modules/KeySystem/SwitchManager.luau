--[[
	SwitchManager.luau (KeySystem)
	------------------------------
	Mengelola power switch ber-tag "PowerSwitch".

	Syarat aktif (sesuai desain): switch hanya bisa ditekan jika pintu
	control room (GateDoorId) SUDAH terbuka. Selama belum, prompt
	menampilkan "Ruang Kontrol Masih Terkunci" dan trigger diabaikan.

	Saat ditekan & syarat terpenuhi -> PowerService:setPower(true).
	Reaktif terhadap DoorStateChanged: prompt otomatis meng-enable saat
	pintu gate terbuka.
--]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local SwitchManager = {}
SwitchManager.__index = SwitchManager

function SwitchManager.new(powerService: any)
	local self = setmetatable({}, SwitchManager)
	self._powerService = powerService
	self._switches = {} :: { [Instance]: any }
	return self
end

local function resolvePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

--- Cek apakah syarat switch terpenuhi (pintu gate terbuka bila diperlukan).
function SwitchManager:_isUnlocked(record: any): boolean
	if not record.requiresDoorOpen then
		return true
	end
	return self._powerService:isDoorOpen(record.gateDoorId)
end

--- Update teks & enabled prompt sesuai syarat.
function SwitchManager:_refreshPrompt(record: any)
	if not record.prompt then return end
	if self._powerService:isPowerOn() then
		-- Power sudah menyala, prompt tak diperlukan lagi
		record.prompt.Enabled = false
		return
	end
	local unlocked = self:_isUnlocked(record)
	record.prompt.Enabled = true
	record.prompt.ActionText = unlocked and Config.PromptSwitchOn or Config.PromptSwitchLocked
end

function SwitchManager:register(inst: Instance)
	if self._switches[inst] then return end

	local part = resolvePart(inst)
	if not part then
		warn("[KeySystem] PowerSwitch '" .. inst.Name .. "' tidak punya BasePart. Skip.")
		return
	end

	local requiresDoorOpen = inst:GetAttribute("RequiresDoorOpen")
	if requiresDoorOpen == nil then requiresDoorOpen = true end
	local gateDoorId = inst:GetAttribute("GateDoorId") or Config.DefaultGateDoorId

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.HoldDuration = Config.PromptHoldDuration
		prompt.MaxActivationDistance = Config.PromptMaxDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
	end

	local record = {
		part = part,
		prompt = prompt,
		requiresDoorOpen = requiresDoorOpen,
		gateDoorId = gateDoorId,
	}
	self._switches[inst] = record

	self:_refreshPrompt(record)

	prompt.Triggered:Connect(function(_player)
		if self._powerService:isPowerOn() then return end
		if self:_isUnlocked(record) then
			self._powerService:setPower(true)
		else
			record.prompt.ActionText = Config.PromptSwitchLocked
		end
	end)
end

--- Refresh semua switch (dipanggil saat status pintu / power berubah).
function SwitchManager:refreshAll()
	for _, record in pairs(self._switches) do
		self:_refreshPrompt(record)
	end
end

function SwitchManager:start()
	for _, inst in CollectionService:GetTagged(Config.PowerSwitchTag) do
		self:register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.PowerSwitchTag):Connect(function(inst)
		self:register(inst)
	end)

	-- Reaktif: pintu gate terbuka -> switch unlock; power on -> prompt off
	self._powerService.DoorStateChanged:Connect(function()
		self:refreshAll()
	end)
	self._powerService.PowerChanged:Connect(function()
		self:refreshAll()
	end)
end

return SwitchManager
