--[[
	AnimationManager.luau
	---------------------
	Mengelola animasi NPC monster di sisi server, OTOMATIS.

	TUJUAN: cukup beri tag "Monster" pada Model NPC -> NPC langsung
	patrol/chase/idle LENGKAP dengan animasi. Tanpa menempel script
	tambahan, tanpa mengisi ID animasi manual.

	DARI MANA ID ANIMASI DIAMBIL (urutan prioritas):
	  1. Folder "Animations" di dalam Model      -> untuk animasi custom (mis. Attack)
	  2. Paket "Animate" bawaan rig Roblox       -> idle/walk/run/jump/fall sudah ada di sini
	  3. ID default Roblox (R6/R15)              -> jaring pengaman terakhir

	Pencocokan nama TIDAK case-sensitive: "Idle" cocok dengan "idle",
	"Walk" dengan "walk", dst. Rig Roblox menamai anaknya huruf kecil,
	jadi tanpa ini animasi asli NPC terabaikan diam-diam.

	CATATAN PENTING:
	  - Script "Animate" bawaan Roblox berupa LocalScript, TIDAK jalan
	    pada NPC di Workspace. Modul ini menggantikan perannya dari server.
	  - Hanya SATU pihak yang boleh menyetir Animator. Kalau tim ingin
	    mengurus animasi NPC sendiri, beri Attribute "NoAutoAnimations" = true
	    pada Model, lalu pakai kanal "AIState" + "AISignal" dari EnemyController.
--]]

local AnimationManager = {}
AnimationManager.__index = AnimationManager

-- Pemetaan STATE FSM (Attribute "AIState" yang di-publish EnemyController)
-- -> nama animasi. INI sumber kebenaran animasi, BUKAN kecepatan.
--
-- ATTACKING -> Idle (berdiri; WalkSpeed=0 di state itu). Ayunan serangan tetap
-- dipicu terpisah oleh playAttack(), jadi animasi Attack
-- tidak ikut di-loop di sini.
local STATE_TO_ANIM = {
	IDLE      = "Idle",
	PATROL    = "Walk",
	CHASING   = "Run",
	ATTACKING = "Idle",
}

-- Fallback berjenjang bila animasi state tidak tersedia di rig ini.
local ANIM_FALLBACK = {
	Run  = "Walk",
	Walk = "Idle",
}

-- Animation ID bawaan Roblox (R15 & R6) — jaring pengaman terakhir
local DEFAULT_ANIMS = {
	R15 = {
		Idle  = "rbxassetid://507766388",
		Walk  = "rbxassetid://913402848",
		Run   = "rbxassetid://913376220",
		Jump  = "rbxassetid://507765000",
		Fall  = "rbxassetid://507767968",
	},
	R6 = {
		Idle  = "rbxassetid://180435571",
		Walk  = "rbxassetid://180436334",
		Run   = "rbxassetid://180436334",
		Jump  = "rbxassetid://125750702",
		Fall  = "rbxassetid://180436148",
	},
}

--- Cari anak berdasarkan nama, TANPA membedakan huruf besar/kecil.
local function findChildInsensitive(parent: Instance?, name: string): Instance?
	if not parent then return nil end
	local wanted = string.lower(name)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == wanted then
			return child
		end
	end
	return nil
end

--- Ambil AnimationId dari sebuah node: bisa Animation langsung,
--- atau StringValue/Folder yang membungkus Animation di dalamnya
--- (bentuk paket "Animate" bawaan Roblox: Animate/idle/Animation1).
local function extractAnimId(node: Instance?): string?
	if not node then return nil end

	if node:IsA("Animation") and node.AnimationId ~= "" then
		return node.AnimationId
	end

	-- Wrapper: ambil Animation pertama di dalamnya
	local inner = node:FindFirstChildOfClass("Animation")
	if inner and inner.AnimationId ~= "" then
		return inner.AnimationId
	end

	return nil
end

