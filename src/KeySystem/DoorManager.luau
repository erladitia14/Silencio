--[[
	DoorManager.luau (KeySystem)
	----------------------------
	Mengelola pintu ber-tag "LockedDoor".

	Untuk tiap pintu:
	  - Membuat ProximityPrompt otomatis (kalau belum ada)
	  - Saat di-trigger: cek apakah tim punya RequiredKey via KeyService
	      * punya  -> buka pintu (transparansi + non-collide), lapor PowerService
	      * tidak  -> tampilkan prompt "Terkunci"
	  - Reaktif terhadap perubahan kepemilikan kunci (prompt teks di-update)

	Pintu bisa berupa BasePart atau Model (pakai PrimaryPart / part pertama).
--]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local DoorManager = {}
DoorManager.__index = DoorManager

function DoorManager.new(keyService: any, powerService: any)
	local self = setmetatable({}, DoorManager)
	self._keyService = keyService
	self._powerService = powerService
	self._doors = {} :: { [Instance]: any }  -- record per pintu
	return self
end

--- Ambil BasePart utama dari sebuah instance pintu (Part atau Model).
local function resolvePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

--- Baca konfigurasi pintu dari attribute (dengan fallback ke default).
local function readDoorConfig(inst: Instance)
	local doorId = inst:GetAttribute("DoorId") or Config.DefaultDoorId
	local requiredKey = inst:GetAttribute("RequiredKey") or doorId
	local autoClose = inst:GetAttribute("AutoClose")
	if autoClose == nil then autoClose = Config.DefaultAutoClose end
	local autoCloseDelay = inst:GetAttribute("AutoCloseDelay") or Config.DefaultAutoCloseDelay
	return doorId, requiredKey, autoClose, autoCloseDelay
end

function DoorManager:_openDoor(inst: Instance, record: any)
	local part = record.part
	if not part then return end

	-- Simpan properti asli agar bisa dikembalikan saat menutup
	if record.origTransparency == nil then
		record.origTransparency = part.Transparency
		record.origCanCollide = part.CanCollide
	end

	part.Transparency = Config.DoorOpenTransparency
	part.CanCollide = Config.DoorOpenCanCollide
	record.isOpen = true

	self._powerService:setDoorOpen(record.doorId, true)
	print("[KeySystem] Pintu '" .. record.doorId .. "' terbuka.")

	if record.prompt then
		record.prompt.Enabled = false
	end

	if record.autoClose then
		task.delay(record.autoCloseDelay, function()
			self:_closeDoor(inst, record)
		end)
	end
end

function DoorManager:_closeDoor(inst: Instance, record: any)
	local part = record.part
	if not part or not record.isOpen then return end

	part.Transparency = record.origTransparency or 0
	part.CanCollide = record.origCanCollide ~= false
	record.isOpen = false

	self._powerService:setDoorOpen(record.doorId, false)

	-- Aktifkan lagi prompt supaya bisa dibuka ulang
	self:_refreshPrompt(record)
end

--- Update teks/enabled prompt sesuai kepemilikan kunci saat ini.
function DoorManager:_refreshPrompt(record: any)
	if not record.prompt or record.isOpen then return end
	local hasKey = self._keyService:hasKey(record.requiredKey)
	record.prompt.Enabled = true
	record.prompt.ActionText = hasKey and Config.PromptDoorUnlock or Config.PromptDoorLocked
end

function DoorManager:register(inst: Instance)
	if self._doors[inst] then return end

	local part = resolvePart(inst)
	if not part then
		warn("[KeySystem] LockedDoor '" .. inst.Name .. "' tidak punya BasePart. Skip.")
		return
	end

	local doorId, requiredKey, autoClose, autoCloseDelay = readDoorConfig(inst)

	-- Buat ProximityPrompt kalau belum ada
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
		doorId = doorId,
		requiredKey = requiredKey,
		autoClose = autoClose,
		autoCloseDelay = autoCloseDelay,
		prompt = prompt,
		isOpen = false,
	}
	self._doors[inst] = record

	self:_refreshPrompt(record)

	prompt.Triggered:Connect(function(_player)
		if record.isOpen then return end
		if self._keyService:hasKey(record.requiredKey) then
			self:_openDoor(inst, record)
		else
			-- Feedback singkat: pintu masih terkunci
			record.prompt.ActionText = Config.PromptDoorLocked
		end
	end)
end

--- Panggil saat kepemilikan kunci berubah agar prompt pintu ter-update.
function DoorManager:onKeysChanged()
	for _, record in pairs(self._doors) do
		self:_refreshPrompt(record)
	end
end

--- Inisialisasi semua pintu ber-tag + dengarkan pintu baru saat runtime.
function DoorManager:start()
	for _, inst in CollectionService:GetTagged(Config.LockedDoorTag) do
		self:register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.LockedDoorTag):Connect(function(inst)
		self:register(inst)
	end)
end

return DoorManager
