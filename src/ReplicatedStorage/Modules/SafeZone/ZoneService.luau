--[[
	ZoneService.luau
	----------------
	Otak sistem Safe Zone di SERVER. Satu-satunya pemilik state bilik.

	Tugasnya:
	  1. Menemukan bilik (tag "SafeZone" / Folder "SafeZones") dan membuat
	     objek Zone untuk masing-masing — termasuk bilik yang di-tag saat
	     game sudah jalan.
	  2. Menjalankan detak: siapa di dalam bilik mana, napas berkurang,
	     cooldown, dinding monster dibuka/ditutup.
	  3. Menjawab pertanyaan core AI: "apakah karakter ini terlindungi?"
	     (dipakai TargetFinder lewat SafeZoneManager).
	  4. Menyiarkan keadaan ke client untuk UI bar napas.

	NOL KONFIGURASI: tidak ada script yang perlu ditempel ke bilik, tidak
	ada ID yang perlu diisi. Cukup tag Part-nya. Detail per bilik lewat
	Attribute (lihat Config).

	MONSTER: modul ini yang menandai badan monster ke CollisionGroup
	(mengikuti tag "Monster"), jadi core AI tidak perlu diubah untuk
	urusan dinding.
--]]

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config   = require(script.Parent.Config)
local Geometry = require(script.Parent.Geometry)
local Settings = require(script.Parent.Settings)
local Barrier  = require(script.Parent.Barrier)
local Zone     = require(script.Parent.Zone)

local ZoneService = {}

local S = Config.State

local zones: { [BasePart]: any } = {}      -- part -> Zone
local zoneOf: { [any]: any } = {}          -- player -> Zone (yang sedang melindunginya)
local started = false
local remote: RemoteEvent? = nil
local lastTick = 0

---------------------------------------------------------------------
-- PENDAFTARAN BILIK
---------------------------------------------------------------------

--- Publikasikan keadaan bilik sebagai Attribute pada Part-nya.
--- Kanal ini sengaja disediakan supaya tim bisa memasang efek (suara
--- pintu, lampu, partikel) TANPA menyentuh script ini — pola yang sama
--- dengan Attribute "AIState" milik EnemyController.
local function publish(zone: any)
	pcall(function()
		zone.part:SetAttribute("SafeZoneState", zone.state)
		zone.part:SetAttribute("SafeZoneBreath", math.floor(zone.breathLeft * 10) / 10)
	end)
end

function ZoneService:register(part: BasePart): boolean
	if not part:IsA("BasePart") or zones[part] then
		return false
	end

	for _, problem in Settings.validate(part) do
		warn("[SafeZone] " .. part:GetFullName() .. ": " .. problem)
	end

	local zone = Zone.new(part)
	zones[part] = zone

	Barrier.register(part)
	if zone:hasBarrier() then
		-- Bilik kosong = belum melindungi siapa pun = belum menahan monster.
		Barrier.setSolid(part, false)
	end

	publish(zone)
	return true
end

function ZoneService:unregister(part: BasePart)
	local zone = zones[part]
	if not zone then
		return
	end

	for who in zone.occupants do
		zoneOf[who] = nil
	end

	Barrier.unregister(part)
	zones[part] = nil
end

--- Pindai ulang seluruh Workspace. Aman dipanggil berkali-kali.
function ZoneService:scan(): number
	local found = 0
	for _, part in Geometry.gatherZoneParts() do
		if self:register(part) then
			found += 1
		end
	end
	return found
end

---------------------------------------------------------------------
-- PERTANYAAN DARI CORE AI
---------------------------------------------------------------------

--- Apakah karakter ini sedang DILINDUNGI (bukan cuma "berada di dalam").
--- Inilah bedanya dengan Safe Zone versi lama: berdiri di bilik yang
--- napasnya habis / penuh / hangus TIDAK melindungi.
function ZoneService:isProtected(character: Model?): boolean
	if not character then
		return false
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local zone = zoneOf[player]
		return zone ~= nil and zone:isProtecting() and zone:hasOccupant(player)
	end

	-- Karakter non-player (NPC teman, dummy uji): pakai bilik abadi saja.
	-- Bilik ber-napas memang dirancang untuk player (butuh UI & identitas).
	local root = Geometry.rootOf(character)
	if not root then
		return false
	end

	for _, zone in zones do
		if zone:isEternal() and Geometry.isPointInside(root.Position, zone.part) then
			return true
		end
	end

	return false
end

--- Keadaan bilik seorang player (untuk sistem lain: musik, SFX, UI server-side).
function ZoneService:stateOf(player: any): { [string]: any }?
	local zone = zoneOf[player]
	return zone and zone:snapshot() or nil
end

--- Daftar semua bilik + keadaannya (debug / dashboard).
function ZoneService:all(): { any }
	local list = {}
	for _, zone in zones do
		table.insert(list, zone:snapshot())
	end
	return list
end

---------------------------------------------------------------------
-- DETAK
---------------------------------------------------------------------

local function leaveZone(who: any, zone: any)
	zone:remove(who)
	if zoneOf[who] == zone then
		zoneOf[who] = nil
	end
