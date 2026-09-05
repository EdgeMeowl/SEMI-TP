--[[
  Halfway Steal (Semi/Instant Steal V2)
  Fully standalone — all Gamma Hub modules embedded
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local tick = tick
local taskwait = task.wait
local taskspawn = task.spawn
local taskdelay = task.delay
local Vector3 = Vector3
local CFrame = CFrame

_G._FH_GAMMA_GEN = (_G._FH_GAMMA_GEN or 0) + 1
local _GEN = _G._FH_GAMMA_GEN
_G._FH_SHUTDOWN = false


-- ── Config ──

local Config = {}

do
	local FOLDER = "GammaHub"
	local FILE = FOLDER .. "/config.json"
	local FILE_BAK = FOLDER .. "/config.bak.json"
	local HttpService = game:GetService("HttpService")

	Config.data = {}

	local function _ensureFolder()
		if not makefolder then return end
		if isfolder and isfolder(FOLDER) then return end
		pcall(function() makefolder(FOLDER) end)
	end

	pcall(_ensureFolder)

	pcall(function()
		local function tryDecode(path)
			if isfile and readfile and isfile(path) then
				local ok, decoded = pcall(function()
					return HttpService:JSONDecode(readfile(path))
				end)
				if ok and type(decoded) == "table" then return decoded end
			end
		end
		local d = tryDecode(FILE) or tryDecode(FILE_BAK)
		if d then Config.data = d end
	end)

	local function _writeNow()
		if not writefile then return end
		if Config._dirty == false then return end
		pcall(_ensureFolder)
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(Config.data)
		end)
		if not ok or type(encoded) ~= "string" or #encoded < 2 then return end
		pcall(function()
			if isfile and isfile(FILE) then writefile(FILE_BAK, readfile(FILE)) end
		end)
		pcall(function() writefile(FILE, encoded) end)
		Config._dirty = false
	end

	local _saveHandle

	function Config.save()
		Config._dirty = true
		if not writefile then return end
		if _saveHandle then return end
		_saveHandle = taskdelay(0.2, function()
			_writeNow()
			_saveHandle = nil
		end)
	end

	function Config.flush() _writeNow() end

	function Config.get(key, default)
		local v = Config.data[key]
		if v == nil then return default end
		return v
	end

	local function _deepEq(a, b)
		if type(a) == "number" and type(b) == "number" then
			return math.abs(a - b) < 1e-9
		end
		if a == b then return true end
		if type(a) ~= "table" or type(b) ~= "table" then return false end
		for k, v in pairs(a) do
			if not _deepEq(v, b[k]) then return false end
		end
		for k in pairs(b) do
			if a[k] == nil then return false end
		end
		return true
	end

	function Config.set(key, value)
		if _deepEq(Config.data[key], value) then return end
		Config.data[key] = value
		Config._dirty = true
		if type(value) == "number" then
			Config.save()
		else
			_writeNow()
			if _saveHandle then
				task.cancel(_saveHandle)
				_saveHandle = nil
			end
		end
	end

	taskspawn(function()
		while true do
			taskwait(45)
			if writefile then _writeNow() end
		end
	end)
end


-- ── Utility: Tween (used by _FH_CarpetTP) ──

local function Tween(o, i, p)
	TweenService:Create(o, i, p):Play()
end


-- ── Embedded Modules ──

-- cloneref
local cloneref = (type(cloneref) == "function" and cloneref)
	or (syn and syn.cloneref)
	or function(o) return o end

-- Mount names / active mount
local _FH_MOUNT_NAMES = {
	"Flying Carpet",
	"Santa's Sleigh",
	"Witch's Broom",
	"Waverider",
	"Cupid's Wings",
}

local _FH_ActiveMount = Config.get("mount_type", "Flying Carpet")


-- isInEnemyPlot

local function isInEnemyPlot()
	local lp = Players.LocalPlayer
	if not lp then return false end

	local char = lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local plots = Workspace:FindFirstChild("Plots")
	if not plots then return false end

	local myNameL = lp.Name:lower()
	local myDisplayL = lp.DisplayName:lower()

	for _, plot in ipairs(plots:GetChildren()) do
		local sign = plot:FindFirstChild("PlotSign")
		if sign then
			local lbl = sign:FindFirstChildWhichIsA("TextLabel", true)
			if lbl then
				local t = lbl.Text:lower()
				if not (t:find(myNameL, 1, true) or t:find(myDisplayL, 1, true)) then
					local hb = plot:FindFirstChild("StealHitbox", true)
					if hb then
						local cf = hb.CFrame
						local size = hb.Size
						local rel = cf:PointToObjectSpace(hrp.Position)
						if math.abs(rel.X) <= size.X * 0.5
							and math.abs(rel.Z) <= size.Z * 0.5
						then
							return true
						end
					end
				end
			end
		end
	end

	return false
end


-- ── Booster ──

local Booster = (function()
	local M = {
		enabled = false,
		userEnabled = false,
		speed = Config.get("booster_spd", 29),
		jump = Config.get("booster_jmp", 50),
	}

	function M.setSpeed(n)
		M.speed = tonumber(n) or M.speed
		Config.set("booster_spd", M.speed)
	end

	function M.setJump(n)
		M.jump = tonumber(n) or M.jump
		Config.set("booster_jmp", M.jump)
	end

	local _boostConn, _jumpConn

	local function detach()
		if _boostConn then _boostConn:Disconnect(); _boostConn = nil end
		if _jumpConn then _jumpConn:Disconnect(); _jumpConn = nil end
	end

	local function attach()
		detach()
		local player = Players.LocalPlayer or Players.PlayerAdded:Wait()

		_jumpConn = UserInputService.JumpRequest:Connect(function()
			if _GEN ~= _G._FH_GAMMA_GEN then return end
			if not M.enabled then return end
			local char = player.Character
			if not char then return end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not (hrp and hum) then return end
			if hum.FloorMaterial == Enum.Material.Air then return end
			hrp.Velocity = Vector3.new(hrp.Velocity.X, M.jump, hrp.Velocity.Z)
		end)

		_boostConn = RunService.Heartbeat:Connect(function()
			if _GEN ~= _G._FH_GAMMA_GEN then return end
			if not M.enabled then return end
			local char = player.Character
			if not char then return end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not (hrp and hum) then return end
			local moveDir = hum.MoveDirection
			if moveDir.Magnitude > 0 then
				local vel = hrp.Velocity
				hrp.Velocity = Vector3.new(moveDir.X * M.speed, vel.Y, moveDir.Z * M.speed)
			end
		end)
	end

	local _attached = false
	local _suspends = {}

	local function applyState()
		local shouldBeOn = M.userEnabled and not next(_suspends)
		if shouldBeOn then
			M.enabled = true
			if not _attached then
				_attached = true
				taskspawn(function() pcall(attach) end)
			end
		else
			M.enabled = false
			if _attached then _attached = false; detach() end
		end
	end

	function M.set(v)
		M.userEnabled = v and true or false
		Config.set("booster_on", M.userEnabled)
		applyState()
	end

	function M.suspend(name)
		_suspends[name or "default"] = true
		applyState()
	end

	function M.unsuspend(name)
		_suspends[name or "default"] = nil
		applyState()
	end

	local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
	player.CharacterAdded:Connect(function()
		if _GEN ~= _G._FH_GAMMA_GEN then return end
		_suspends = {}
		_attached = false
		detach()
		applyState()
	end)

	return M
end)()


-- ── Actions ──

local Actions = (function()
	local TeleportService = game:GetService("TeleportService")
	local player = Players.LocalPlayer
	local A = {}
	local resetRemote
	local RESET_GUID = "f888ee6e-c86d-46e1-93d7-0639d6635d42"

	pcall(function()
		if type(hookfunction) == "function" then
			local _orig
			local _probe = Instance.new("RemoteEvent")
			local _restored = false

			local function restore()
				if _restored or not _orig then return end
				_restored = true
				pcall(function() hookfunction(_probe.FireServer, _orig) end)
			end

			_orig = hookfunction(_probe.FireServer, newcclosure(function(self, ...)
				if not resetRemote
					and typeof(self) == "Instance"
					and self:IsA("RemoteEvent")
					and tostring(self.Name):sub(1, 3) == "RE/"
				then
					resetRemote = self
					task.defer(restore)
				end
				return _orig(self, ...)
			end))

			taskdelay(12, restore)
			pcall(function() _probe:Destroy() end)
		end
	end)

	function A.kick()
		taskspawn(function()
			pcall(function()
				local GuiService = game:GetService("GuiService")
				local RS = game:GetService("RunService")
				GuiService.SelectedCoreObject = nil
				for _ = 1, 3 do RS.RenderStepped:Wait() end
				game:Shutdown()
			end)
		end)
	end

	function A.rejoin()
		taskspawn(function()
			pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
		end)
		pcall(function() player:Kick("rejoining") end)
	end

	local resetting = false

	function A.reset()
		if not player or resetting then return end
		resetting = true
		local oldChar = player.Character
		taskspawn(function()
			local deadline = tick() + 8
			while player.Character == oldChar and tick() < deadline do
				if not resetRemote then break end
				pcall(function()
					resetRemote:FireServer(RESET_GUID, player, "balloon")
				end)
				taskwait(0.15)
			end
			resetting = false
		end)
	end

	return A
end)()


-- ── BackpackLock ──

local BackpackLock = (function()
	local lp = Players.LocalPlayer or Players.PlayerAdded:Wait()
	local enabled = false
	local _userIsSwitching = false
	local _userSwitchEndsAt = 0
	local _suspended = false
	local _suspendUntil = 0
	local conns = {}
	local M = {}

	local STEAL_ATTRS = {
		"Stealing", "steal", "stolen",
		"isStealing", "IsSteal", "issteal",
	}

	local function isStealActive()
		for _, attr in ipairs(STEAL_ATTRS) do
			local v = lp:GetAttribute(attr)
			if v ~= nil and v ~= false and v ~= 0 then return true end
		end
		return false
	end

	local function clear()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		conns = {}
	end

	local function userInteracting()
		return _userIsSwitching or tick() < _userSwitchEndsAt
	end

	local function moveToolsToBackpack(char)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local bp = lp:FindFirstChildOfClass("Backpack")
		if not hum or not bp then return end
		if userInteracting() or isStealActive() or _suspended or tick() < _suspendUntil then return end
		pcall(hum.UnequipTools, hum)
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") then
				t.Parent = bp
			end
		end
	end

	local function hookCharacter(char)
		if not char then return end
		taskdelay(0.05, function()
			if enabled then moveToolsToBackpack(char) end
		end)
		table.insert(conns, char.ChildAdded:Connect(function(obj)
			if not enabled or not obj:IsA("Tool") then return end
			task.defer(function()
				taskwait()
				if not enabled
					or userInteracting()
					or isStealActive()
					or _suspended
					or tick() < _suspendUntil
				then
					return
				end
				if obj.Parent == char then
					local bp = lp:FindFirstChildOfClass("Backpack")
					if bp then obj.Parent = bp end
				end
			end)
		end))
	end

	function M.set(on)
		enabled = on and true or false
		clear()
		if not enabled then return end
		if lp.Character then hookCharacter(lp.Character) end
		table.insert(conns, lp.CharacterAdded:Connect(hookCharacter))
		table.insert(conns, UserInputService.InputBegan:Connect(function(inp, gpe)
			local kc = inp.KeyCode
			local isHotbarKey = kc and (
				(kc.Value >= Enum.KeyCode.One.Value and kc.Value <= Enum.KeyCode.Nine.Value)
				or kc == Enum.KeyCode.Zero
			)
			local isClick = inp.UserInputType == Enum.UserInputType.MouseButton1
				or inp.UserInputType == Enum.UserInputType.Touch
			if gpe and not isClick then return end
			if isHotbarKey or isClick then
				_userIsSwitching = true
				_userSwitchEndsAt = tick() + 1.5
				taskdelay(1.5, function() _userIsSwitching = false end)
			end
		end))
	end

	function M.suspend(duration)
		local until_ = tick() + (tonumber(duration) or 5)
		if until_ > _suspendUntil then _suspendUntil = until_ end
		_suspended = true
		taskdelay(tonumber(duration) or 5, function()
			if tick() >= _suspendUntil then _suspended = false end
		end)
	end

	function M.unsuspend()
		_suspended = false
		_suspendUntil = 0
	end

	return M
end)()


-- ── AutoBigPotion ──

local AutoBigPotion = (function()
	local M = { enabled = false }

	function M.set(v) M.enabled = v and true or false end

	taskspawn(function()
		pcall(function()
			local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
			local PPS = game:GetService("ProximityPromptService")

			local POTION_NAMES = {
				"Giant Potion", "Giant",
				"Grow Potion", "Super Grow", "Potion",
			}

			local GIANT_THRESHOLD = 2.5

			local function isGiant()
				local c = player.Character
				local hum = c and c:FindFirstChildOfClass("Humanoid")
				if not hum then return false end
				local scale = hum:FindFirstChild("BodyHeightScale")
					or hum:FindFirstChild("BodyDepthScale")
					or hum:FindFirstChild("BodyWidthScale")
				return scale and scale:IsA("NumberValue") and scale.Value >= GIANT_THRESHOLD
			end

			local STEAL_ATTRS = {
				"Stealing", "steal", "stolen",
				"isStealing", "IsSteal", "issteal",
			}

			local function isStealAttrActive()
				for _, attr in ipairs(STEAL_ATTRS) do
				local v = player:GetAttribute(attr)
				if v ~= nil and v ~= false and v ~= 0 then return true end
				end
				return false
			end

			local function activate()
				if isGiant() or isStealAttrActive() then return end
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local bp = player:FindFirstChild("Backpack")
				if not char or not hum or not bp then return end

				local potion
				for _, name in ipairs(POTION_NAMES) do
					local t = bp:FindFirstChild(name) or char:FindFirstChild(name)
					if t and t:IsA("Tool") then potion = t; break end
				end
				if not potion then return end

				if BackpackLock and BackpackLock.suspend then
					BackpackLock.suspend(1)
				end

				pcall(function()
					if potion.Parent ~= char then hum:EquipTool(potion) end
					potion:Activate()
					taskdelay(0.25, function()
						if potion and potion.Parent == char and bp and bp.Parent then
							potion.Parent = bp
						end
					end)
				end)
			end

			M.activate = activate

			local sessionToken = {}

			M.clearSession = function()
				for k in next, sessionToken do sessionToken[k] = nil end
			end

			local function isSteal(prompt) return prompt.ActionText == "Steal" end

			PPS.PromptButtonHoldBegan:Connect(function(prompt, plr)
				if plr ~= player
					or not M.enabled
					or not isSteal(prompt)
					or isGiant()
					or isStealAttrActive()
				then
					return
				end
				local myToken = {}
				sessionToken[prompt] = myToken
				local dur = (prompt.HoldDuration and prompt.HoldDuration > 0)
					and prompt.HoldDuration or 1
				taskdelay(dur * 0.99, function()
					if sessionToken[prompt] ~= myToken or not M.enabled then return end
					if prompt and prompt.Parent and isInEnemyPlot() then
						pcall(activate)
					end
				end)
			end)

			PPS.PromptButtonHoldEnded:Connect(function(prompt, plr)
				if plr == player then sessionToken[prompt] = nil end
			end)

			PPS.PromptTriggered:Connect(function(prompt, plr)
				if plr == player then sessionToken[prompt] = nil end
			end)
		end)
	end)

	return M
end)()


-- ── Remote Infrastructure ──

local _FH_TripRemote, _FH_StealRemote

do
	local ok, NetMod = pcall(function()
		return game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Net")
	end)

	if ok and NetMod then
		local okClone, NetClone = pcall(function() return require(NetMod:Clone()) end)
		if okClone and NetClone then
			local function getRemote(uuid)
				local okr, rn = pcall(function() return NetClone:RemoteEvent(uuid) end)
				if okr and rn then return NetMod:FindFirstChild(tostring(rn)) end
			end
			_FH_StealRemote = getRemote("3ba148c9-7ed6-4675-93f8-9f7c356a2c54")
			_FH_TripRemote = getRemote("f40f7d9e-2f0d-4167-b250-899273f46874")
		end
	end
end

local _FH_TRIP_U1 = "68c86eb7-eb7e-4b4d-96ae-cf7cd847c5b0"
local _FH_TRIP_U2 = "07b9cc25-2a1f-4a26-a0ec-f2fab578d8bd"
local _FH_STEAL_U1 = "cda5c764-d4e3-45c4-94e4-53a538347590"
local _FH_STEAL_U2 = "8c852fbf-d542-4ef4-aa28-612e24db8d4a"

local function _FH_ResolvePromptTarget(prompt)
	if not prompt or not prompt.Parent then return nil end
	local att = prompt.Parent
	local spawn = att and att.Parent
	local base = spawn and spawn.Parent
	local podium = base and base.Parent
	local pods = podium and podium.Parent
	local plot = pods and pods.Parent
	local pod = podium and tonumber(podium.Name)
	if not (plot and pod) then return nil end
	return { plotName = plot.Name, pod = pod }
end

local function _FH_StartTrip(target)
	local T0 = workspace:GetServerTimeNow()
	if _FH_TripRemote then
	pcall(_FH_TripRemote.FireServer, _FH_TripRemote, T0 + 124, _FH_TRIP_U1)
	pcall(_FH_TripRemote.FireServer, _FH_TripRemote, T0 + 124, _FH_TRIP_U2)
	end
	_G._FH_LastStealStart = tick()
	return { t0 = T0, startedAt = tick(), target = target }
end

local function _FH_FinishSteal(ctx)
	if not ctx or not ctx.target or not _FH_StealRemote then return false end
	local elapsed = tick() - ctx.startedAt
	if elapsed < 1.3 then taskwait(1.3 - elapsed) end
	local ts = ctx.t0 + 1.3 + 31
	pcall(_FH_StealRemote.FireServer, _FH_StealRemote, ts, _FH_STEAL_U1, ctx.target.plotName, ctx.target.pod)
	pcall(_FH_StealRemote.FireServer, _FH_StealRemote, ts, _FH_STEAL_U2, ctx.target.plotName, ctx.target.pod)
	return true
end


-- ── __FH_v2 (Steal Hold / Trigger) ──

local __MIN_HOLD_TIME_v2 = 1.3
local __TRIGGER_AFTER_GREEN_v2 = 0.02
local __stealCbCache_v2 = setmetatable({}, { __mode = "k" })

local function __buildStealCallbacks_v2(prompt)
	if __stealCbCache_v2[prompt] then return __stealCbCache_v2[prompt] end
	if type(getconnections) ~= "function" then return nil end

	local data = { hold = {}, trigger = {} }

	local ok1, c1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
	if ok1 then
		for _, c in ipairs(c1) do
			if type(c.Function) == "function" then
				table.insert(data.hold, c.Function)
			end
		end
	end

	local ok2, c2 = pcall(getconnections, prompt.Triggered)
	if ok2 then
		for _, c in ipairs(c2) do
			if type(c.Function) == "function" then
				table.insert(data.trigger, c.Function)
			end
		end
	end

	if #data.hold == 0 and #data.trigger == 0 then return nil end
	__stealCbCache_v2[prompt] = data
	return data
end

local __FH_v2 = {}

function __FH_v2.startStealHold(prompt, method)
	if not prompt or not prompt.Parent then return nil end
	local cb = __buildStealCallbacks_v2(prompt)
	if not cb then return nil end
	for _, fn in ipairs(cb.hold) do taskspawn(fn) end
	local now = tick()
	return {
		prompt = prompt, cb = cb, method = method,
		ragdollFireTime = now, startedAt = now,
		holdBeganAt = now, holdDone = true,
	}
end

function __FH_v2.doHoldAndWait(ctx)
	if ctx.holdDone then return end
	for _, fn in ipairs(ctx.cb.hold) do taskspawn(fn) end
	ctx.holdBeganAt = tick()
	taskwait(__MIN_HOLD_TIME_v2)
	ctx.holdDone = true
end

function __FH_v2.waitForStealTime(ctx, sec)
	if not ctx then return end
	if sec >= 1.0 then return end
	local elapsed = tick() - ctx.ragdollFireTime
	if elapsed < sec then taskwait(sec - elapsed) end
end

function __FH_v2.finishStealHold(ctx)
	if not ctx then return false end
	if not ctx.holdBeganAt then __FH_v2.doHoldAndWait(ctx) end
	local heldFor = tick() - (ctx.holdBeganAt or tick())
	if heldFor < __MIN_HOLD_TIME_v2 then taskwait(__MIN_HOLD_TIME_v2 - heldFor) end
	taskwait(__TRIGGER_AFTER_GREEN_v2)
	for _, fn in ipairs(ctx.cb.trigger) do taskspawn(fn) end
	return true
end


-- ── _FH_CarpetTP ──

local _FH_CarpetTP_Speed = 214

do
	local lp = Players.LocalPlayer

	local function stripTool(tool)
		if not lp or not tool or not tool:IsA("Tool") then return end
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Massless = true; d.CanCollide = false
			end
		end
		tool.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.Massless = true; d.CanCollide = false
			end
		end)
	end

	local function wireChar(c)
		for _, t in ipairs(c:GetChildren()) do stripTool(t) end
		c.ChildAdded:Connect(stripTool)
	end

	if lp and lp.Character then wireChar(lp.Character) end
	if lp then lp.CharacterAdded:Connect(wireChar) end
