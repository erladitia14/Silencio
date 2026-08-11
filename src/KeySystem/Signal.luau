--[[
	Signal.luau (KeySystem)
	-----------------------
	Implementasi Signal ringan (observer pattern) berbasis BindableEvent.
	Dipakai untuk komunikasi antar-modul yang decoupled:
	  - PowerService.PowerChanged
	  - DoorManager.DoorOpened
	Sehingga modul lain cukup subscribe tanpa saling tahu implementasi.
--]]

local Signal = {}
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({}, Signal)
	self._bindable = Instance.new("BindableEvent")
	return self
end

--- Subscribe ke signal. Mengembalikan RBXScriptConnection (punya :Disconnect()).
function Signal:Connect(callback: (...any) -> ())
	return self._bindable.Event:Connect(callback)
end

--- Memicu signal ke semua subscriber.
function Signal:Fire(...)
	self._bindable:Fire(...)
end

--- Membersihkan signal.
function Signal:Destroy()
	self._bindable:Destroy()
end

return Signal
