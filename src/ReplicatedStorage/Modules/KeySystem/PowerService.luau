--[[
	PowerService.luau (KeySystem)
	-----------------------------
	Single source of truth untuk status listrik carnival.
	Modul lain (LightManager, nanti SoundManager, dll) cukup subscribe
	ke signal PowerChanged — tidak perlu tahu asal perubahannya.

	Juga menyimpan set pintu yang sudah terbuka (openedDoors), agar
	PowerSwitch bisa memvalidasi syarat "pintu control room harus kebuka".
--]]

local Signal = require(script.Parent.Signal)

local PowerService = {}
PowerService.__index = PowerService

function PowerService.new()
	local self = setmetatable({}, PowerService)
	self._powerOn = false
	self._openedDoors = {} :: { [string]: boolean }

	-- Signal publik. Subscribe via PowerService.PowerChanged:Connect(fn)
	self.PowerChanged = Signal.new()  -- Fire(isOn: boolean)
	self.DoorStateChanged = Signal.new() -- Fire(doorId: string, isOpen: boolean)

	return self
end

--- Set status power. Hanya fire signal jika benar-benar berubah.
function PowerService:setPower(isOn: boolean)
	if self._powerOn == isOn then
		return
	end
	self._powerOn = isOn
	print("[KeySystem] Power => " .. (isOn and "ON" or "OFF"))
	self.PowerChanged:Fire(isOn)
end

function PowerService:isPowerOn(): boolean
	return self._powerOn
end

--- Dipanggil DoorManager saat sebuah pintu terbuka/tertutup.
function PowerService:setDoorOpen(doorId: string, isOpen: boolean)
	if self._openedDoors[doorId] == isOpen then
		return
	end
	self._openedDoors[doorId] = isOpen
	self.DoorStateChanged:Fire(doorId, isOpen)
end

--- Cek apakah pintu tertentu sedang terbuka.
function PowerService:isDoorOpen(doorId: string): boolean
	return self._openedDoors[doorId] == true
end

return PowerService
