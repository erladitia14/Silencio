--[[
	SafeZoneController.server.luau
	------------------------------
	Orchestrator sistem Safe Zone "bilik toilet".

	Letak: ServerScriptService (Script server, bukan ModuleScript).
	Modulnya: ReplicatedStorage/Modules/SafeZone/

	CARA PAKAI (nol konfigurasi):
	  1. Beri tag "SafeZone" pada Part bilik  (atau taruh di Folder
	     "SafeZones" di Workspace). Nama Part bebas.
	  2. Selesai. Tidak perlu menempel script, tidak perlu mengisi ID.

	Detail per bilik lewat Attribute pada Part-nya:
	  BreathTime (Number)    lama perlindungan, detik            default 20
	  MaxOccupants (Number)  kapasitas                            default 1
	  CooldownTime (Number)  lama hangus setelah dipakai, detik   default 15
	  BurnOnExit (Bool)      keluar lebih awal langsung hangus    default false
	  NoBarrier (Bool)       bilik tidak menahan monster          default false
	  NoBreath (Bool)        bilik aman selamanya (tanpa timer)   default false

	Bilik menerbitkan keadaannya sebagai Attribute pada Part-nya sendiri:
	  SafeZoneState  = READY | OCCUPIED | BREACHED | COOLDOWN
	  SafeZoneBreath = sisa napas (detik)
	Tim bisa memasang efek (suara, lampu, partikel) dengan mendengarkan
	Attribute itu — tanpa menyentuh script ini. Pola yang sama dengan
	"AIState" milik EnemyController.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage
	:WaitForChild("Modules", 10)
	:WaitForChild("SafeZone", 10)

assert(modules, "[SafeZone] Folder 'SafeZone' tidak ditemukan di ReplicatedStorage.Modules!")

local Config      = require(modules:WaitForChild("Config"))
local ZoneService = require(modules:WaitForChild("ZoneService"))

print("[SafeZone] === Silencio Safe Zone (bilik toilet) ===")

ZoneService:start()

print(string.format(
	"[SafeZone] Default: napas %ds, kapasitas %d, cooldown %ds, dinding monster %s.",
	Config.BreathTime,
	Config.MaxOccupants,
	Config.CooldownTime,
	Config.BarrierEnabled and "AKTIF" or "nonaktif"
))
print("[SafeZone] Beri tag '" .. Config.SafeZoneTag .. "' pada Part bilik untuk mengaktifkan.")
