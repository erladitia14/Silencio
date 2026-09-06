--[[
	SkinAnimator.luau
	-----------------
	Memutar animasi pada MESH VISUAL (skin) mengikuti keadaan AI.

	KENAPA MODUL TERPISAH DARI AnimationManager:
	  AnimationManager memutar animasi lewat `Humanoid` milik rig. Pada pola
	  "driver + skin", yang punya tulang/animasi justru MESH-nya, dan mesh itu
	  dianimasikan lewat `AnimationController` — bukan Humanoid. Jadi
	  AnimationManager tidak bisa menyentuhnya sama sekali.

	CARA KERJA:
	  Rig menyiarkan keadaannya lewat Attribute "AIState" (IDLE / PATROL /
	  CHASING / ATTACKING / DEAD) dan BindableEvent "AISignal". Modul ini
	  mendengarkan keduanya, lalu memutar animasi skin yang sesuai.

	DARI MANA ID ANIMASI DIAMBIL (per state, urutan prioritas):
	  1. folder "Animations" di dalam SKIN   -> Animation bernama Idle/Walk/Run/Attack/Death
	  2. Animation object mana pun di skin   -> dipakai sebagai animasi tunggal (fallback)
	  Nama TIDAK case-sensitive.

	KALAU SKIN CUMA PUNYA SATU ANIMASI:
	  Animasi itu dipakai untuk semua state (lebih baik daripada NPC kaku).
	  Tambahkan Animation bernama "Run"/"Attack" dst di folder "Animations"
	  untuk membedakan per state — tanpa mengubah script apa pun.
--]]

local SkinAnimator = {}
SkinAnimator.__index = SkinAnimator

--- Animasi yang dipakai untuk tiap state AI.
local STATE_ANIM = {
	IDLE      = "Idle",
	PATROL    = "Walk",
	CHASING   = "Run",
	ATTACKING = "Attack",
	DEAD      = "Death",
}

--- Nama animasi yang dicari (urutan ini juga dipakai saat melapor ke Output).
local ANIM_NAMES = { "Idle", "Walk", "Run", "Attack", "Death" }

--- Cari anak berdasarkan nama, tanpa membedakan huruf besar/kecil.
local function findChildInsensitive(parent: Instance?, name: string): Instance?
	if not parent then return nil end
	local wanted = string.lower(name)
	for _, child in parent:GetChildren() do
		if string.lower(child.Name) == wanted then
			return child
		end
	end
	return nil
end

--- Ambil AnimationId dari node: Animation langsung, atau wrapper yang
--- membungkus Animation di dalamnya.
local function extractAnimId(node: Instance?): string?
	if not node then return nil end
	if node:IsA("Animation") and node.AnimationId ~= "" then
		return node.AnimationId
	end
	local inner = node:FindFirstChildOfClass("Animation")
	if inner and inner.AnimationId ~= "" then
		return inner.AnimationId
	end
	return nil
end

--- Animation pertama yang ditemukan di dalam skin (fallback animasi tunggal).
local function firstAnimId(skin: Instance): string?
	for _, d in skin:GetDescendants() do
		if d:IsA("Animation") and d.AnimationId ~= "" then
			return d.AnimationId
		end
	end
	return nil
end

--- Buat animator untuk sebuah skin. Mengembalikan nil bila skin tidak punya
--- AnimationController/Humanoid (berarti memang tidak bisa dianimasikan).
function SkinAnimator.new(skin: Instance)
	local controller = skin:FindFirstChildOfClass("AnimationController")
		or skin:FindFirstChildOfClass("Humanoid")
	if not controller then
		return nil
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	local self = setmetatable({}, SkinAnimator)
	self._skin = skin
	self._animator = animator
	self._tracks = {} :: { [string]: AnimationTrack }
	self._sources = {} :: { [string]: string }
	-- AnimationId -> track, supaya ID yang sama tidak dimuat berkali-kali.
	-- Penting untuk kasus fallback tunggal: tanpa ini 5 state = 5 track
	-- identik, dan berpindah state jadi stop/play animasi yang sama (tersendat).
	self._byId = {} :: { [string]: AnimationTrack }
	self._current = nil :: AnimationTrack?
	self._currentName = ""
	self._connections = {} :: { RBXScriptConnection }

	self:_loadTracks()
	return self
end

