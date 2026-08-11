--[[
	LightManager.luau (KeySystem)
	-----------------------------
	Menyalakan/mematikan semua objek ber-tag "CarnivalLight" secara serempak
	saat PowerService.PowerChanged berubah.

	Efisien: hanya iterasi 1x per perubahan state (bukan polling).
	Mendukung part biasa (Material/Color) maupun objek Light (PointLight,
	SpotLight, SurfaceLight) dan Neon.

	Objek baru ber-tag yang muncul saat runtime otomatis ikut state terkini.
--]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local LightManager = {}
LightManager.__index = LightManager

function LightManager.new(powerService: any)
	local self = setmetatable({}, LightManager)
	self._powerService = powerService
	self._lights = {} :: { [Instance]: any }
	return self
end

--- Terapkan state on/off ke satu objek lampu.
function LightManager:_apply(inst: Instance, isOn: boolean)
	local record = self._lights[inst]
	if not record then return end

	local onBright = inst:GetAttribute("OnBrightness") or Config.DefaultOnBrightness
	local offBright = inst:GetAttribute("OffBrightness") or Config.DefaultOffBrightness

	-- 1) Kalau instance-nya objek Light
	if inst:IsA("Light") then
		inst.Enabled = isOn
		inst.Brightness = isOn and onBright or offBright
		return
	end

	-- 2) Kalau BasePart: atur emisi via Light child (kalau ada) + tampilan
	if inst:IsA("BasePart") then
		-- Light child (PointLight dll)
		for _, child in inst:GetChildren() do
			if child:IsA("Light") then
				child.Enabled = isOn
				child.Brightness = isOn and onBright or offBright
			end
		end

		-- Tampilan part: Neon menyala saat on, kembali material asli saat off
		if isOn then
			record.origMaterial = record.origMaterial or inst.Material
			record.origColor = record.origColor or inst.Color
			inst.Material = Enum.Material.Neon
			inst.Color = Config.LightOnColor
		else
			if record.origMaterial then inst.Material = record.origMaterial end
			if record.origColor then inst.Color = record.origColor end
		end
	end
end

function LightManager:register(inst: Instance)
	if self._lights[inst] then return end
	self._lights[inst] = {}
	-- Sinkronkan langsung ke state power saat ini
	self:_apply(inst, self._powerService:isPowerOn())
end

--- Terapkan state ke semua lampu (dipanggil saat PowerChanged).
function LightManager:setAll(isOn: boolean)
	for inst in pairs(self._lights) do
		if inst.Parent then
			self:_apply(inst, isOn)
		else
			self._lights[inst] = nil  -- bersihkan yang sudah dihapus
		end
	end
end

--- Inisialisasi: daftarkan lampu ber-tag, subscribe PowerChanged, dengarkan runtime.
function LightManager:start()
	for _, inst in CollectionService:GetTagged(Config.CarnivalLightTag) do
		self:register(inst)
	end

	CollectionService:GetInstanceAddedSignal(Config.CarnivalLightTag):Connect(function(inst)
		self:register(inst)
	end)

	self._powerService.PowerChanged:Connect(function(isOn)
		self:setAll(isOn)
	end)
end

return LightManager
