--[[
	KeyPickupManager.luau (KeySystem)
	---------------------------------
	Mengelola objek ber-tag "KeyPickup".
	Tiap kunci diberi ProximityPrompt "Ambil Kunci".
	Saat di-trigger: berikan KeyId ke KeyService (shared/tim), lalu hilangkan
	kunci dari dunia (Destroy). Bersifat server-authoritative.
--]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local KeyPickupManager = {}
KeyPickupManager.__index = KeyPickupManager

function KeyPickupManager.new(keyService: any, onKeyGranted: ((keyId: string) -> ())?)
	local self = setmetatable({}, KeyPickupManager)
	self._keyService = keyService
	self._onKeyGranted = onKeyGranted
	self._registered = {} :: { [Instance]: boolean }
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

function KeyPickupManager:register(inst: Instance)
	if self._registered[inst] then return end

	local part = resolvePart(inst)
	if not part then
		warn("[KeySystem] KeyPickup '" .. inst.Name .. "' tidak punya BasePart. Skip.")
		return
	end

	local keyId = inst:GetAttribute("KeyId") or Config.DefaultKeyId

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.HoldDuration = Config.PromptHoldDuration
		prompt.MaxActivationDistance = Config.PromptMaxDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
	end
	prompt.ActionText = Config.PromptKeyPickup

	self._registered[inst] = true

	prompt.Triggered:Connect(function(_player)
		self._keyService:grantKey(keyId)
		if self._onKeyGranted then
			self._onKeyGranted(keyId)
		end
		-- Hilangkan kunci dari dunia
		inst:Destroy()
	end)
end

function KeyPickupManager:start()
	for _, inst in CollectionService:GetTagged(Config.KeyPickupTag) do
		self:register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.KeyPickupTag):Connect(function(inst)
		self:register(inst)
	end)
end

return KeyPickupManager
