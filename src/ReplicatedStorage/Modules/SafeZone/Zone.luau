--[[
	Zone.luau
	---------
	Satu bilik = satu objek Zone. Semua state per-bilik ada di sini:
	napas, penghuni, cooldown.

	SIKLUS BILIK (satu arah, tidak ada jalan pintas):

	  READY ──(ada yang masuk)──► OCCUPIED ──(napas habis)──► BREACHED
	    ▲                             │                          │
	    │                             │ (kosong lagi)            │ (kosong)
	    │                             ▼                          ▼
	    └────(napas terisi penuh)── READY                    COOLDOWN
	                                                             │
	                                                             └─► READY

	Aturan yang mencegah exploit:
	  - Keluar-masuk TIDAK mereset napas. Napas hanya terisi penuh setelah
	    bilik kosong selama CooldownTime (atau setelah COOLDOWN selesai).
	  - Bilik yang sudah BREACHED tidak bisa melindungi siapa pun sampai
	    ia kosong dan lewat masa hangus.
	  - Kapasitas dijaga: pendatang ke-2 (bilik toilet MaxOccupants=1)
	    tidak dapat perlindungan sama sekali.
--]]

local Config   = require(script.Parent.Config)
local Settings = require(script.Parent.Settings)

local Zone = {}
Zone.__index = Zone

local S = Config.State

--- @param part  Part bilik di Workspace
function Zone.new(part: BasePart)
	local self = setmetatable({}, Zone)

	self.part       = part
	self.state      = S.READY
	self.breathLeft = Settings.get(part, "BreathTime")
	self.occupants  = {} :: { [any]: boolean }  -- key = Player (atau tabel palsu saat uji)
	self.count      = 0
	self.emptySince = os.clock()
	self.burnedAt   = 0
	self.dirty      = true   -- true = state berubah, perlu dikirim ke client

	return self
end

---------------------------------------------------------------------
-- SETELAN (selalu dibaca ulang: tim boleh ubah Attribute saat Play)
---------------------------------------------------------------------

function Zone:breathTime(): number
	local v = Settings.get(self.part, "BreathTime")
	return typeof(v) == "number" and v or Config.BreathTime
end

function Zone:cooldownTime(): number
	local v = Settings.get(self.part, "CooldownTime")
	return typeof(v) == "number" and v or Config.CooldownTime
end

function Zone:capacity(): number
	return Settings.capacity(self.part)
end

--- Bilik "abadi": tanpa timer napas (perilaku Safe Zone lama).
function Zone:isEternal(): boolean
	return Settings.get(self.part, "NoBreath") == true
end

--- Bilik ini menahan monster secara fisik?
function Zone:hasBarrier(): boolean
	if not Config.BarrierEnabled then
		return false
	end
	return Settings.get(self.part, "NoBarrier") ~= true
end

---------------------------------------------------------------------
-- PENGHUNI
---------------------------------------------------------------------

--- Apakah `who` terdaftar sebagai penghuni yang dilindungi.
function Zone:hasOccupant(who: any): boolean
	return self.occupants[who] == true
end

--- Coba daftarkan penghuni. Mengembalikan alasan gagal (atau nil kalau berhasil).
--- @return string?  nil = dapat perlindungan, "FULL"/"COOLDOWN"/"BREACHED" = tidak
function Zone:tryAdd(who: any): string?
	if self.occupants[who] then
		return nil
	end

	if self.state == S.COOLDOWN then
		return S.COOLDOWN
	end
	if self.state == S.BREACHED then
		return S.BREACHED
	end
	if self.count >= self:capacity() then
		return "FULL"
	end

	self.occupants[who] = true
	self.count += 1
	self.dirty = true

	if self.state == S.READY then
		self:_setState(S.OCCUPIED)
	end

	return nil
end

--- Keluarkan penghuni (keluar bilik / mati / leave server).
function Zone:remove(who: any)
	if not self.occupants[who] then
		return
	end

	self.occupants[who] = nil
	self.count -= 1
	self.dirty = true

	if self.count > 0 then
		return
	end

	-- Bilik baru saja kosong.
	self.emptySince = os.clock()

	if self.state == S.BREACHED then
		-- Sudah kebobolan -> hangus, tunggu masa cooldown.
		self:_burn()
	elseif self.state == S.OCCUPIED then
		if Settings.get(self.part, "BurnOnExit") == true then
			self:_burn()
		else
			-- Napas TIDAK di-reset: keluar-masuk tidak memberi jatah gratis.
			self:_setState(S.READY)
		end
	end
end

---------------------------------------------------------------------
-- DETAK
---------------------------------------------------------------------

function Zone:_setState(next: string)
	if self.state ~= next then
		self.state = next
		self.dirty = true
	end
end

function Zone:_burn()
	self.burnedAt = os.clock()
	self.breathLeft = 0
	self:_setState(S.COOLDOWN)
end

--- Maju satu langkah waktu.
--- @param dt  detik sejak detak sebelumnya
function Zone:step(dt: number)
	if self:isEternal() then
		-- Bilik abadi: napas selalu penuh, tidak pernah hangus.
		self.breathLeft = self:breathTime()
		self:_setState(self.count > 0 and S.OCCUPIED or S.READY)
		return
	end

	if self.state == S.OCCUPIED then
		self.breathLeft = math.max(0, self.breathLeft - dt)
		self.dirty = true
		if self.breathLeft <= 0 then
			self:_setState(S.BREACHED)
		end

	elseif self.state == S.COOLDOWN then
		if (os.clock() - self.burnedAt) >= self:cooldownTime() then
			self.breathLeft = self:breathTime()
			self.emptySince = os.clock()
			self:_setState(S.READY)
		end

	elseif self.state == S.READY then
		-- Terisi penuh hanya setelah kosong selama CooldownTime.
		local full = self:breathTime()
		if self.breathLeft < full and (os.clock() - self.emptySince) >= self:cooldownTime() then
			self.breathLeft = full
			self.dirty = true
		end
	end
	-- BREACHED: tidak ada yang berubah sampai penghuni terakhir keluar.
end

--- Bilik sedang benar-benar melindungi penghuninya?
function Zone:isProtecting(): boolean
	return self.state == S.OCCUPIED
end

--- Ringkasan untuk dikirim ke client (UI bar napas).
function Zone:snapshot(): { [string]: any }
	local full = self:breathTime()
	return {
		zone     = self.part,
		state    = self.state,
		breath   = self.breathLeft,
		max      = full,
		fraction = full > 0 and math.clamp(self.breathLeft / full, 0, 1) or 0,
		count    = self.count,
		capacity = self:capacity(),
		eternal  = self:isEternal(),
	}
end

return Zone
