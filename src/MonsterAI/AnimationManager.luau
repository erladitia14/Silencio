--[[
	AnimationManager.luau
	---------------------
	Mengelola animasi NPC Monster di sisi server.
	
	MASALAH YANG DISELESAIKAN:
	  - Script 'Animate' bawaan Roblox pada NPC seringkali berupa LocalScript,
	    sehingga TIDAK berjalan ketika dipasang pada NPC di Workspace.
	  - Modul ini menggantikan peran LocalScript Animate dengan mengelola
	    animasi (Idle, Walk, Run, Jump, Fall, Attack) langsung dari Server.
--]]

local Config = require(script.Parent.Config)

local AnimationManager = {}
AnimationManager.__index = AnimationManager

-- Animation ID bawaan Roblox (R15 & R6)
local DEFAULT_ANIMS = {
	R15 = {
		Idle  = "http://www.roblox.com/asset/?id=507766388",
		Walk  = "http://www.roblox.com/asset/?id=913402848",
		Run   = "http://www.roblox.com/asset/?id=913376220",
		Jump  = "http://www.roblox.com/asset/?id=507765000",
		Fall  = "http://www.roblox.com/asset/?id=507767968",
	},
	R6 = {
		Idle  = "http://www.roblox.com/asset/?id=180435571",
		Walk  = "http://www.roblox.com/asset/?id=180436334",
		Run   = "http://www.roblox.com/asset/?id=180436334",
		Jump  = "http://www.roblox.com/asset/?id=125750702",
		Fall  = "http://www.roblox.com/asset/?id=180436148",
	}
}

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

	self:_loadAnimations()
	self:_setupStateListeners()

	return self
end

--- Extract AnimationId dari object Animation, StringValue, atau default ID
function AnimationManager:_getAnimId(name: string): string
	-- 1. Cari folder "Animations" di dalam model
	local animFolder = self._model:FindFirstChild("Animations")
	if animFolder then
		local found = animFolder:FindFirstChild(name)
		if found and found:IsA("Animation") and found.AnimationId ~= "" then
			return found.AnimationId
		end
	end

	-- 2. Cari di script/folder "Animate" jika ada
	local animateObj = self._model:FindFirstChild("Animate")
	if animateObj then
		local found = animateObj:FindFirstChild(name)
		if found then
			if found:IsA("Animation") and found.AnimationId ~= "" then
				return found.AnimationId
			elseif found:IsA("StringValue") then
				local childAnim = found:FindFirstChildOfClass("Animation")
				if childAnim and childAnim.AnimationId ~= "" then
					return childAnim.AnimationId
				end
			end
		end
	end

	-- 3. Fallback ke ID default Roblox
	local defaults = DEFAULT_ANIMS[self._rigType]
	return defaults[name] or defaults.Idle
end

--- Helper untuk memuat dan menyimpan AnimationTrack
function AnimationManager:_loadTrack(name: string): AnimationTrack?
	local animId = self:_getAnimId(name)
	if not animId or animId == "" then return nil end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local success, track = pcall(function()
		return self._animator:LoadAnimation(anim)
	end)

	if success and track then
		self._tracks[name] = track
		return track
	end

	return nil
end

--- Memuat semua track animasi utama
function AnimationManager:_loadAnimations()
	self:_loadTrack("Idle")
	self:_loadTrack("Walk")
	self:_loadTrack("Run")
	self:_loadTrack("Jump")
	self:_loadTrack("Fall")
	self:_loadTrack("Attack")
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
--- FIX bug C: update _currentTrack & _currentAnimName supaya animasi attack
--- tidak keburu di-Stop oleh handler Running (Walk/Run) saat monster bergerak.
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

	self._currentTrack = attackTrack
	self._currentAnimName = "Attack"

	if not attackTrack.IsPlaying then
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
