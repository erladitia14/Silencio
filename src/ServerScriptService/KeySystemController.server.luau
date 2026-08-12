--[[
	KeySystemController.server.luau
	-------------------------------
	Orchestrator KEY SYSTEM untuk Silencio.

	FLOW:
	  1. Player ambil KeyPickup            -> KeyService.grantKey(keyId)
	  2. Player buka LockedDoor (butuh kunci) -> PowerService.setDoorOpen(doorId, true)
	  3. PowerSwitch (butuh pintu kebuka)  -> PowerService.setPower(true)
	  4. PowerChanged(true)                -> LightManager nyalakan semua CarnivalLight

	Semua modul decoupled lewat PowerService (signal). Nol hardcoded path:
	builder cukup menempel Tag + set Attribute di Studio.

	SETUP:
	  - Letakkan script ini di ServerScriptService
	  - Folder "KeySystem" (berisi ModuleScript) sebagai sibling
	  - Tag objek di Studio:
	      KeyPickup     -> kunci (attr: KeyId, default "control_room")
	      LockedDoor    -> pintu (attr: DoorId/RequiredKey, default "control_room")
	      PowerSwitch   -> tuas  (attr: RequiresDoorOpen=true, GateDoorId="control_room")
	      CarnivalLight -> lampu (attr: OnBrightness/OffBrightness)

	TEST CEPAT (tanpa building):
	  - Spawn 1 Part, tag "KeyPickup"
	  - Spawn 1 Part, tag "LockedDoor"
	  - Spawn 1 Part, tag "PowerSwitch"
	  - Spawn beberapa Part, tag "CarnivalLight"
--]]

local modulesFolder = script.Parent:FindFirstChild("KeySystem")
	or script.Parent:WaitForChild("KeySystem", 10)

assert(modulesFolder, "[KeySystem] Folder 'KeySystem' tidak ditemukan di ServerScriptService!")

local KeyService       = require(modulesFolder:WaitForChild("KeyService"))
local PowerService     = require(modulesFolder:WaitForChild("PowerService"))
local DoorManager      = require(modulesFolder:WaitForChild("DoorManager"))
local LightManager     = require(modulesFolder:WaitForChild("LightManager"))
local SwitchManager    = require(modulesFolder:WaitForChild("SwitchManager"))
local KeyPickupManager = require(modulesFolder:WaitForChild("KeyPickupManager"))

print("[KeySystem] === Silencio KEY SYSTEM v1.0 ===")

-- Instansiasi service inti
local keyService   = KeyService.new()
local powerService = PowerService.new()

-- Managers
local doorManager   = DoorManager.new(keyService, powerService)
local lightManager  = LightManager.new(powerService)
local switchManager = SwitchManager.new(powerService)

-- Saat kunci baru didapat, refresh prompt pintu (biar teks "Terkunci" -> "Buka")
local keyPickupManager = KeyPickupManager.new(keyService, function(_keyId)
	doorManager:onKeysChanged()
end)

-- Start semua subsistem (aman walau 0 objek ter-tag)
doorManager:start()
lightManager:start()
switchManager:start()
keyPickupManager:start()

-- Pastikan lampu mulai dalam kondisi OFF sesuai state awal power
lightManager:setAll(powerService:isPowerOn())

print("[KeySystem] Siap. Tag: KeyPickup / LockedDoor / PowerSwitch / CarnivalLight")
