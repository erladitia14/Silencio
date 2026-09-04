--[[
	ZoneService.luau
	----------------
	Otak sistem Safe Zone di SERVER. Satu-satunya pemilik state bilik.

	Tugasnya:
	  1. Menemukan bilik (tag "SafeZone" / Folder "SafeZones") dan membuat
	     objek Zone untuk masing-masing — termasuk bilik yang di-tag saat
	     game sudah jalan.
	  2. Memasang ProximityPrompt: pemain MENEKAN tombol untuk sembunyi,
	     karakternya dipindah ke dalam bilik dan dikunci di tempat.
	  3. Menjalankan detak: napas berkurang, cooldown, dinding monster.
	  4. MENGELUARKAN penghuni begitu napas habis (BREACHED) — inilah
	     bedanya dengan versi sebelumnya, di mana pemain tetap di dalam.
	  5. Menjawab core AI: "apakah karakter ini terlindungi?"
	  6. Menyiarkan keadaan ke client: bar napas + kamera mengintip.

	NOL KONFIGURASI: cukup tag Part-nya. Detail per bilik lewat Attribute.

	DUA CARA MASUK:
	  - default: ProximityPrompt (bilik toilet / lemari — "sembunyi")
	  - Attribute `TouchToEnter` = true: cukup berdiri di dalam area,
	    karakter tidak dipindah/dikunci (untuk ruang aman terbuka)
--]]

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config    = require(script.Parent.Config)
local Geometry  = require(script.Parent.Geometry)
local Settings  = require(script.Parent.Settings)
local Barrier   = require(script.Parent.Barrier)
local Zone      = require(script.Parent.Zone)
local Anchors   = require(script.Parent.Anchors)
local Occupancy = require(script.Parent.Occupancy)
local Prompt    = require(script.Parent.PromptManager)

local ZoneService = {}

local S = Config.State
local E = Config.Event

local zones:  { [BasePart]: any } = {}   -- part -> Zone
local zoneOf: { [any]: any }      = {}   -- player -> Zone yang menampungnya
local started = false
local remote: RemoteEvent? = nil
local lastTick = 0

---------------------------------------------------------------------
-- KOMUNIKASI KE CLIENT
---------------------------------------------------------------------

local function fire(player: any, payload: { [string]: any })
	-- Player palsu (uji perilaku di edit mode) tidak punya FireClient. Payload-nya
	-- dicatat ke outbox supaya alur pesan tetap BISA DIVERIFIKASI — tanpa ini,
	-- perbaikan seperti "kirim NONE setelah ditolak" cuma bisa diyakini,
	-- tidak bisa dibuktikan.
	--
	-- Dicek SEBELUM `remote`: uji tidak memanggil start(), jadi remote-nya nil
	-- dan pencatatan tidak akan pernah jalan kalau urutannya dibalik.
	if typeof(player) ~= "Instance" then
		if ZoneService._outbox then
			local box = ZoneService._outbox[player]
			if not box then
				box = {}
				ZoneService._outbox[player] = box
			end
			table.insert(box, payload)
		end
		return
	end
	if not remote then
		return
	end
	remote:FireClient(player, payload)
end

--- Kirim pembaruan bar napas.
local function sendState(player: any, zone: any?)
	if not zone then
		fire(player, { kind = E.STATE, state = "NONE" })
		return
	end
	local snap = zone:snapshot()
	fire(player, {
		kind     = E.STATE,
		state    = snap.state,
		breath   = snap.breath,
		max      = snap.max,
		fraction = snap.fraction,
		count    = snap.count,
		capacity = snap.capacity,
		eternal  = snap.eternal,
	})
end

--- Suruh client memasang kamera "mengintip" + transisi gelap.
--- Kamera diurus CLIENT karena Camera itu objek lokal; server cuma
--- memberi titik intip dan arah pintu.
local function sendEnter(player: any, zone: any)
	local peek = Anchors.peek(zone.part)
	fire(player, {
		kind      = E.ENTER,
		zone      = zone.part,
		peekCF    = peek,
		doorDir   = Anchors.doorDirection(zone.part),
		fade      = Config.FadeTime,
		yawLimit  = Config.PeekYawLimit,
		pitchLimit = Config.PeekPitchLimit,
		sensitivity = Config.PeekSensitivity,
	})
end

--- Suruh client mengembalikan kamera normal.
--- @param forced  true = diusir karena napas habis (bukan keluar sendiri)
local function sendExit(player: any, forced: boolean)
	fire(player, { kind = E.EXIT, fade = Config.FadeTime, forced = forced })
end

---------------------------------------------------------------------
-- PENDAFTARAN BILIK
---------------------------------------------------------------------

--- Publikasikan keadaan bilik sebagai Attribute pada Part-nya sendiri.
--- Kanal untuk efek tim (suara pintu, lampu, partikel) TANPA menyentuh
--- script ini — pola yang sama dengan Attribute "AIState" milik EnemyController.
local function publish(zone: any)
	pcall(function()
		zone.part:SetAttribute("SafeZoneState", zone.state)
		zone.part:SetAttribute("SafeZoneBreath", math.floor(zone.breathLeft * 10) / 10)
	end)