end

local _fhCarpetActiveTween

local function _FH_CarpetTP(targetCF, speedOverride)
	local lp = Players.LocalPlayer
	if lp and lp:GetAttribute("Stealing") ~= nil then return end

	local chr = lp and lp.Character
	local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
	if not hrp or not targetCF then return end

	if typeof(targetCF) == "Vector3" then targetCF = CFrame.new(targetCF) end

	local dist = (hrp.Position - targetCF.Position).Magnitude
	local dur = math.max(0.05, dist / (speedOverride or _FH_CarpetTP_Speed or 214))

	local bp = lp:FindFirstChildOfClass("Backpack")
	local carpet = (bp and bp:FindFirstChild(_FH_ActiveMount))
		or chr:FindFirstChild(_FH_ActiveMount)
	local hum = chr:FindFirstChildOfClass("Humanoid")

	if carpet and hum and carpet.Parent ~= chr then
		if BackpackLock and BackpackLock.suspend then
			pcall(BackpackLock.suspend, BackpackLock, math.max(0.5, dur + 0.3))
		end
		pcall(hum.EquipTool, hum, carpet)
	end

	if _fhCarpetActiveTween then
		pcall(_fhCarpetActiveTween.Cancel, _fhCarpetActiveTween)
	end

	local tw = TweenService:Create(
		hrp,
		TweenInfo.new(dur, Enum.EasingStyle.Linear),
		{ CFrame = targetCF }
	)
	_fhCarpetActiveTween = tw
	tw:Play()
	return tw
