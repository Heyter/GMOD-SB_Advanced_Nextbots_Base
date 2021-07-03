
--[[------------------------------------
	NEXTBOT:BehaveStart
	Creating behaviour thread using NEXTBOT:BehaviourCoroutine. Also setups task list and default tasks.
--]]------------------------------------
function ENT:BehaveStart()
	self:SetupCollisionBounds()

	self:SetupTaskList(self.m_TaskList)
	self:SetupTasks()

	self.BehaviourThread = coroutine.create(function() self:BehaviourCoroutine() end)
end

--[[------------------------------------
	NEXTBOT:BehaveUpdate
	This is where bot updating
--]]------------------------------------
function ENT:BehaveUpdate(interval)
	self.BehaveInterval = interval
	
	if self.m_Physguned then
		self.loco:SetVelocity(vector_origin)
	end
	
	self:StuckCheck()
	
	local disable = self:DisableBehaviour()
	
	if !disable then
		local crouch = self:ShouldCrouch()
		if crouch!=self:IsCrouching() and (crouch or self:CanStandUp()) then
			self:SwitchCrouch(crouch)
		end
	end
	
	self:SetupSpeed()
	self:SetupMotionType()
	self:ProcessFootsteps()
	self.m_FallSpeed = -self.loco:GetVelocity().z
	
	if !disable then
		self:SetupEyeAngles()
		self:UpdatePhysicsObject()
		self:ForgetOldEnemies()
		
		local ply = self:GetControlPlayer()
		if IsValid(ply) then
			-- Sending current weapon clips data
		
			if self:HasWeapon() then
				local wep = self:GetActiveWeapon()
				
				self:SetWeaponClip1(wep:Clip1())
				self:SetWeaponClip2(wep:Clip2())
				self:SetWeaponMaxClip1(wep:GetMaxClip1())
				self:SetWeaponMaxClip2(wep:GetMaxClip2())
			end
			
			-- Calling behavior think for player control
			self:BehaviourPlayerControlThink(ply)
			
			-- Calling task callbacks
			self:RunTask("PlayerControlUpdate",interval,ply)
			
			self.m_ControlPlayerOldButtons = self.m_ControlPlayerButtons
		else
			-- Calling behaviour with coroutine type
			if self.BehaviourThread then
				if coroutine.status(self.BehaviourThread)=="dead" then
					self.BehaviourThread = nil
					ErrorNoHalt("NEXTBOT:BehaviourCoroutine() has been finished!\n")
				else
					assert(coroutine.resume(self.BehaviourThread))
				end
			end
			
			-- Calling behaviour with think type
			self:BehaviourThink()
			
			-- Calling task callbacks
			self:RunTask("BehaveUpdate",interval)
		end
	end
	
	self:SetupGesturePosture()
end

--[[------------------------------------
	Name: NEXTBOT:BehaviourCoroutine
	Desc: Override this function to control bot using coroutine type.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:BehaviourCoroutine()
	while true do
		coroutine.yield()
	end
end

--[[------------------------------------
	Name: NEXTBOT:DisableBehaviour
	Desc: Decides should behaviour be disabled.
	Arg1: 
	Ret1: bool | Return true to disable.
--]]------------------------------------
function ENT:DisableBehaviour()
	return self:IsPostureActive() or self:IsGestureActive(true) or GetConVar("ai_disabled"):GetBool() and !self:IsControlledByPlayer() or self:RunTask("DisableBehaviour")
end

--[[------------------------------------
	Name: NEXTBOT:BehaviourThink
	Desc: Override this function to control bot using think type.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:BehaviourThink()
	if !game.SinglePlayer() and (!IsValid(Entity(1)) or !Entity(1):IsListenServerHost()) then return end

	local dist = 100 * 100
	local ent = Entity(1)
	local pos = ent:GetPos()
	local near = self:GetPos():DistToSqr(pos) < dist

	if !near then
		if !self:PathIsValid() or self:GetPathPos():Distance(pos) > dist then
			self:SetupPath(pos)
		end

		if self:PathIsValid() then
			self:GetPath():Draw()
			self:ControlPath(true)
		end
	else
		if self:PathIsValid() then
			self:GetPath():Invalidate()
		end
	end
end

--[[------------------------------------
	Name: NEXTBOT:BehaviourPlayerControlThink
	Desc: Override this function to control bot with player.
	Arg1: Player | ply | Player who controls bot
	Ret1: 
--]]------------------------------------
function ENT:BehaviourPlayerControlThink(ply)
	local eyeang = ply:EyeAngles()
	local forward,right = eyeang:Forward(),eyeang:Right()
	local f = self:ControlPlayerKeyDown(IN_FORWARD) and 1 or self:ControlPlayerKeyDown(IN_BACK) and -1 or 0
	local r = self:ControlPlayerKeyDown(IN_MOVELEFT) and 1 or self:ControlPlayerKeyDown(IN_MOVERIGHT) and -1 or 0

	if f!=0 or r!=0 then
		local eyeang = ply:EyeAngles()
		eyeang.p = 0
		eyeang.r = 0
		local movedir = eyeang:Forward()*f-eyeang:Right()*r

		self:Approach(self:GetPos()+movedir*100)
	end

	if self:ControlPlayerKeyPressed(IN_JUMP) then
		self:Jump()
	end

	if self:HasWeapon() then
		local wep = self:GetActiveLuaWeapon()

		if self[wep.Primary.Automatic and "ControlPlayerKeyDown" or "ControlPlayerKeyPressed"](self,IN_ATTACK) then
			if wep:Clip1()<=0 and wep:GetMaxClip1()>0 then
				self:WeaponReload()
			else
				self:WeaponPrimaryAttack()
			end
		end

		if self[wep.Secondary.Automatic and "ControlPlayerKeyDown" or "ControlPlayerKeyPressed"](self,IN_ATTACK2) then
			self:WeaponSecondaryAttack()
		end

		if self:ControlPlayerKeyPressed(IN_RELOAD) then
			self:WeaponReload()
		end
	end

	if self:ControlPlayerKeyPressed(IN_USE) then
		local pos = self:GetShootPos()
		local tr = util.TraceLine({start = pos,endpos = pos+forward*72,filter = self})

		if tr.Hit then
			if self:CanPickupWeapon(tr.Entity) and !self:HasWeapon() then
				self:SetupWeapon(tr.Entity)
			else
				tr.Entity:Input("Use",self,self)
			end
		end
	end
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesAdd
	Desc: Adds a capability to the bot.
	Arg1: number | cap | Capabilities to add. See CAP_ Enums
	Ret1: 
--]]------------------------------------
function ENT:CapabilitiesAdd(cap)
	self.m_Capabilities = bit.bor(self.m_Capabilities,cap)
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesClear
	Desc: Clears all capabilities of bot.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:CapabilitiesClear()
	self.m_Capabilities = 0
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesGet
	Desc: Returns all capabilities including weapon capabilities.
	Arg1: 
	Ret1: number | Capabilities. See CAP_ Enums
--]]------------------------------------
function ENT:CapabilitiesGet()
	return bit.bor(self.m_Capabilities,self:HasWeapon() and self:GetActiveLuaWeapon():GetCapabilities() or 0)
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesRemove
	Desc: Removes capability from bot.
	Arg1: number | cap | Capabilities to remove. See CAP_ Enums
	Ret1: 
--]]------------------------------------
function ENT:CapabilitiesRemove(cap)
	self.m_Capabilities = bit.bxor(bit.bor(self.m_Capabilities,cap),cap)
end