end

--- Pemain menekan prompt: masuk kalau di luar, keluar kalau di dalam.
local function onPromptTriggered(part: BasePart, player: Player)
	local zone = zones[part]
	if not zone then
		return
	end

	-- Sudah di dalam bilik INI -> prompt berfungsi sebagai tombol keluar.
	if zone:hasOccupant(player) then
		ZoneService:leave(player, false)
		return
	end

	ZoneService:enter(player, zone)
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

	if zone:usesPrompt() then
		Prompt.attach(part, onPromptTriggered)
	end

	publish(zone)
	return true
end

function ZoneService:unregister(part: BasePart)
	local zone = zones[part]
	if not zone then
		return
	end

	-- Lepaskan penghuni SEBELUM bilik hilang, kalau tidak mereka
	-- terkunci selamanya (Anchored, WalkSpeed 0).
	for who in zone.occupants do
		if Occupancy.isHidden(who) then
			Occupancy.exit(who, self:_characterOf(who), part)
			sendExit(who, true)
		end
		zoneOf[who] = nil
		sendState(who, nil)
	end

	Prompt.detach(part)
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
-- MASUK / KELUAR
---------------------------------------------------------------------

function ZoneService:_characterOf(player: any): Model?
	if typeof(player) == "Instance" then
		return (player :: Player).Character
	end
	-- Player palsu untuk uji perilaku.
	return (player :: any).Character
end

--- Masukkan pemain ke bilik (sembunyi).
--- @return string?  nil = berhasil; "FULL"/"COOLDOWN"/"BREACHED"/... = gagal
function ZoneService:enter(player: any, zone: any): string?
	-- Satu pemain tidak boleh menempati dua bilik.
	if zoneOf[player] then
		return "ALREADY_IN_ZONE"
	end

	local character = self:_characterOf(player)
	if not character then
		return "NO_CHARACTER"
	end

	-- Cek kuota/keadaan bilik DULU, baru pindahkan karakter — supaya
	-- pemain tidak sempat tergeser ke dalam bilik yang menolaknya.
	local denied = zone:tryAdd(player)
	if denied then
		-- Tampilkan alasan penolakan sekejap, LALU sembunyikan lagi.
		-- Tanpa `NONE` menyusul, pesan "the stall is spent" nempel di layar
		-- selamanya karena pemain ini tidak pernah jadi penghuni — jadi tidak
		-- ada jalur lain yang akan membersihkannya. (bug dari playtest Aer)
		sendState(player, zone)
		task.delay(Config.DeniedNoticeTime, function()
			if not zoneOf[player] then
				sendState(player, nil)
			end
		end)
		return denied
	end

	if zone:usesPrompt() then
		local ok, why = Occupancy.enter(player, character, zone.part)
		if not ok then
			-- Batalkan keanggotaan: jangan biarkan bilik "terpakai" oleh
			-- pemain yang gagal masuk.
			zone:remove(player)
			return why
		end
		Prompt.setOccupied(zone.part, true)
		sendEnter(player, zone)
	end

	zoneOf[player] = zone
	sendState(player, zone)
	return nil
end

--- Keluarkan pemain dari bilik.
--- @param forced  true = diusir karena napas habis
function ZoneService:leave(player: any, forced: boolean)
	local zone = zoneOf[player]
	if not zone then
		return
	end

	local usesPrompt = zone:usesPrompt()

	zone:remove(player)
	zoneOf[player] = nil

	if usesPrompt then
		if Occupancy.isHidden(player) then
			Occupancy.exit(player, self:_characterOf(player), zone.part)
		end
		Prompt.setOccupied(zone.part, zone.count > 0)
		sendExit(player, forced)
	end

	sendState(player, nil)
end

---------------------------------------------------------------------
-- PERTANYAAN DARI CORE AI
---------------------------------------------------------------------

--- Apakah karakter ini sedang DILINDUNGI (bukan cuma "berada di dalam").
--- Berdiri di bilik yang napasnya habis / penuh / hangus TIDAK melindungi.
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

--- Keadaan bilik seorang player (untuk sistem lain: musik, SFX, dsb).
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

--- Bilik bertipe sentuh: keanggotaan mengikuti posisi karakter.
function ZoneService:_updateTouchZones(parts: { BasePart })
	local touchParts = {}
	for _, part in parts do
		local zone = zones[part]
		if zone and not zone:usesPrompt() then
			table.insert(touchParts, part)
		end
	end
	if #touchParts == 0 then
		return
	end

	for _, player in Players:GetPlayers() do
		local current = zoneOf[player]
		-- Jangan ganggu pemain yang sedang sembunyi di bilik prompt.
		if not (current and current:usesPrompt()) then
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local alive = humanoid ~= nil and humanoid.Health > 0
			local insidePart = (char and alive)
				and Geometry.findContainingZone(char, touchParts) or nil

			if current and (not insidePart or current.part ~= insidePart) then
				self:leave(player, false)
				current = nil
			end
			if insidePart and not current then
				self:enter(player, zones[insidePart])
			end
		end
	end