end


-- ── HalfwaySteal Module ──

local HalfwaySteal = (function()
	local M = {
		potion = false,
		debounce = false,
		method = "Walk",
		_semiStealCtx = nil,
		autoAP = false,
		autoWalk = false,
		walkPoint = nil,
	}

	function M.setPotion(v) M.potion = v and true or false end

	function M.setMethod(v)
		M.method = (v == "TP") and "TP" or "Walk"
	end

	local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
	M.player = player

	local BASES = {
		b1 = {
			refVec = Vector3.new(-337, -5, 100),
			finalPos = Vector3.new(-337, -5, 103),
		},
		b2 = {
			refVec = Vector3.new(-335, -5, 20),
			finalPos = Vector3.new(-334.80, -5.04, 18.90),
		},
	}

	local FFLAGS = {
		GameNetPVHeaderRotationalVelocityZeroCutoffExponent = -5000,
		LargeReplicatorWrite5 = true,
		LargeReplicatorEnabled9 = true,
		AngularVelociryLimit = 360,
		TimestepArbiterVelocityCriteriaThresholdTwoDt = 2147483646,
		S2PhysicsSenderRate = 15000,
		DisableDPIScale = true,
		MaxDataPacketPerSend = 2147483647,
		PhysicsSenderMaxBandwidthBps = 20000,
		TimestepArbiterHumanoidLinearVelThreshold = 21,
		MaxMissedWorldStepsRemembered = -2147483648,
		PlayerHumanoidPropertyUpdateRestrict = true,
		SimDefaultHumanoidTimestepMultiplier = 0,
		StreamJobNOUVolumeLengthCap = 2147483647,
		DebugSendDistInSteps = -2147483648,
		GameNetDontSendRedundantNumTimes = 1,
		CheckPVLinearVelocityIntegrateVsDeltaPositionThresholdPercent = 1,
		CheckPVDifferencesForInterpolationMinVelThresholdStudsPerSecHundredth = 1,
		LargeReplicatorSerializeRead3 = true,
		ReplicationFocusNouExtentsSizeCutoffForPauseStuds = 2147483647,
		CheckPVCachedVelThresholdPercent = 10,
		CheckPVDifferencesForInterpolationMinRotVelThresholdRadsPerSecHundredth = 1,
		GameNetDontSendRedundantDeltaPositionMillionth = 1,
		InterpolationFrameVelocityThresholdMillionth = 5,
		StreamJobNOUVolumeCap = 2147483647,
		InterpolationFrameRotVelocityThresholdMillionth = 5,
		CheckPVCachedRotVelThresholdPercent = 10,
		WorldStepMax = 30,
		InterpolationFramePositionThresholdMillionth = 5,
		TimestepArbiterHumanoidTurningVelThreshold = 1,
		SimOwnedNOUCountThresholdMillionth = 2147483647,
		GameNetPVHeaderLinearVelocityZeroCutoffExponent = -5000,
		NextGenReplicatorEnabledWrite4 = true,
		TimestepArbiterOmegaThou = 1073741823,
		MaxAcceptableUpdateDelay = 1,
		LargeReplicatorSerializeWrite4 = true,
	}

	local function SSSetFFlags()
		if type(setfflag) ~= "function" then return end
		for k, v in pairs(FFLAGS) do
			pcall(setfflag, k, tostring(v))
		end
	end

	local function SSEquipGrapple()
		if BackpackLock and BackpackLock.suspend then
			pcall(BackpackLock.suspend, 4)
		end
		local char = player.Character
		local bp = player:FindFirstChild("Backpack")
		if not char or not bp then return end

		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool") then tool.Parent = bp end
		end

		local carpet = bp:FindFirstChild(_FH_ActiveMount)
		if carpet then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then pcall(hum.EquipTool, hum, carpet) end
		end
	end

	local function _stealIsGiant()
		local c = player.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if not hum then return false end
		local scale = hum:FindFirstChild("BodyHeightScale")
			or hum:FindFirstChild("BodyDepthScale")
			or hum:FindFirstChild("BodyWidthScale")
		return scale and scale:IsA("NumberValue") and scale.Value >= 2.5
	end

	local function drinkPotion()
		if (M.potion or AutoBigPotion.enabled)
			and not _stealIsGiant()
			and AutoBigPotion.activate
			and isInEnemyPlot()
		then
			pcall(AutoBigPotion.activate)
		end
	end

	local function isPrimeMethod() return M.method == "TP" end
	local function isWalkMode() return M.method ~= "TP" end

	local canDirectTp, tpThroughWaypoints, walkTo

	canDirectTp = function(HRP, targetPos)
		if not HRP or not targetPos then return false end

		local origin = HRP.Position
		local ignored = { player.Character }

		for _ = 1, 12 do
			local direction = targetPos - origin
			if direction.Magnitude <= 0.05 then return true end

			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Blacklist
			params.FilterDescendantsInstances = ignored
			params.IgnoreWater = true

			local result = Workspace:Raycast(origin, direction, params)
			if not result then return true end

			local hit = result.Instance
			if not hit then return true end

			if hit:IsA("BasePart") and not hit.CanCollide then
				table.insert(ignored, hit)
				origin = result.Position + direction.Unit * 0.1
			else
				return (result.Position - targetPos).Magnitude <= 3
			end
		end

		return false
	end

	tpThroughWaypoints = function(HRP, waypoints)
		if #waypoints == 0 then return end

		local startIndex = 1
		for i = #waypoints, 1, -1 do
			if canDirectTp(HRP, waypoints[i]) then startIndex = i; break end
		end

		for i = startIndex, #waypoints do
			HRP.CFrame = CFrame.new(waypoints[i])
			if i < #waypoints then taskwait(0.135) end
		end
	end

	walkTo = function(HRP, targetPos, speed, arriveDist, timeout)
		if not HRP or not HRP.Parent or not targetPos then return end

		speed = speed or 180
		arriveDist = arriveDist or 6
		timeout = timeout or 6

		SSEquipGrapple()

		local _ctrls
		pcall(function()
			_ctrls = require(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
		end)
		if _ctrls then _ctrls:Disable() end

		if Booster and Booster.suspend then pcall(Booster.suspend, "steal") end

		pcall(function()
			local start = tick()
			while HRP and HRP.Parent do
				local d = targetPos - HRP.Position
				local flat = Vector3.new(d.X, 0, d.Z)
				local mag = flat.Magnitude

				if mag < arriveDist then break end
				if tick() - start > timeout then break end

				local effSpeed = speed
				if mag < 25 then effSpeed = math.max(60, speed * (mag / 25)) end

				local dir = flat.Unit
				HRP.Velocity = Vector3.new(dir.X * effSpeed, HRP.Velocity.Y, dir.Z * effSpeed)
				taskwait()
			end

			if HRP and HRP.Parent then
				HRP.Velocity = Vector3.zero
				HRP.CFrame = CFrame.new(targetPos)
			end
		end)

		if _ctrls then _ctrls:Enable() end
		if Booster and Booster.unsuspend then pcall(Booster.unsuspend, "steal") end
	end

	local function _v2TeleportHRP(position)
		local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not h then return end
		h.Velocity = Vector3.zero
		h.CFrame = CFrame.new(position)
	end

	local _v2PlotController

	local function _v2GetMyPlotModel()
		if not _v2PlotController then
			pcall(function()
				_v2PlotController = require(
					game:GetService("ReplicatedStorage"):WaitForChild("Controllers"):WaitForChild("PlotController")
				)
			end)
		end
		local model
		pcall(function() model = _v2PlotController:GetMyPlot().PlotModel end)
		return model
	end

	function M.SSDoTeleport()
		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then return end

		SSEquipGrapple()
		M.semiInstantMode = "Semi"

		local wasBoosterOn = Booster and Booster.userEnabled
		if wasBoosterOn and Booster.set then pcall(Booster.set, false) end

		local wasPotionOn = AutoBigPotion and AutoBigPotion.enabled
		if wasPotionOn and AutoBigPotion.set then pcall(AutoBigPotion.set, false) end
		if AutoBigPotion and AutoBigPotion.clearSession then pcall(AutoBigPotion.clearSession) end

		local plots = Workspace:FindFirstChild("Plots")
		if not plots then return end

		local myName = player.DisplayName
		local enemyPlots = {}

		for _, plot in ipairs(plots:GetChildren()) do
			local sign = plot:FindFirstChild("PlotSign")
			local label = sign
				and sign:FindFirstChild("SurfaceGui")
				and sign.SurfaceGui:FindFirstChild("Frame")
				and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")

			if label and label.Text ~= "Empty Base" then
				local owner = label.Text
					:gsub("'s Base$", "")
					:gsub("'s base$", "")
					:gsub("%s+$", "")
				if owner ~= myName then
					table.insert(enemyPlots, plot)
				end
			end
		end

		local function getClosestPodium()
			if #enemyPlots == 0 then return nil end

			local best, bestDist = nil, math.huge

			for _, plot in ipairs(enemyPlots) do
				local podiums = plot:FindFirstChild("AnimalPodiums")
				if not podiums then continue end

				local plotPos
				pcall(function()
					if plot.PrimaryPart then
						plotPos = plot.PrimaryPart.Position
					else
						plotPos = plot:GetPivot().Position
					end
				end)
				if not plotPos then
					local part = plot:FindFirstChildWhichIsA("BasePart", true)
					if part then plotPos = part.Position end
				end

				local plotIsBase1 = true
				if plotPos then
					local d1 = (plotPos - BASES.b1.refVec).Magnitude
					local d2 = (plotPos - BASES.b2.refVec).Magnitude
					plotIsBase1 = d1 < d2
				end

				for _, pname in ipairs({ "1", "10" }) do
					local podium = podiums:FindFirstChild(pname)
					if not podium then continue end

					local cm = podium:FindFirstChild("Claim")
						and podium.Claim:FindFirstChild("Main")
					if not cm then continue end

					local d = (hrp.Position - cm.Position).Magnitude
					if d < bestDist then
						bestDist = d

						local spawn = podium:FindFirstChild("Base")
							and podium.Base:FindFirstChild("Spawn")
						local pa = spawn and spawn:FindFirstChild("PromptAttachment")
						local prompt = pa and pa:FindFirstChildWhichIsA("ProximityPrompt")

						if prompt then
							best = {
								plot = plot,
								podiumName = pname,
								position = cm.Position,
								prompt = prompt,
								promptPos = pa.WorldPosition,
								distance = d,
								isEnemyBase1 = plotIsBase1,
							}
						end
					end
				end
			end

			return best
		end

		local podium = getClosestPodium()
		if not podium then return end

		local finalPos
		do
			local dB1 = (podium.position - BASES.b1.refVec).Magnitude
			local dB2 = (podium.position - BASES.b2.refVec).Magnitude
			finalPos = (dB1 < dB2) and BASES.b1.finalPos or BASES.b2.finalPos
		end

		local carpet = char:FindFirstChild(_FH_ActiveMount)
			or (player.Backpack and player.Backpack:FindFirstChild(_FH_ActiveMount))
		if carpet then pcall(hum.EquipTool, hum, carpet) end

		local netCtx = _FH_StartTrip({
			plotName = podium.plot.Name,
			pod = tonumber(podium.podiumName) or podium.podiumName,
		})
		M._semiStealCtx = netCtx

		local function doTpSequence(HRP, fPos, pod)
			local isAtBase1
			do
				local dB1 = (pod.position - BASES.b1.refVec).Magnitude
				local dB2 = (pod.position - BASES.b2.refVec).Magnitude
				isAtBase1 = dB1 < dB2
			end

			local redPos = isAtBase1
				and Vector3.new(-337, -5, 100)
				or Vector3.new(-335, -5, 20)

			local greenPos = isAtBase1
				and Vector3.new(-347.12, -6.67, 81.64)
				or Vector3.new(-349.43, -6.78, 37.47)

			local approachWaypoints = isAtBase1
				and {
					Vector3.new(-352.54, -6.83, 6.66),
					Vector3.new(-351.49, -6.65, 113.72),
					Vector3.new(-337, -5, 103),
				}
				or {
					Vector3.new(-351.49, -6.65, 113.72),
					Vector3.new(-352.54, -6.83, 6.66),
					Vector3.new(-334.80, -5.04, 18.90),
				}

			local function doApproachPath(HRP_, _pod, _isAtBase1)
				if isWalkMode() then
					local startIndex = 1
					for i = #approachWaypoints, 1, -1 do
						if canDirectTp(HRP_, approachWaypoints[i]) then
							startIndex = i; break
						end
					end
					for i = startIndex, #approachWaypoints do
						walkTo(HRP_, approachWaypoints[i], 180)
					end
					return
				end

				if _pod and redPos and canDirectTp(HRP_, redPos) then
					HRP_.CFrame = CFrame.new(redPos)
				else
					tpThroughWaypoints(HRP_, approachWaypoints)
				end
			end

			if isPrimeMethod() then
				local prompt = pod and pod.prompt
				if not prompt or not prompt.Parent then return end

				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = math.huge
				SSEquipGrapple()

				HRP.CFrame = isAtBase1
					and CFrame.new(-343.08, -6.84, 93.20)
					or CFrame.new(-342.91, -6.81, 28.00)
				taskwait(0.25)

				HRP.CFrame = isAtBase1
					and CFrame.new(-340.16, -7.29, 48.82)
					or CFrame.new(-340.16, -7.29, 72.40)
				taskwait(0.12)

				HRP.CFrame = isAtBase1
					and CFrame.new(-341.26, -7.29, 66.95)
					or CFrame.new(-341.26, -7.29, 54.27)
				taskwait(0.12)

				HRP.CFrame = isAtBase1
					and CFrame.new(-339.93, -7.29, 82.14)
					or CFrame.new(-339.63, -7.29, 39.33)
				taskwait(0.18)

				local ctx = __FH_v2.startStealHold(prompt, "TP")

				HRP.CFrame = isAtBase1
					and CFrame.new(-354.04, -7.21, 90.42)
					or CFrame.new(-354.04, -7.21, 28.00)
				taskwait(0.45)

				HRP.CFrame = isAtBase1
					and CFrame.new(-334.60, -5.00, 101.30)
					or CFrame.new(-334.60, -5.00, 19.30)

				if ctx and ctx.holdBeganAt then
					while tick() - ctx.holdBeganAt < __MIN_HOLD_TIME_v2 do
						taskwait()
					end
				end

				drinkPotion()
				SSEquipGrapple()

				HRP.CFrame = isAtBase1
					and CFrame.new(-351.53, -7.29, 83.66)
					or CFrame.new(-350.62, -7.29, 35.91)

				if ctx then __FH_v2.finishStealHold(ctx) end
			else
				local ctx

				if pod and pod.prompt and pod.prompt.Parent then
					pod.prompt.RequiresLineOfSight = false
					pod.prompt.MaxActivationDistance = math.huge
					ctx = __FH_v2.startStealHold(pod.prompt, "Walk")
				end

				if ctx then __FH_v2.waitForStealTime(ctx, 0.8) end

				doApproachPath(HRP, pod, isAtBase1)
				taskwait(0.25)
				drinkPotion()
				SSEquipGrapple()

				if pod and pod.prompt and pod.prompt.Parent and ctx then
					if greenPos then
						__FH_v2.waitForStealTime(ctx, 1.3)
						HRP.CFrame = CFrame.new(greenPos)
					end
					__FH_v2.finishStealHold(ctx)
				end
			end

			local startTime = tick()
			while player:GetAttribute("Stealing") == nil do
				if tick() - startTime >= 1 then break end
				taskwait(0.1)
			end
		end

		taskspawn(function()
			pcall(function()
				doTpSequence(hrp, finalPos, podium)
				M._semiStealCtx = nil
			end)

			if wasBoosterOn and Booster.set then pcall(Booster.set, true) end

			if M.autoWalk and M.walkPoint then
				if Booster and Booster.unsuspend then pcall(Booster.unsuspend, "steal") end
				pcall(function()
					local c = player.Character
					local hum = c and c:FindFirstChildOfClass("Humanoid")
					local hrp = c and c:FindFirstChild("HumanoidRootPart")

					if hum and hrp then
						local deadline = tick() + 15

						while tick() < deadline do
							local flat = Vector3.new(
								M.walkPoint.X - hrp.Position.X,
								0,
								M.walkPoint.Z - hrp.Position.Z
							)
							if flat.Magnitude < 3 then break end
							hum:MoveTo(M.walkPoint)
							taskwait()

							c = player.Character
							hrp = c and c:FindFirstChild("HumanoidRootPart")
							hum = c and c:FindFirstChildOfClass("Humanoid")
							if not (hrp and hum) then break end
						end
					end
				end)
			end
		end)
	end

	M.SSDoSteal = M.SSDoTeleport

	function M.execute()
		local _lp = game:GetService("Players").LocalPlayer
		if _lp and _lp:GetAttribute("Stealing") then return end
		if M.debounce then return end

		M.debounce = true
		taskspawn(function()
			SSSetFFlags()
			M.SSDoTeleport()
			taskwait(1.2)
			M.debounce = false
		end)
	end

	local _RESET_MAX_DURATION = 0.05
	local _resetCooldown = false
	local _resetThread = nil
	local _currentCharacter = nil
	local _resetSuccessful = false
	local _stopResetSequence = false
	local _cameraLocked = false
	local _lockedCameraCFrame = nil

	local function _stopReset()
		_stopResetSequence = true
		if _resetThread then task.cancel(_resetThread) _resetThread = nil end
		_resetCooldown = false
		_currentCharacter = nil
		_cameraLocked = false
		local ch = player.Character
		if ch then
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if hum then pcall(function()
				hum.HipHeight = 2
				local rp = ch:FindFirstChild("HumanoidRootPart")
				if rp then rp.CanCollide = true end
				for _, p in ipairs(ch:GetChildren()) do
					if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.CanCollide = true end
				end
			end) end
		end
	end

	player.CharacterAdded:Connect(function()
		_stopReset()
		_resetCooldown = false
		_currentCharacter = nil
		_resetSuccessful = false
		_stopResetSequence = false
		_cameraLocked = false
	end)

	taskspawn(function()
		local camera = workspace.CurrentCamera
		while true do
			task.wait(0.016)
			if _cameraLocked and _lockedCameraCFrame and camera then
				camera.CFrame = _lockedCameraCFrame
			end
		end
	end)

	function M.activate()
		if _resetCooldown then return end
		_resetCooldown = true
		_resetSuccessful = false
		_stopResetSequence = false
		_cameraLocked = false

		local character = player.Character
		if not character then _resetCooldown = false return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then _resetCooldown = false return end

		local camera = workspace.CurrentCamera
		if camera then
			_lockedCameraCFrame = camera.CFrame
			_cameraLocked = true
		end

		_currentCharacter = character
		local isRespawning = false

		_resetThread = task.spawn(function()
			local attempts = 0
			local maxAttempts = 40
			local originalHipHeight = humanoid.HipHeight

			while character and character.Parent and humanoid and humanoid.Health > 0 and not isRespawning and not _stopResetSequence do
				if player.Character ~= character then isRespawning = true break end
				pcall(function()
					humanoid.HipHeight = 1e30
					humanoid.AutoRotate = true
					local rp = character:FindFirstChild("HumanoidRootPart")
					if rp then rp.CanCollide = false end
					for _, p in ipairs(character:GetChildren()) do
						if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.CanCollide = false end
					end
				end)
				if not character or not character.Parent or not humanoid or humanoid.Health <= 0 or player.Character ~= character then
					_resetSuccessful = true break
				end
				attempts = attempts + 1
				if attempts >= maxAttempts then break end
				task.wait(_RESET_MAX_DURATION)
			end

			if not _resetSuccessful then
				if character and character.Parent and humanoid and humanoid.Health > 0 and not isRespawning then
					pcall(function() humanoid.Health = 0 end)
					task.wait(0.1)
					if not character.Parent or humanoid.Health <= 0 then _resetSuccessful = true end
				end
			end

			if not _resetSuccessful and character and character.Parent and humanoid then
				pcall(function()
					humanoid.HipHeight = originalHipHeight
					local rp = character:FindFirstChild("HumanoidRootPart")
					if rp then rp.CanCollide = true end
					for _, p in ipairs(character:GetChildren()) do
						if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.CanCollide = true end
					end
				end)
			end

			_cameraLocked = false
			_resetCooldown = false
			_resetThread = nil
			_currentCharacter = nil
			_stopResetSequence = false
		end)
	end

	return M
end)()


-- ── EdgeMeowl-style GUI ──

local keybind = Enum.KeyCode.F5

local function applySpinningGradient(uiGradient)
	taskspawn(function()
		while uiGradient and uiGradient.Parent do
			local t = TweenService:Create(
				uiGradient,
				TweenInfo.new(3.5, Enum.EasingStyle.Linear),
				{ Rotation = 360 }
			)
			t:Play()
			t.Completed:Wait()
			uiGradient.Rotation = 0
		end
	end)
end

local FULL_HEIGHT = 170
local MINI_HEIGHT = 40
local PANEL_W = 230

local ScreenGui
local MainFrame
local BorderFrame

local function makeHeaderButton(name, char, xOffset, hoverColor)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 24, 0, 24)
	btn.Position = UDim2.new(1, xOffset, 0, 4)
	btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	btn.AutoButtonColor = false
	btn.Text = char
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 12
	btn.Font = Enum.Font.GothamBold
	btn.Parent = MainFrame

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn

	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 255, 255)
	s.Thickness = 1
	s.Parent = btn

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = hoverColor
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	end)
	return btn
