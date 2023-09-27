--[[
Name: Banzai-1.1
Revision: $Rev: 21576 $
Author(s): Rabbit (rabbit.magtheridon@gmail.com), maia
Documentation: http://www.wowace.com/index.php/Banzai-1.1_API_Documentation
SVN: http://svn.wowace.com/wowace/trunk/BanzaiLib/Banzai-1.1
Description: Aggro notification library.
Dependencies: AceLibrary, AceOO-2.0, AceEvent-2.0, Roster-2.1
]]

--[[
BanzaiLib is copyrighted 2006 by Rabbit.

This addon is distributed under the terms of the Creative Commons
Attribution-NonCommercial-ShareAlike 2.0 license.

http://creativecommons.org/licenses/by-nc-sa/2.5/

You may distribute and use these libraries without making your mod adhere to the
same license, as long as you preserve the license text embedded in the
libraries.

Any and all questions regarding our stance and licensing should be
directed to the #wowace IRC channel on irc.freenode.net.
]]

-------------------------------------------------------------------------------
-- Locals
-------------------------------------------------------------------------------

local MAJOR_VERSION = "Banzai-1.1"
local MINOR_VERSION = "$Revision: 21576 $"

if not AceLibrary then error(MAJOR_VERSION .. " requires AceLibrary.") end
if not AceLibrary:IsNewVersion(MAJOR_VERSION, MINOR_VERSION) then return end

if AceLibrary:HasInstance("Banzai-1.0") then error(MAJOR_VERSION .. " can't run alongside Banzai-1.0.") end
if not AceLibrary:HasInstance("AceOO-2.0") then error(MAJOR_VERSION .. " requires AceOO-2.0.") end
if not AceLibrary:HasInstance("AceEvent-2.0") then error(MAJOR_VERSION .. " requires AceEvent-2.0.") end
if not AceLibrary:HasInstance("Roster-2.1") then error(MAJOR_VERSION .. " requires Roster-2.1.") end

local lib = {}
AceLibrary("AceEvent-2.0"):embed(lib)

local RL = nil
local roster = nil
local playerName = nil

-------------------------------------------------------------------------------
-- Local heap
-------------------------------------------------------------------------------

local new, del
do
	local cache = setmetatable({},{__mode='k'})
	function new()
		local t = next(cache)
		if t then
			cache[t] = nil
			return t
		else
			return {}
		end
	end
	function del(t)
		for k in pairs(t) do
			t[k] = nil
		end
		cache[t] = true
		return nil
	end
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

-- Activate a new instance of this library
function activate(self, oldLib, oldDeactivate)
	if oldLib then
		self.vars = oldLib.vars
		if oldLib:IsEventScheduled("UpdateAggroList") then
			oldLib:CancelScheduledEvent("UpdateAggroList")
			self:StartOrStop()
		end
	else
		self.vars = {}
	end

	RL = AceLibrary("Roster-2.1")
	roster = RL.roster
	playerName = UnitName("player")

	if not self.vars then self.vars = {} end

	self:RegisterEvent("AceEvent_EventRegistered", "StartOrStop")
	self:RegisterEvent("AceEvent_EventUnregistered", "StartOrStop")

	if oldDeactivate then oldDeactivate(oldLib) end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

function lib:StartOrStop()
	local aceEvent = AceLibrary("AceEvent-2.0")
	if aceEvent:IsEventRegistered("Banzai_UnitGainedAggro") or
		aceEvent:IsEventRegistered("Banzai_PlayerGainedAggro") or
		aceEvent:IsEventRegistered("Banzai_UnitLostAggro") or
		aceEvent:IsEventRegistered("Banzai_PlayerLostAggro") or
		aceEvent:IsEventRegistered("Banzai_Run") then
		if not self:IsEventScheduled("UpdateAggroList") then
			self:ScheduleRepeatingEvent("UpdateAggroList", self.UpdateAggroList, 0.2, self)
			self.vars.running = true
			self:TriggerEvent("Banzai_Enabled")
		end
	elseif self:IsEventRegistered("UpdateAggroList") then
		self:CancelScheduledEvent("UpdateAggroList")
		for i, unit in pairs(roster) do
			unit.banzai = nil
			unit.banzaiModifier = nil
		end
		self.vars.running = nil
		self:TriggerEvent("Banzai_Disabled")
	end
end

-------------------------------------------------------------------------------
-- Library
-------------------------------------------------------------------------------

function lib:UpdateAggroList()
	local oldBanzai = nil

	for name, unit in pairs(roster) do
		if not oldBanzai then oldBanzai = new() end
		oldBanzai[name] = unit.banzai

		-- deduct aggro for all, increase it later for everyone with aggro
		if not unit.banzaiModifier then unit.banzaiModifier = 0 end
		unit.banzaiModifier = math.max(0, unit.banzaiModifier - 5)

		-- check for aggro
		local targetId = unit.unitid .. "target"
		if UnitExists(targetId) and UnitExists(targetId .. "target") then
			local targetName = UnitName(targetId .. "target")
			if roster[targetName] and UnitCanAttack("player", targetId) and UnitCanAttack(targetId, "player") then
				if not roster[targetName].banzaiModifier then roster[targetName].banzaiModifier = 0 end
				roster[targetName].banzaiModifier = roster[targetName].banzaiModifier + 10
				if not roster[targetName].banzaiTarget then roster[targetName].banzaiTarget = new() end
				table.insert(roster[targetName].banzaiTarget, targetId)
			end
		end

		-- cleanup
		unit.banzaiModifier = math.max(0, unit.banzaiModifier)
		unit.banzaiModifier = math.min(25, unit.banzaiModifier)

		-- set aggro
		unit.banzai = (unit.banzaiModifier > 15)
	end

	for name, unit in pairs(roster) do
		if oldBanzai[name] ~= nil and oldBanzai[name] ~= unit.banzai then
			-- Aggro status has changed.
			if unit.banzai == true and unit.banzaiTarget then
				-- Unit has aggro
				self:TriggerEvent("Banzai_UnitGainedAggro", unit.unitid, unit.banzaiTarget)
				if name == playerName then
					self:TriggerEvent("Banzai_PlayerGainedAggro", unit.banzaiTarget)
				end
			elseif unit.banzai == false then
				-- Unit lost aggro
				self:TriggerEvent("Banzai_UnitLostAggro", unit.unitid)
				if name == playerName then
					self:TriggerEvent("Banzai_PlayerLostAggro", unit.unitid)
				end
			end
		end
		if unit.banzaiTarget then
			unit.banzaiTarget = del(unit.banzaiTarget)
		end
	end

	if oldBanzai then
		oldBanzai = del(oldBanzai)
	end
end

-------------------------------------------------------------------------------
-- API
-------------------------------------------------------------------------------

function lib:GetUnitAggroByUnitId( unitId )
	if not self.vars.running then error(MAJOR_VERSION.." is not running. You must register for one of the events.") end
	local rosterUnit = RL:GetUnitObjectFromUnit(unitId)
	if not rosterUnit then return nil end
	return rosterUnit.banzai
end

function lib:GetUnitAggroByUnitName( unitName )
	if not self.vars.running then error(MAJOR_VERSION.." is not running. You must register for one of the events.") end
	local rosterUnit = RL:GetUnitObjectFromName(unitName)
	if not rosterUnit then return nil end
	return rosterUnit.banzai
end

function lib:IsRunning()
	return self:IsEventScheduled("UpdateAggroList")
end

-------------------------------------------------------------------------------
-- Register
-------------------------------------------------------------------------------
AceLibrary:Register(lib, MAJOR_VERSION, MINOR_VERSION, activate)

