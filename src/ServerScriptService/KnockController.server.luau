--[[
	KnockController.server.luau
	---------------------------
	Script tipis yang menyalakan sistem KNOCK & REVIVE.

	SETUP:
	  - Letakkan script ini di ServerScriptService.
	  - Folder "KnockSystem" berisi ModuleScript harus ada di
	    ReplicatedStorage/Modules.

	Sistem ini BERDIRI SENDIRI dan tidak mengubah script sistem lain.
	Satu-satunya sentuhan ke core AI: TargetFinder membaca Attribute "Knocked"
	pada karakter (di-set KnockSystem) supaya monster melepas korban yang
	tumbang dan mencari target lain.

	Untuk tim (SFX/UI): dengarkan BindableEvent "KnockSignal" di
	ReplicatedStorage. Payload:
	  Fire("Downed",   player)
	  Fire("Revived",  player, reviverPlayer)
	  Fire("BleedOut", player)
	  Fire("Warning",  player, secondsLeft)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage
	:WaitForChild("Modules", 10)
	:WaitForChild("KnockSystem", 10)

assert(modulesFolder, "[KnockSystem] Folder 'KnockSystem' tidak ditemukan di ReplicatedStorage.Modules!")

local KnockService = require(modulesFolder:WaitForChild("KnockService"))

print("[KnockSystem] === Silencio Knock & Revive System ===")
KnockService.start()
print("[KnockSystem] Sistem siap. Pemain yang HP-nya habis karena monster akan tumbang, bukan mati.")