--- Muat semua track yang tersedia; laporkan asal tiap animasi.
function SkinAnimator:_loadTracks()
	local folder = findChildInsensitive(self._skin, "Animations")
	local fallback = firstAnimId(self._skin)

	for _, name in ANIM_NAMES do
		local id, source

		local fromFolder = folder and extractAnimId(findChildInsensitive(folder, name))
		if fromFolder then
			id, source = fromFolder, "Animations/" .. name
		elseif fallback then
			-- Skin cuma punya satu animasi -> pakai untuk semua state.
			id, source = fallback, "fallback-tunggal"
		end

		if id then
			-- Satu AnimationId = satu track. State yang memakai ID sama akan
			-- BERBAGI track, sehingga perpindahan state tidak menghentikan lalu
			-- memulai ulang animasi yang sama persis.
			local track = self._byId[id]
			if not track then
				local anim = Instance.new("Animation")
				anim.AnimationId = id
				local ok, loadedTrack = pcall(function()
					return self._animator:LoadAnimation(anim)
				end)
				if ok and loadedTrack then
					track = loadedTrack
					self._byId[id] = track
				end
			end

			if track then
				self._tracks[name] = track
				self._sources[name] = source
			else
				self._sources[name] = (source or "?") .. " (GAGAL LOAD)"
			end
		else
			self._sources[name] = "TIDAK ADA"
		end
	end

	local report = {}
	for _, name in ANIM_NAMES do
		table.insert(report, string.format("%s:%s(%s)", name,
			self._tracks[name] and "OK" or "-", self._sources[name]))
	end
	print("[SkinAnimator] " .. self._skin.Name .. " -> " .. table.concat(report, " "))
end

--- Putar animasi looping untuk sebuah state.
function SkinAnimator:playLoop(name: string, fade: number?)
	local track = self._tracks[name]
	if not track then return end

	-- Sudah memainkan animasi yang sama (mis. semua state pakai fallback
	-- yang sama) -> jangan restart, biar gerakannya tidak tersendat.
	if self._current == track and track.IsPlaying then
		self._currentName = name
		return
	end

	local fadeTime = fade or 0.25
	if self._current and self._current ~= track then
		self._current:Stop(fadeTime)
	end

	self._current = track
	self._currentName = name
	track.Looped = true
	if not track.IsPlaying then
		track:Play(fadeTime)
	end
end

--- Putar animasi sekali (untuk kejadian seperti Attack).
--- Mengembalikan false bila animasinya tidak tersedia.
function SkinAnimator:playOnce(name: string): boolean
	local track = self._tracks[name]
	if not track then return false end

	-- Kalau animasi ini sama dengan yang sedang looping (kasus fallback
	-- tunggal), jangan diganggu: memutarnya ulang malah bikin tersendat.
	if self._current == track then
		return true
	end

	track.Looped = false
	track:Play(0.1)
	return true
end

--- Terapkan state AI ke animasi skin.
function SkinAnimator:applyState(state: string?)
	if not state then return end
	local animName = STATE_ANIM[state]
	if animName then
		-- Gunakan fade time 0.35s agar transisi antar-state (Walk <-> Idle) mengalir halus (smooth blend)
		self:playLoop(animName, 0.35)
	end
end

--- Sambungkan ke rig: ikuti Attribute "AIState" + BindableEvent "AISignal".
function SkinAnimator:bindTo(rig: Model)
	-- Keadaan (idle / patrol / chase / dead)
	local stateConn = rig:GetAttributeChangedSignal("AIState"):Connect(function()
		self:applyState(rig:GetAttribute("AIState"))
	end)
	table.insert(self._connections, stateConn)

	-- Kejadian sekejap (serangan, mati)
	local signal = rig:FindFirstChild("AISignal")
	if signal and signal:IsA("BindableEvent") then
		local evConn = signal.Event:Connect(function(eventName)
			if eventName == "Attack" then
				self:playOnce("Attack")
			elseif eventName == "Died" then
				self:playLoop("Death", 0.1)
			end
		end)
		table.insert(self._connections, evConn)
	end

	-- Terapkan state yang sedang berlaku (AI mungkin sudah jalan)
	self:applyState(rig:GetAttribute("AIState"))
end

--- Lepas semua koneksi & hentikan animasi.
function SkinAnimator:destroy()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	self._connections = {}

	-- Iterasi _byId, bukan _tracks: beberapa state bisa BERBAGI track yang
	-- sama, jadi _tracks memuat entri duplikat.
	for _, track in self._byId do
		track:Stop()
		track:Destroy()
	end
	self._byId = {}
	self._tracks = {}
	self._current = nil
end

return SkinAnimator
