--[[
	CombatManager.luau
	------------------
	Mengelola sistem combat monster: serangan, damage, cooldown,
	dan animasi attack.
--]]

local Config = require(script.Parent.Config)

local CombatManager = {}
CombatManager.__index = CombatManager

--- Membuat instance CombatManager baru untuk sebuah monster.
--- Setiap monster memiliki cooldown tracker sendiri.
function CombatManager.new(monsterModel: Model, animManager: any?)
	local self = setmetatable({}, CombatManager)
	self._model = monsterModel
	self._humanoid = monsterModel:FindFirstChildOfClass("Humanoid") :: Humanoid
	self._animManager = animManager
	self._lastAttackTime = 0
	self._fallbackAttackTrack = nil :: AnimationTrack?  -- cache track fallback (FIX bug D)
	return self
end

--- Cek apakah serangan sudah bisa dilakukan (cooldown selesai).
function CombatManager:canAttack(): boolean
	return (tick() - self._lastAttackTime) >= Config.AttackCooldown
end

--- Melakukan serangan ke target.
--- Mengembalikan true jika serangan berhasil dilakukan.
function CombatManager:attack(targetChar: Model): boolean
	if not self:canAttack() then
		return false
	end

	local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return false
	end

	-- Deal damage
	targetHumanoid:TakeDamage(Config.Damage)
	self._lastAttackTime = tick()

	-- Play attack animation
	self:_playAttackAnimation()

	return true
end

--- Memainkan animasi serangan jika tersedia.
function CombatManager:_playAttackAnimation()
	if self._animManager and self._animManager.playAttack then
		local played = self._animManager:playAttack()
		if played then return end
	end

	local animFolder = self._model:FindFirstChild("Animations")
	if not animFolder then return end

	local attackAnim = animFolder:FindFirstChild("Attack") :: Animation?
	if not attackAnim then return end

	local animator = self._humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	-- FIX bug D: cache track fallback agar tidak LoadAnimation baru tiap serang
	-- (mencegah akumulasi AnimationTrack / memory leak).
	local track = self._fallbackAttackTrack
	if not track then
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(attackAnim)
		end)
		if not ok or not loaded then return end
		track = loaded
		self._fallbackAttackTrack = track
	end

	if not track.IsPlaying then
		track:Play(0.1)
	end
end

--- Membersihkan resource milik CombatManager (track fallback).
--- Normalnya animasi dikelola AnimationManager; ini hanya untuk jalur fallback.
function CombatManager:destroy()
	if self._fallbackAttackTrack then
		self._fallbackAttackTrack:Stop()
		self._fallbackAttackTrack:Destroy()
		self._fallbackAttackTrack = nil
	end
end

return CombatManager
