--[[
	KeyService.luau (KeySystem)
	---------------------------
	Single source of truth: siapa memegang kunci apa.
	Server-authoritative — state kunci TIDAK disimpan di client.

	Co-op friendly: kunci yang sudah diambil salah satu player dianggap
	dimiliki oleh TIM (shared), agar power/pintu tetap terbuka meski
	player yang mengambil keluar. Bisa diubah ke per-player bila perlu.
--]]

local KeyService = {}
KeyService.__index = KeyService

function KeyService.new()
	local self = setmetatable({}, KeyService)
	-- Set kunci yang sudah dimiliki tim: { [keyId] = true }
	self._ownedKeys = {} :: { [string]: boolean }
	return self
end

--- Tandai sebuah kunci telah diambil (dimiliki tim).
function KeyService:grantKey(keyId: string)
	self._ownedKeys[keyId] = true
	print("[KeySystem] Kunci diperoleh: " .. tostring(keyId))
end

--- Cek apakah tim sudah memiliki kunci tertentu.
function KeyService:hasKey(keyId: string): boolean
	return self._ownedKeys[keyId] == true
end

--- (Opsional) hapus kunci — mis. dipakai/patah.
function KeyService:consumeKey(keyId: string)
	self._ownedKeys[keyId] = nil
end

return KeyService