--- Membuat instance AnimationManager baru untuk monster model.
function AnimationManager.new(monsterModel: Model)
	local self = setmetatable({}, AnimationManager)

	self._model = monsterModel
	self._humanoid = monsterModel:FindFirstChildOfClass("Humanoid") :: Humanoid
	assert(self._humanoid, "[AnimationManager] Model '" .. monsterModel.Name .. "' tidak memiliki Humanoid!")

	-- Pastikan Animator ada di dalam Humanoid
	self._animator = self._humanoid:FindFirstChildOfClass("Animator")
	if not self._animator then
		self._animator = Instance.new("Animator")
		self._animator.Parent = self._humanoid
	end

	self._rigType = (self._humanoid.RigType == Enum.HumanoidRigType.R6) and "R6" or "R15"
	self._tracks = {} :: { [string]: AnimationTrack }
	self._currentTrack = nil :: AnimationTrack?
	self._currentAnimName = "" :: string
	self._connections = {} :: { RBXScriptConnection }
	self._completionConnections = {} :: { [AnimationTrack]: RBXScriptConnection }
	self._sources = {} :: { [string]: string }  -- dari mana tiap animasi didapat (untuk log)

	-- Apakah rig ini BONE-BASED (mesh import: punya Bone, tanpa Motor6D)?
	--
	-- KENAPA PENTING: animasi DEFAULT Roblox (DEFAULT_ANIMS) dibuat untuk rig
	-- karakter Roblox yang sendinya Motor6D bernama "Torso"/"Left Leg"/dst.
	-- Mesh import (Mixamo dsb) tidak punya Motor6D sama sekali -- sendinya
	-- Bone. Animasi default TETAP ter-load (Length > 0) tapi TIDAK menggerakkan
	-- bone apa pun -> mesh diam di rest pose = T-POSE.
	--
	-- Jadi untuk rig bone-based, default Roblox TIDAK BOLEH dipakai sebagai
	-- fallback: lebih baik tidak ada animasi (mesh tetap seperti sekarang)
	-- daripada dipaksa memutar track yang tidak nyambung lalu T-pose.
	local hasMotor6D, hasBone = false, false
	for _, d in ipairs(monsterModel:GetDescendants()) do
		if d:IsA("Bone") then
			hasBone = true
		elseif d:IsA("Motor6D") then
			hasMotor6D = true
		end
	end
	self._boneBased = hasBone and not hasMotor6D

	self:_loadAnimations()
	self:_setupStateListeners()

	return self
end

--- Cari AnimationId untuk sebuah nama animasi.
--- Mengembalikan (animId, sumber) supaya bisa dilaporkan ke Output.
function AnimationManager:_getAnimId(name: string): (string?, string)
	-- 1. Folder "Animations" custom di dalam model (prioritas tertinggi)
	local animFolder = findChildInsensitive(self._model, "Animations")
	if animFolder then
		local id = extractAnimId(findChildInsensitive(animFolder, name))
		if id then
			return id, "Animations/" .. name
		end
	end

	-- 2. Paket "Animate" bawaan rig Roblox (idle/walk/run/jump/fall/...)
	local animateObj = findChildInsensitive(self._model, "Animate")
	if animateObj then
		local id = extractAnimId(findChildInsensitive(animateObj, name))
		if id then
			return id, "Animate/" .. name
		end
	end

	-- 3. ID default Roblox
	--
	-- SKIP untuk rig BONE-BASED (lihat self._boneBased di new()): animasi default
	-- menargetkan Motor6D milik karakter Roblox, jadi pada mesh import (Bone,
	-- tanpa Motor6D) ia ter-load tapi TIDAK menggerakkan apa pun -> T-POSE.
	-- Lebih baik mengembalikan "tidak ada" supaya play() tidak menghentikan
	-- animasi yang sedang berjalan.
	if self._boneBased then
		return nil, "TIDAK ADA (rig bone-based, default Roblox dilewati)"
	end

	local defaults = DEFAULT_ANIMS[self._rigType]
	local fallback = defaults[name]
	if fallback then
		return fallback, "default-" .. self._rigType
	end

	-- Tidak ada sama sekali (mis. "Attack" tanpa aset) -> jangan paksa Idle,
	-- biar pemanggil tahu animasi ini memang tidak tersedia.
	return nil, "TIDAK ADA"
end

--- Helper untuk memuat dan menyimpan AnimationTrack
function AnimationManager:_loadTrack(name: string): AnimationTrack?
	local animId, source = self:_getAnimId(name)
	self._sources[name] = source

	if not animId then return nil end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local success, track = pcall(function()
		return self._animator:LoadAnimation(anim)
	end)

	if success and track then
		self._tracks[name] = track
		return track
	end

	self._sources[name] = source .. " (GAGAL LOAD)"
	return nil
end

--- Memuat semua track animasi utama
function AnimationManager:_loadAnimations()
	for _, name in ipairs({ "Idle", "Walk", "Run", "Jump", "Fall", "Attack", "Jumpscare" }) do
		self:_loadTrack(name)
	end

	-- Laporkan hasil supaya jelas animasi mana yang aktif & dari mana asalnya
	local report = {}
	for _, name in ipairs({ "Idle", "Walk", "Run", "Jump", "Fall", "Attack", "Jumpscare" }) do
		local mark = self._tracks[name] and "OK" or "-"
		table.insert(report, string.format("%s:%s(%s)", name, mark, self._sources[name] or "?"))
	end
	print("[AnimationManager] " .. self._model.Name .. " -> " .. table.concat(report, " "))