end

local function createToggleRow(labelText, yPos, startOn, onChanged)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 140, 0, 18)
	lbl.Position = UDim2.new(0, 15, 0, yPos)
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextSize = 11
	lbl.Font = Enum.Font.GothamSemibold
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = MainFrame

	local btnBorder = Instance.new("Frame")
	btnBorder.Size = UDim2.new(0, 62, 0, 20)
	btnBorder.Position = UDim2.new(1, -75, 0, yPos + 1)
	btnBorder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	btnBorder.BorderSizePixel = 0
	btnBorder.ZIndex = 1
	btnBorder.Parent = MainFrame

	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 7)
	bc.Parent = btnBorder

	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	bg.Parent = btnBorder
	applySpinningGradient(bg)

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -2, 1, -2)
	btn.Position = UDim2.new(0, 1, 0, 1)
	btn.TextColor3 = Color3.fromRGB(200, 200, 200)
	btn.TextSize = 10
	btn.Font = Enum.Font.GothamBold
	btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	btn.Parent = btnBorder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = btn

	local state = startOn

	local function render()
		if state then
			btn.Text = "ON"
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.Text = "OFF"
			btn.TextColor3 = Color3.fromRGB(200, 200, 200)
		end
	end
	render()

	btn.MouseButton1Click:Connect(function()
		state = not state
		render()
		onChanged(state)
	end)
	return btn
