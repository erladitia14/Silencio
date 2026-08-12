--[[
	StateMachine.luau
	-----------------
	Finite State Machine (FSM) generik & reusable.
	
	Setiap state didefinisikan sebagai tabel dengan callback:
	  - onEnter(context)   → dipanggil saat masuk ke state
	  - onUpdate(context)  → dipanggil setiap tick selama di state
	  - onExit(context)    → dipanggil saat keluar dari state
	
	Usage:
	  local fsm = StateMachine.new()
	  fsm:addState("PATROL", {
	      onEnter  = function(ctx) ... end,
	      onUpdate = function(ctx) ... end,
	      onExit   = function(ctx) ... end,
	  })
	  fsm:setState("PATROL", context)
	  -- dalam loop:
	  fsm:update(context)
--]]

local StateMachine = {}
StateMachine.__index = StateMachine

export type StateCallbacks = {
	onEnter:  ((context: any) -> ())?,
	onUpdate: ((context: any) -> ())?,
	onExit:   ((context: any) -> ())?,
}

function StateMachine.new()
	local self = setmetatable({}, StateMachine)
	self._states = {} :: { [string]: StateCallbacks }
	self._currentState = nil :: string?
	self._previousState = nil :: string?
	return self
end

--- Mendaftarkan state baru ke dalam FSM.
function StateMachine:addState(name: string, callbacks: StateCallbacks)
	assert(not self._states[name], "[StateMachine] State '" .. name .. "' sudah terdaftar.")
	self._states[name] = callbacks
end

--- Mendapatkan nama state yang aktif saat ini.
function StateMachine:getState(): string?
	return self._currentState
end

--- Mendapatkan nama state sebelumnya.
function StateMachine:getPreviousState(): string?
	return self._previousState
end

--- Berpindah ke state baru. Memanggil onExit dari state lama
--- dan onEnter dari state baru.
function StateMachine:setState(name: string, context: any?)
	assert(self._states[name], "[StateMachine] State '" .. name .. "' tidak ditemukan.")

	-- Jangan transisi jika sudah di state yang sama
	if self._currentState == name then
		return
	end

	-- Exit state lama
	if self._currentState then
		local oldState = self._states[self._currentState]
		if oldState and oldState.onExit then
			oldState.onExit(context)
		end
	end

	self._previousState = self._currentState
	self._currentState = name

	-- Enter state baru
	local newState = self._states[name]
	if newState and newState.onEnter then
		newState.onEnter(context)
	end
end

--- Memanggil onUpdate dari state yang aktif.
--- Harus dipanggil setiap tick di game loop.
function StateMachine:update(context: any?)
	if not self._currentState then return end

	local state = self._states[self._currentState]
	if state and state.onUpdate then
		state.onUpdate(context)
	end
end

return StateMachine