end

--- Memainkan track animasi berdasarkan nama
function AnimationManager:play(name: string, transitionTime: number?)
	if self._currentAnimName == name and self._currentTrack and self._currentTrack.IsPlaying then
		return
	end

	local track = self._tracks[name]
	if not track then
		track = self:_loadTrack(name)
	end

	if not track then return end

	local fadeTime = transitionTime or 0.25

	local previous = self._currentTrack
	self._currentTrack = track
	self._currentAnimName = name
	if previous and previous ~= track then
		previous:Stop(fadeTime)
	end

	if not track.IsPlaying then
		track.Looped = true
		track:Play(fadeTime)
	end
end

--- Animasi dasar mengikuti STATE AI, bukan speed sesaat antar-waypoint.
--- Jump/Fall sementara mengikuti state fisik; mendarat kembali ke state AI.
function AnimationManager:playState(stateName: string?)
	if stateName == "DEAD" then
		self._currentTrack = nil
		self._currentAnimName = ""
		for _, track in pairs(self._tracks) do
			track:Stop(0.1)
		end
		return
	end

	local animName = STATE_TO_ANIM[stateName or "IDLE"]
	if not animName then return end

	-- Jangan potong jumpscare, atau ayunan serangan yang masih berlangsung.
	if self._currentTrack and self._currentTrack.IsPlaying then
		if self._currentAnimName == "Jumpscare"
			or (self._currentAnimName == "Attack" and stateName == "ATTACKING") then
			return
		end
	end

	local physical = self._humanoid:GetState()
	if physical == Enum.HumanoidStateType.Jumping and self._tracks.Jump then
		animName = "Jump"
	elseif physical == Enum.HumanoidStateType.Freefall and self._tracks.Fall then
		animName = "Fall"
	end

	-- Bone rig tanpa Run memakai track Walk yang SAMA, bukan default R6.
	while animName do
		if self._tracks[animName] then
			self:play(animName)
			return
		end
		animName = ANIM_FALLBACK[animName]
	end
end

function AnimationManager:_setupStateListeners()
	local stateConn = self._model:GetAttributeChangedSignal("AIState"):Connect(function()
		self:playState(self._model:GetAttribute("AIState"))
	end)
	table.insert(self._connections, stateConn)

	-- Tidak memakai Humanoid.Running: speed sempat nol bukan berarti IDLE.
	-- StateChanged dipakai hanya untuk masuk/keluar animasi udara & kematian.
	local function isAir(state)
		return state == Enum.HumanoidStateType.Jumping
			or state == Enum.HumanoidStateType.Freefall
	end
	local physicalConn = self._humanoid.StateChanged:Connect(function(oldState, newState)
		if newState == Enum.HumanoidStateType.Dead then
			self:playState("DEAD")
		elseif isAir(oldState) or isAir(newState) then
			self:playState(self._model:GetAttribute("AIState"))
		end
	end)
	table.insert(self._connections, physicalConn)
	self:playState(self._model:GetAttribute("AIState"))
end

--- One-shot mempertahankan API Attack/Jumpscare yang sudah dipakai controller.
--- Setelah selesai, kembali ke state TERKINI; callback track lama tidak boleh
--- mengambil alih track baru yang sudah menggantikannya.
function AnimationManager:_playOneShot(name: string): boolean
	local track = self._tracks[name] or self:_loadTrack(name)
	if not track then return false end

	if not self._completionConnections[track] then
		local conn = track.Stopped:Connect(function()
			if self._currentTrack ~= track then return end
			self._currentTrack = nil
			self._currentAnimName = ""
			self:playState(self._model:GetAttribute("AIState"))
		end)
		self._completionConnections[track] = conn
		table.insert(self._connections, conn)
	end

	local previous = self._currentTrack
	self._currentTrack = track
	self._currentAnimName = name
	if previous and previous ~= track then
		previous:Stop(0.1)
	end
	if not track.IsPlaying then
		track.Looped = false
		track:Play(0.1)
	end
	return true
end

function AnimationManager:playAttack(): boolean
	if self._currentAnimName == "Jumpscare" and self._currentTrack
		and self._currentTrack.IsPlaying then
		return false
	end
	return self:_playOneShot("Attack")
end

function AnimationManager:playJumpscare(): boolean
	return self:_playOneShot("Jumpscare")
end

--- Cleanup event connections saat monster dibersihkan
function AnimationManager:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	self._completionConnections = {}
	self._currentTrack = nil
	self._currentAnimName = ""

	for _, track in pairs(self._tracks) do
		track:Stop()
		track:Destroy()
	end
	self._tracks = {}
end

return AnimationManager