end

local function buildGUI()
	local oldGui = game:GetService("CoreGui"):FindFirstChild("HalfwayStealV2")
		or Players.LocalPlayer and Players.LocalPlayer.PlayerGui:FindFirstChild("HalfwayStealV2")
	if oldGui then oldGui:Destroy() end

	ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "HalfwayStealV2"
	ScreenGui.ResetOnSpawn = false

	local ok = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
	if not ok then
		ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end

	BorderFrame = Instance.new("Frame")
	BorderFrame.Name = "BorderFrame"
	BorderFrame.Size = UDim2.new(0, PANEL_W + 4, 0, FULL_HEIGHT + 4)
	BorderFrame.Position = UDim2.new(0.5, -(PANEL_W + 4) / 2, 0.4, -(FULL_HEIGHT + 4) / 2)
	BorderFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	BorderFrame.BorderSizePixel = 0
	BorderFrame.ZIndex = 0
	BorderFrame.Parent = ScreenGui

	local BorderCorner = Instance.new("UICorner")
	BorderCorner.CornerRadius = UDim.new(0, 12)
	BorderCorner.Parent = BorderFrame

	local BorderGradient = Instance.new("UIGradient")
	BorderGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	BorderGradient.Parent = BorderFrame
	applySpinningGradient(BorderGradient)

	MainFrame = Instance.new("Frame")
	MainFrame.Name = "MainFrame"
	MainFrame.Size = UDim2.new(0, PANEL_W, 0, FULL_HEIGHT)
	MainFrame.Position = UDim2.new(0.5, -PANEL_W / 2, 0.4, -FULL_HEIGHT / 2)
	MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	MainFrame.BorderSizePixel = 0
	MainFrame.Active = true
	MainFrame.Draggable = true
	MainFrame.ClipsDescendants = true
	MainFrame.ZIndex = 1
	MainFrame.Parent = ScreenGui

	local MainCorner = Instance.new("UICorner")
	MainCorner.CornerRadius = UDim.new(0, 12)
	MainCorner.Parent = MainFrame

	local dragToggle = nil
	local dragStart = nil
	local startPos = nil

	local function updateInput(input)
		local delta = input.Position - dragStart
		local position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
		TweenService:Create(MainFrame, TweenInfo.new(0.08), { Position = position }):Play()
	end

	MainFrame.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch)
		then
			dragToggle = true
			dragStart = input.Position
			startPos = MainFrame.Position
			input.Changed:Connect(function()
				if (input.UserInputState == Enum.UserInputState.End) then
					dragToggle = false
				end
			end)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch)
			and dragToggle
		then
			updateInput(input)
		end
	end)

	local function syncBorder()
		BorderFrame.Position = UDim2.new(
			MainFrame.Position.X.Scale, MainFrame.Position.X.Offset - 2,
			MainFrame.Position.Y.Scale, MainFrame.Position.Y.Offset - 2
		)
		BorderFrame.Size = UDim2.new(
			0, MainFrame.Size.X.Offset + 4,
			0, MainFrame.Size.Y.Offset + 4
		)
	end

	local borderSyncConn = MainFrame:GetPropertyChangedSignal("Position"):Connect(syncBorder)
	local borderSyncConn2 = MainFrame:GetPropertyChangedSignal("Size"):Connect(syncBorder)
	syncBorder()

	-- Header
	local HeaderLabel = Instance.new("TextLabel")
	HeaderLabel.Name = "HeaderLabel"
	HeaderLabel.Size = UDim2.new(1, -55, 0, 22)
	HeaderLabel.Position = UDim2.new(0, 15, 0, 2)
	HeaderLabel.BackgroundTransparency = 1
	HeaderLabel.Text = "Halfway Steal"
	HeaderLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	HeaderLabel.TextSize = 14
	HeaderLabel.Font = Enum.Font.GothamBold
	HeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
	HeaderLabel.Parent = MainFrame

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 1
	titleStroke.Parent = HeaderLabel

	local DiscordLabel = Instance.new("TextLabel")
	DiscordLabel.Name = "DiscordLabel"
	DiscordLabel.Size = UDim2.new(1, -55, 0, 14)
	DiscordLabel.Position = UDim2.new(0, 15, 0, 24)
	DiscordLabel.BackgroundTransparency = 1
	DiscordLabel.Text = "v2 — standalone"
	DiscordLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	DiscordLabel.TextSize = 10
	DiscordLabel.Font = Enum.Font.Gotham
	DiscordLabel.TextXAlignment = Enum.TextXAlignment.Left
	DiscordLabel.Parent = MainFrame

	-- Minimize (using makeHeaderButton)
	local MinimizeButton = makeHeaderButton("MinimizeButton", "–", -35, Color3.fromRGB(80, 80, 80))

	local minimized = false
	MinimizeButton.MouseButton1Click:Connect(function()
		minimized = not minimized
		local h = minimized and MINI_HEIGHT or FULL_HEIGHT
		MinimizeButton.Text = minimized and "+" or "–"
		TweenService:Create(MainFrame, TweenInfo.new(0.2),
			{ Size = UDim2.new(0, PANEL_W, 0, h) }):Play()
	end)

	-- OPTIONS label
	local OptionsLabel = Instance.new("TextLabel")
	OptionsLabel.Name = "OptionsLabel"
	OptionsLabel.Size = UDim2.new(0, 100, 0, 18)
	OptionsLabel.Position = UDim2.new(0, 15, 0, 78)
	OptionsLabel.BackgroundTransparency = 1
	OptionsLabel.Text = "OPTIONS"
	OptionsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	OptionsLabel.TextSize = 12
	OptionsLabel.Font = Enum.Font.GothamBold
	OptionsLabel.TextXAlignment = Enum.TextXAlignment.Left
	OptionsLabel.Parent = MainFrame

	-- Steal Now button (spinning border)
	local stealBtnBorder = Instance.new("Frame")
	stealBtnBorder.Size = UDim2.new(0, 96, 0, 26)
	stealBtnBorder.Position = UDim2.new(0, 15, 0, 44)
	stealBtnBorder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	stealBtnBorder.BorderSizePixel = 0
	stealBtnBorder.ZIndex = 1
	stealBtnBorder.Parent = MainFrame

	local sbCorner = Instance.new("UICorner")
	sbCorner.CornerRadius = UDim.new(0, 9)
	sbCorner.Parent = stealBtnBorder

	local sbGrad = Instance.new("UIGradient")
	sbGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	sbGrad.Parent = stealBtnBorder
	applySpinningGradient(sbGrad)

	local stealBtn = Instance.new("TextButton")
	stealBtn.Size = UDim2.new(1, -2, 1, -2)
	stealBtn.Position = UDim2.new(0, 1, 0, 1)
	stealBtn.Text = "Steal Now"
	stealBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	stealBtn.TextSize = 11
	stealBtn.Font = Enum.Font.GothamBold
	stealBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	stealBtn.Parent = stealBtnBorder

	local stealInnerCorner = Instance.new("UICorner")
	stealInnerCorner.CornerRadius = UDim.new(0, 7)
	stealInnerCorner.Parent = stealBtn

	stealBtn.MouseButton1Click:Connect(function()
		HalfwaySteal.execute()
	end)

	-- Activate button (spinning border)
	local actBtnBorder = Instance.new("Frame")
	actBtnBorder.Size = UDim2.new(0, 96, 0, 26)
	actBtnBorder.Position = UDim2.new(0, 122, 0, 44)
	actBtnBorder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	actBtnBorder.BorderSizePixel = 0
	actBtnBorder.ZIndex = 1
	actBtnBorder.Parent = MainFrame

	local abCorner = Instance.new("UICorner")
	abCorner.CornerRadius = UDim.new(0, 9)
	abCorner.Parent = actBtnBorder

	local abGrad = Instance.new("UIGradient")
	abGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	abGrad.Parent = actBtnBorder
	applySpinningGradient(abGrad)

	local actBtn = Instance.new("TextButton")
	actBtn.Size = UDim2.new(1, -2, 1, -2)
	actBtn.Position = UDim2.new(0, 1, 0, 1)
	actBtn.Text = "Activate"
	actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	actBtn.TextSize = 11
	actBtn.Font = Enum.Font.GothamBold
	actBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	actBtn.Parent = actBtnBorder

	local actInnerCorner = Instance.new("UICorner")
	actInnerCorner.CornerRadius = UDim.new(0, 7)
	actInnerCorner.Parent = actBtn

	actBtn.MouseButton1Click:Connect(function()
		HalfwaySteal.activate()
	end)

	-- Use Potion toggle
	createToggleRow("Use Potion", 100, false, function(on)
		HalfwaySteal.setPotion(on)
	end)

	-- Method selector (Walk / TP) — like a toggle row but cycles text
	local methodLbl = Instance.new("TextLabel")
	methodLbl.Size = UDim2.new(0, 140, 0, 18)
	methodLbl.Position = UDim2.new(0, 15, 0, 120)
	methodLbl.BackgroundTransparency = 1
	methodLbl.Text = "Method"
	methodLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	methodLbl.TextSize = 11
	methodLbl.Font = Enum.Font.GothamSemibold
	methodLbl.TextXAlignment = Enum.TextXAlignment.Left
	methodLbl.Parent = MainFrame

	local methodBorder = Instance.new("Frame")
	methodBorder.Size = UDim2.new(0, 62, 0, 20)
	methodBorder.Position = UDim2.new(1, -75, 0, 121)
	methodBorder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	methodBorder.BorderSizePixel = 0
	methodBorder.ZIndex = 1
	methodBorder.Parent = MainFrame

	local methodBC = Instance.new("UICorner")
	methodBC.CornerRadius = UDim.new(0, 7)
	methodBC.Parent = methodBorder

	local methodBG = Instance.new("UIGradient")
	methodBG.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(15, 15, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	methodBG.Parent = methodBorder
	applySpinningGradient(methodBG)

local methodIsPrime = false

	local methodBtn = Instance.new("TextButton")
	methodBtn.Size = UDim2.new(1, -2, 1, -2)
	methodBtn.Position = UDim2.new(0, 1, 0, 1)
	methodBtn.Text = "Walk"
	methodBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	methodBtn.TextSize = 10
	methodBtn.Font = Enum.Font.GothamBold
	methodBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	methodBtn.Parent = methodBorder

	local methodInnerCorner = Instance.new("UICorner")
	methodInnerCorner.CornerRadius = UDim.new(0, 5)
	methodInnerCorner.Parent = methodBtn

	methodBtn.MouseButton1Click:Connect(function()
		methodIsPrime = not methodIsPrime
		methodBtn.Text = methodIsPrime and "TP" or "Walk"
		HalfwaySteal.setMethod(methodIsPrime and "TP" or "Walk")
	end)

	-- Auto AP toggle
	createToggleRow("Auto AP", 142, false, function(on)
		HalfwaySteal.autoAP = on
	end)
end

buildGUI()

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == keybind then
		HalfwaySteal.execute()
	end
end)

print("Halfway Steal V2")