end

--- Tentukan bilik setiap player, lalu majukan waktu semua bilik.
function ZoneService:step(dt: number)
	local parts = {}
	for part in zones do
		if part.Parent then
			table.insert(parts, part)
		else
			-- Bilik dihapus tim saat Play: bersihkan tanpa error.
			self:unregister(part)
		end
	end

	-- 1. Perbarui keanggotaan
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local alive = humanoid ~= nil and humanoid.Health > 0

		local insidePart = (char and alive) and Geometry.findContainingZone(char, parts) or nil
		local current = zoneOf[player]

		if current and (not insidePart or current.part ~= insidePart) then
			leaveZone(player, current)
			current = nil
		end

		if insidePart and not current then
			local zone = zones[insidePart]
			if zone then
				local denied = zone:tryAdd(player)
				if not denied then
					zoneOf[player] = zone
				end
			end
		end
	end

	-- 2. Majukan waktu tiap bilik + sinkronkan dinding
	for _, zone in zones do
		local wasProtecting = zone:isProtecting()
		zone:step(dt)

		if zone:hasBarrier() then
			local solid = zone:isProtecting()
			if solid ~= wasProtecting or zone.dirty then
				Barrier.setSolid(zone.part, solid)
			end
		end

		if zone.dirty then
			publish(zone)
		end
	end

	-- 3. Siarkan ke client (UI bar napas)
	if remote then
		for _, player in Players:GetPlayers() do
			local zone = zoneOf[player]
			if zone then
				if zone.dirty then
					local snap = zone:snapshot()
					remote:FireClient(player, {
						state    = snap.state,
						breath   = snap.breath,
						max      = snap.max,
						fraction = snap.fraction,
						count    = snap.count,
						capacity = snap.capacity,
						eternal  = snap.eternal,
					})
				end
			elseif self._wasShowing and self._wasShowing[player] then
				remote:FireClient(player, { state = "NONE" })
			end
		end

		self._wasShowing = {}
		for _, player in Players:GetPlayers() do
			self._wasShowing[player] = zoneOf[player] ~= nil
		end
	end

	for _, zone in zones do
		zone.dirty = false
	end
end

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------

local function ensureRemote(): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(Config.RemoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = Config.RemoteName
	ev.Parent = ReplicatedStorage
	return ev
end

--- Nyalakan sistem. Dipanggil sekali oleh SafeZoneController.
function ZoneService:start()
	if started then
		return
	end
	started = true

	Barrier.init()
	remote = ensureRemote()

	local found = self:scan()
	print(string.format("[SafeZone] %d bilik terdaftar (tag '%s' / folder '%s').",
		found, Config.SafeZoneTag, Config.SafeZoneFolder))

	CollectionService:GetInstanceAddedSignal(Config.SafeZoneTag):Connect(function(inst)
		if inst:IsA("BasePart") then
			self:register(inst)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(Config.SafeZoneTag):Connect(function(inst)
		if inst:IsA("BasePart") then
			self:unregister(inst)
		end
	end)

	-- Badan monster masuk CollisionGroup supaya kena dinding bilik.
	-- Mengikuti tag "Monster", jadi core AI tidak perlu diubah.
	for _, monster in CollectionService:GetTagged("Monster") do
		if monster:IsA("Model") then
			Barrier.markMonster(monster)
		end
	end
	CollectionService:GetInstanceAddedSignal("Monster"):Connect(function(inst)
		if inst:IsA("Model") then
			task.wait(0.5)  -- tunggu model selesai dimuat (pola yang sama dengan EnemyController)
			Barrier.markMonster(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("Monster"):Connect(function(inst)
		if inst:IsA("Model") then
			Barrier.unmarkMonster(inst)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local zone = zoneOf[player]
		if zone then
			leaveZone(player, zone)
		end
		if self._wasShowing then
			self._wasShowing[player] = nil
		end
	end)

	lastTick = os.clock()
	task.spawn(function()
		while true do
			task.wait(Config.TickInterval)
			local now = os.clock()
			local dt = now - lastTick
			lastTick = now
			local ok, err = pcall(function()
				self:step(dt)
			end)
			if not ok then
				warn("[SafeZone] Kesalahan pada detak: " .. tostring(err))
			end
		end
	end)
end

--- KHUSUS UJI: kosongkan seluruh state. Jangan dipanggil saat runtime.
function ZoneService:reset()
	for part in zones do
		Barrier.unregister(part)
	end
	zones = {}
	zoneOf = {}
	self._wasShowing = nil
	started = false
end

--- KHUSUS UJI: akses objek Zone sebuah part.
function ZoneService:zoneFor(part: BasePart): any
	return zones[part]
end

--- KHUSUS UJI: daftarkan penghuni palsu (edit mode tidak punya Player).
function ZoneService:_debugSetOccupant(part: BasePart, who: any): string?
	local zone = zones[part]
	if not zone then
		return "NO_ZONE"
	end
	local denied = zone:tryAdd(who)
	if not denied then
		zoneOf[who] = zone
	end
	return denied
end

return ZoneService
