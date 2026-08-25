--[[
	CombatManager.luau
	------------------
	Mengelola sistem combat monster: serangan, damage, cooldown.

	CATATAN ANIMASI:
	  Modul ini TIDAK menyentuh Animator secara langsung lagi.
	  Animasi attack diserahkan ke script NPC lewat event "Attack"
	  pada BindableEvent "AISignal" (di-emit oleh EnemyController).
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
	return self
end

--- Cek apakah serangan sudah bisa dilakukan (cooldown selesai).
function CombatManager:canAttack(): boolean
	return (tick() - self._lastAttackTime) >= Config.get(self._model, "AttackCooldown")
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
	targetHumanoid:TakeDamage(Config.get(self._model, "Damage"))
	self._lastAttackTime = tick()

	-- Animasi default (opt-in saja). Jalur normal: EnemyController emit "Attack".
	self:_playAttackAnimation()

	return true
end

--- Memainkan animasi serangan HANYA bila animasi default sedang dipakai.
---
--- PENTING: modul ini TIDAK lagi menyentuh Animator secara langsung.
--- Jalur normal = EnemyController emit event "Attack" lewat AISignal, lalu
--- script animasi milik NPC yang memutuskan animasi apa yang diputar.
--- `_animManager` hanya terisi kalau Model punya UseDefaultAnimations = true.
function CombatManager:_playAttackAnimation()
	if self._animManager and self._animManager.playAttack then
		self._animManager:playAttack()
	end
end

--- Cleanup. Tidak ada lagi AnimationTrack yang dimiliki modul ini;
--- disediakan agar pemanggilan ctx.combat:destroy() tetap aman.
function CombatManager:destroy()
	self._animManager = nil
end

return CombatManager
