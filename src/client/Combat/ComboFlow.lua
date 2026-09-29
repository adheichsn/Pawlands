local ComboFlow = {}
ComboFlow.__index = ComboFlow

local function resolveHoldSeconds(config, timing, naturalSeconds)
	local seconds = timing.MaxHold
	if naturalSeconds and naturalSeconds > 0 then
		seconds = naturalSeconds - config.AnimationExitBlendLead
	end
	return math.clamp(seconds, timing.MinHold, timing.MaxHold)
end

function ComboFlow.new(config, callbacks)
	return setmetatable({
		Config = config,
		Callbacks = callbacks,
		Active = false,
		Kind = nil,
		ComboIndex = 0,
		Token = 0,
		StartedAt = 0,
		NextAt = nil,
		FinishAt = 0,
		QueuedNext = false,
		QueuedRestart = false,
		QueuedRestartRunning = false,
	}, ComboFlow)
end

function ComboFlow:_finish()
	if not self.Active then
		return
	end
	self.Token += 1
	self.Active = false
	self.Kind = nil
	self.ComboIndex = 0
	self.StartedAt = 0
	self.NextAt = nil
	self.FinishAt = 0
	self.QueuedNext = false
	self.QueuedRestart = false
	self.QueuedRestartRunning = false
	if self.Callbacks.OnChainEnd then
		self.Callbacks.OnChainEnd()
	end
end

function ComboFlow:_timingFor(kind, comboIndex)
	if kind == "Running" then
		return self.Config.RunningTiming
	end
	return self.Config.ComboTiming[comboIndex]
end

function ComboFlow:_play(kind, comboIndex)
	if not self.Active then
		self.Active = true
		if self.Callbacks.OnChainStart then
			self.Callbacks.OnChainStart()
		end
	end

	self.Token += 1
	local token = self.Token
	self.Kind = kind
	self.ComboIndex = comboIndex or 0
	self.QueuedNext = false
	self.QueuedRestart = false
	self.QueuedRestartRunning = false
	self.StartedAt = os.clock()

	local naturalSeconds
	if self.Callbacks.OnAttack then
		naturalSeconds = self.Callbacks.OnAttack(kind, comboIndex)
	end

	local timing = self:_timingFor(kind, comboIndex)
	local holdSeconds = resolveHoldSeconds(self.Config, timing, naturalSeconds)
	self.NextAt = timing.NextAt and (self.StartedAt + timing.NextAt) or nil
	self.FinishAt = self.StartedAt + holdSeconds

	if self.NextAt then
		local delaySeconds = math.max(0, self.NextAt - os.clock())
		task.delay(delaySeconds, function()
			if not self.Active or self.Token ~= token or not self.QueuedNext then
				return
			end
			self:_advance()
		end)
	end

	task.delay(math.max(0, self.FinishAt - os.clock()), function()
		if not self.Active or self.Token ~= token then
			return
		end
		if self.Kind == "Combo" and self.ComboIndex == 4 and self.QueuedRestart then
			local running = self.QueuedRestartRunning
			self:_finish()
			self:_startFresh(running)
			return
		end
		self:_finish()
	end)
end

function ComboFlow:_startFresh(running)
	if running then
		self:_play("Running", 0)
	else
		self:_play("Combo", 1)
	end
end

function ComboFlow:_advance()
	if not self.Active then
		return
	end
	if self.Kind == "Running" then
		self:_play("Combo", 1)
		return
	end
	if self.Kind == "Combo" and self.ComboIndex < 4 then
		self:_play("Combo", self.ComboIndex + 1)
	end
end

function ComboFlow:Request(running)
	if not self.Active then
		self:_startFresh(running == true)
		return true
	end

	local now = os.clock()
	if self.Kind == "Combo" and self.ComboIndex == 4 then
		if now >= self.FinishAt - self.Config.FinisherRestartBufferSeconds then
			self.QueuedRestart = true
			self.QueuedRestartRunning = running == true
			return true
		end
		return false
	end

	if self.NextAt and now >= self.NextAt then
		self:_advance()
		return true
	end

	if self.NextAt then
		-- Only a single next hit is buffered; repeated early clicks do not compress
		-- the authored swing into an unnaturally fast chain.
		self.QueuedNext = true
		return true
	end

	return false
end

function ComboFlow:Cancel()
	self:_finish()
end

function ComboFlow:Destroy()
	self:Cancel()
	self.Callbacks = {}
end

return ComboFlow
