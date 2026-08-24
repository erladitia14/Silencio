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

local Config = require(script.Parent.Config)

local AnimationManager = {}
AnimationManager.__index = AnimationManager

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
	self._sources = {} :: { [string]: string }  -- dari mana tiap animasi didapat (untuk log)

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
	for _, name in ipairs({ "Idle", "Walk", "Run", "Jump", "Fall", "Attack" }) do
		self:_loadTrack(name)
	end

	-- Laporkan hasil supaya jelas animasi mana yang aktif & dari mana asalnya
	local report = {}
	for _, name in ipairs({ "Idle", "Walk", "Run", "Jump", "Fall", "Attack" }) do
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

	if self._currentTrack and self._currentTrack ~= track then
		self._currentTrack:Stop(fadeTime)
	end

	self._currentTrack = track
	self._currentAnimName = name

	if not track.IsPlaying then
		track.Looped = true
		track:Play(fadeTime)
	end
end

--- Memasang event listeners pada Humanoid untuk auto-animation saat bergerak
function AnimationManager:_setupStateListeners()
	-- Event saat pergerakan (speed) berubah
	local runConn = self._humanoid.Running:Connect(function(speed)
		if speed > 0.1 then
			if speed > (Config.PatrolSpeed + 2) then
				self:play("Run")
			else
				self:play("Walk")
			end
		else
			self:play("Idle")
		end
	end)
	table.insert(self._connections, runConn)

	-- Event saat melompat
	local jumpConn = self._humanoid.Jumping:Connect(function()
		self:play("Jump", 0.1)
	end)
	table.insert(self._connections, jumpConn)

	-- Event saat melayang/jatuh
	local freefallConn = self._humanoid.FreeFalling:Connect(function(active)
		if active then
			self:play("Fall", 0.1)
		end
	end)
	table.insert(self._connections, freefallConn)

	-- Play Idle pertama kali
	self:play("Idle")
end

--- Memainkan animasi serangan (Attack) secara eksplisit.
--- Mengembalikan false bila NPC ini belum punya animasi serang, supaya
--- pemanggil tidak menganggap animasi sudah jalan.
function AnimationManager:playAttack(): boolean
	local attackTrack = self._tracks["Attack"]
	if not attackTrack then
		attackTrack = self:_loadTrack("Attack")
	end

	if not attackTrack then
		return false
	end

	-- Hentikan track lain yang sedang aktif (mis. Idle/Walk) dengan rapi
	if self._currentTrack and self._currentTrack ~= attackTrack then
		self._currentTrack:Stop(0.1)
	end

	-- FIX bug C: update _currentTrack & _currentAnimName supaya animasi attack
	-- tidak keburu di-Stop oleh handler Running (Walk/Run) saat monster bergerak.
	self._currentTrack = attackTrack
	self._currentAnimName = "Attack"

	if not attackTrack.IsPlaying then
		attackTrack.Looped = false
		attackTrack:Play(0.1)
	end

	return true
end

--- Cleanup event connections saat monster dibersihkan
function AnimationManager:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}

	for _, track in pairs(self._tracks) do
		track:Stop()
		track:Destroy()
	end
	self._tracks = {}
end

return AnimationManager