end

--- Usir semua penghuni bilik yang napasnya habis.
function ZoneService:_ejectBreached()
	for _, zone in zones do
		if zone.state == S.BREACHED and zone.count > 0 then
			local victims = {}
			for who in zone.occupants do
				table.insert(victims, who)
			end
			for _, who in victims do
				self:leave(who, true)
			end
		end
	end
end

--- Karakter penghuni hilang/mati saat sembunyi: bersihkan supaya bilik
--- tidak terkunci oleh pemain yang sudah tidak ada.
---
--- Iterasi lewat DAFTAR PENGHUNI, bukan Players:GetPlayers() — penghuni
--- yang sudah keluar server tidak lagi muncul di Players, jadi kalau
--- kita menyapu dari sisi Players, catatannya justru tertinggal selamanya.
function ZoneService:_pruneDeadOccupants()
	local stale = {}

	for _, zone in zones do
		for who in zone.occupants do
			local char = self:_characterOf(who)
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local gone = not char
				or not char.Parent
				or (humanoid ~= nil and humanoid.Health <= 0)
			if gone then
				table.insert(stale, { who = who, zone = zone })
			end
		end
	end

	for _, entry in stale do
		local who, zone = entry.who, entry.zone
		-- forget(): karakternya sudah mati/hilang, memulihkan WalkSpeed pada
		-- karakter lama tidak ada guna — tapi kunci Anchored tetap dilepas
		-- kalau karakternya masih ada, kalau tidak ia tertinggal dan
		-- membuat pemain terkunci permanen di sesi berikutnya.
		Occupancy.forget(who, self:_characterOf(who))
		zone:remove(who)
		zoneOf[who] = nil
		if zone:usesPrompt() then
			Prompt.setOccupied(zone.part, zone.count > 0)
		end
		sendState(who, nil)
	end
end

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

	self:_pruneDeadOccupants()
	self:_updateTouchZones(parts)

	-- Majukan waktu tiap bilik + sinkronkan dinding
	for _, zone in zones do
		local wasProtecting = zone:isProtecting()
		zone:step(dt)

		if zone:hasBarrier() then
			local solid = zone:isProtecting()
			if solid ~= wasProtecting or zone.dirty then
				Barrier.setSolid(zone.part, solid)
			end
		end
	end

	-- Siarkan bar napas ke penghuni SEBELUM pengusiran, supaya pemain
	-- sempat melihat "Napas habis!" — kalau diusir dulu, ia cuma melihat
	-- layar gelap tanpa tahu kenapa.
	for _, zone in zones do
		if zone.dirty then
			for who in zone.occupants do
				sendState(who, zone)
			end
		end
	end

	-- Napas habis -> penghuni DIKELUARKAN (permintaan Aer: jangan biarkan
	-- pemain tetap di dalam setelah "Napas habis!").
	self:_ejectBreached()

	-- Terbitkan Attribute PALING AKHIR: pengusiran mengubah state lagi
	-- (BREACHED -> COOLDOWN saat bilik jadi kosong), jadi kalau diterbitkan
	-- sebelum itu, efek buatan tim akan membaca keadaan yang sudah basi.
	for _, zone in zones do
		if zone.dirty then
			publish(zone)
			zone.dirty = false
		end
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
			task.wait(0.5)  -- tunggu model selesai dimuat (pola EnemyController)
			Barrier.markMonster(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("Monster"):Connect(function(inst)
		if inst:IsA("Model") then
			Barrier.unmarkMonster(inst)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		Occupancy.forget(player, player.Character)
		local zone = zoneOf[player]
		if zone then
			zone:remove(player)
			zoneOf[player] = nil
			if zone:usesPrompt() then
				Prompt.setOccupied(zone.part, zone.count > 0)
			end
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

---------------------------------------------------------------------
-- KHUSUS UJI (jangan dipanggil runtime)
---------------------------------------------------------------------

function ZoneService:reset()
	for part in zones do
		Prompt.detach(part)
		Barrier.unregister(part)
	end
	zones = {}
	zoneOf = {}
	Occupancy._reset()
	self._outbox = nil
	started = false
end

function ZoneService:zoneFor(part: BasePart): any
	return zones[part]
end

--- KHUSUS UJI: mulai merekam payload yang dikirim ke player palsu.
function ZoneService:_recordOutbox()
	self._outbox = {}
end

--- KHUSUS UJI: daftar `kind`/`state` pesan yang diterima seorang player palsu.
function ZoneService:_outboxFor(who: any): { string }
	local list = {}
	for _, payload in (self._outbox and self._outbox[who] or {}) do
		table.insert(list, tostring(payload.kind) .. ":" .. tostring(payload.state))
	end
	return list
end

--- Daftarkan penghuni palsu (edit mode tidak punya Player nyata).
function ZoneService:_debugSetOccupant(part: BasePart, who: any): string?
	local zone = zones[part]
	if not zone then
		return "NO_ZONE"
	end
	return self:enter(who, zone)
end

return ZoneService
