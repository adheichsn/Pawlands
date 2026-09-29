local RunService = game:GetService("RunService")

local ComboFlow = {}
ComboFlow.__index = ComboFlow
local EPSILON = 0.0001

function ComboFlow.new(config, callbacks)
	local self = setmetatable({
		Config = config,
		Callbacks = callbacks,
		ComboIndex = 0,
		LastAttackAt = -math.huge,
		NextAttackAt = 0,
		Buffered = false,
		BufferedRunning = false,
		Destroyed = false,
	}, ComboFlow)

	self.Heartbeat = RunService.Heartbeat:Connect(function()
		self:_flushBuffered()
	end)
	return self
end

function ComboFlow:_clearBuffer()
	self.Buffered = false
	self.BufferedRunning = false
end

function ComboFlow:_resolveAction(now, running)
	local comboExpired = now - self.LastAttackAt > self.Config.ComboResetSeconds
	if running and comboExpired then
		return "Running", 0, self.Config.RunningAttack
	end

	if comboExpired or self.ComboIndex <= 0 then
		self.ComboIndex = 1
	else
		self.ComboIndex = (self.ComboIndex % #self.Config.Combo) + 1
	end
	return "Combo", self.ComboIndex, self.Config.Combo[self.ComboIndex]
end

function ComboFlow:_commit(now, running)
	local kind, comboIndex, definition = self:_resolveAction(now, running)
	if not definition then
		return false
	end

	self.LastAttackAt = now
	self.NextAttackAt = now + definition.CadenceSeconds
	self:_clearBuffer()

	if self.Callbacks.OnAttack then
		self.Callbacks.OnAttack(kind, comboIndex)
	end
	return true
end

function ComboFlow:_flushBuffered()
	if self.Destroyed or not self.Buffered then
		return
	end
	local now = os.clock()
	if now + EPSILON < self.NextAttackAt then
		return
	end
	local running = self.BufferedRunning
	self:_commit(now, running)
end

function ComboFlow:Request(running)
	if self.Destroyed then
		return false
	end

	local now = os.clock()
	if now + EPSILON >= self.NextAttackAt then
		return self:_commit(now, running == true)
	end

	local timeUntilReady = self.NextAttackAt - now
	if not self.Buffered and timeUntilReady <= self.Config.InputBufferSeconds + EPSILON then
		self.Buffered = true
		self.BufferedRunning = running == true
		return true
	end
	return false
end

function ComboFlow:Cancel()
	self.ComboIndex = 0
	self.LastAttackAt = -math.huge
	self.NextAttackAt = 0
	self:_clearBuffer()
end

function ComboFlow:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end
	self:Cancel()
	self.Callbacks = {}
end

return ComboFlow
