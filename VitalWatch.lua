--[[
-- Name: VitalWatch
-- Author: Thrae of Maelstrom (aka "Matthew Carras")
-- Release Date: 8-25-06
--
-- Original concept by Sean Kennedy (HealthWatch), then modified by Nikolas Davis (VitalWatch).
-- This is a complete recode of the original VitalWatch, with a lot of new features.
--
-- Thanks to #wowace and #wowi-lounge on Freenode as always for
-- optimization assistance.
--]]

local _G = getfenv(0)
local strfind = string.find

local UnitExists, UnitIsUnit, UnitCanAttack, UnitIsPlayer, UnitName, UnitInRaid, UnitInParty, UnitLevel = _G.UnitExists, _G.UnitIsUnit, _G.UnitCanAttack, _G.UnitIsPlayer, _G.UnitName, _G.UnitInRaid, _G.UnitInParty, _G.UnitLevel

local GetTime = _G.GetTime

VitalWatch = AceLibrary("AceAddon-2.0"):new("AceEvent-2.0", "AceDB-2.0", "FuBarPlugin-2.0")
local VitalWatch = _G.VitalWatch
local VitalWatchLocale = _G.VitalWatchLocale
local tablet = AceLibrary("Tablet-2.0")
local roster

-- stuff for FuBar / Tablet
--VitalWatch.name = "VitalWatch"  -- should be auto provided if using AceAddon-2.0
VitalWatch.title = VitalWatchLocale.LogTitle
VitalWatch.defaultPosition = "LEFT"
VitalWatch.defaultMinimapPosition = 150
VitalWatch.cannotDetachTooltip = false
VitalWatch.hideWithoutStandby = true
VitalWatch.clickableTooltip = true -- XXX now do what?
VitalWatch.independentProfile = true
--VitalWatch.tooltipHiddenWhenEmpty = true
VitalWatch.showTitleWhenDetached = true
VitalWatch.hasIcon  = "Interface\\Icons\\Spell_ChargePositive"

local db, tmp, _

-- These are frames from the default UI
local LowHealthFrame 		= _G.LowHealthFrame
local OutOfControlFrame = _G.OutOfControlFrame

local LastPercentageHealth 
local LastPercentageMana 
local MessageLog 
local NumMessageLog = 0

local MessageFrameHoldTime = 3 	-- How long the message is held on the frame.
local MessageFrameMessageAlpha = 1

local NextQueuedMessage, NextQueuedMessageChan, NextQueuedMessagePriority, NextQueuedEmote, NextQueuedDoEmote
local DEFAULT_MsgRate = 0.2
local DEFAULT_AggroWatchRate = 5
local DEFAULT_AggroWatchOtherRate = 8

-- hopefully this won't need to be localized
local SoundPath = "Interface\\AddOns\\VitalWatch\\sounds\\"
local HeartbeatSound = SoundPath .. "Heartbeat.wav"

local DEFAULT_ThresholdCritHealth = 0.2
local DEFAULT_ThresholdLowHealth = 0.4
local DEFAULT_ThresholdCritMana = 0.2
local DEFAULT_ThresholdLowMana = 0.4
local DEFAULT_SoundCritHealth = SoundPath .. "phasers3.wav"
local DEFAULT_SoundLowHealth = SoundPath .. "blip5.wav"

local DEFAULT_SoundCritHealthByClass = {
	["DRUID"] = SoundPath .. "phasers3druid.wav",
	["HUNTER"] = SoundPath .. "phasers3hunter.wav",
	["MAGE"] = SoundPath .. "phasers3mage.wav",
	["PALADIN"] = SoundPath .. "phasers3paladin.wav",
	["PRIEST"] = SoundPath .. "phasers3priest.wav",
	["ROGUE"] = SoundPath .. "phasers3rogue.wav",
	["WARLOCK"] = SoundPath .. "phasers3warlock.wav",
	["WARRIOR"] = SoundPath .. "phasers3warrior.wav"
}
local DEFAULT_SoundLowHealthByClass = {
	["DRUID"] = SoundPath .. "blip5druid.wav",
	["HUNTER"] = SoundPath .. "blip5hunter.wav",
	["MAGE"] = SoundPath .. "blip5mage.wav",
	["PALADIN"] = SoundPath .. "blip5paladin.wav",
	["PRIEST"] = SoundPath .. "blip5priest.wav",
	["ROGUE"] = SoundPath .. "blip5rogue.wav",
	["WARLOCK"] = SoundPath .. "blip5warlock.wav",
	["WARRIOR"] = SoundPath .. "blip5warrior.wav"
}
local DEFAULT_SoundCritManaByClass = {
	["DRUID"] = SoundPath .. "shrinkdruid.wav",
	["HUNTER"] = SoundPath .. "shrinkhunter.wav",
	["MAGE"] = SoundPath .. "shrinkmage.wav",
	["PALADIN"] = SoundPath .. "shrinkpaladin.wav",
	["PRIEST"] = SoundPath .. "shrinkpriest.wav",
	["WARLOCK"] = SoundPath .. "shrinkwarlock.wav"
}

local DEFAULT_SoundAggroByClass = {
	["DRUID"] = SoundPath ..  "blaredruid.wav",
	["HUNTER"] = SoundPath .. "blarehunter.wav",
	["PALADIN"] = SoundPath .. "blarepaladin.wav",
	["PRIEST"] = SoundPath .. "blarepriest.wav",
	["ROGUE"] = SoundPath .. "blarerogue.wav",
	["WARLOCK"] = SoundPath .. "blarewarlock.wav",
	["WARRIOR"] = SoundPath .. "blarewarrior.wav"
}

local ClassColors = {}
for k,v in pairs(RAID_CLASS_COLORS) do
	ClassColors[k] = string.format("%2x%2x%2x", v.r*255, v.g*255, v.b*255)
end

-- Print out a message, probably to ChatFrame1
function VitalWatch:Msg(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFFFFCC00VitalWatch:|r " .. msg )
end

-- Enable a LoadOnDemand addon and optionally run one of its functions.
-- If the addon is already loaded, then just run the function or do
-- nothing.
function VitalWatch:LoDRun(addon,sfunc,arg1,arg2,arg3,arg4,arg5,arg6)
	if not self[sfunc] then
		local loaded, reason = LoadAddOn(addon)
		if loaded then
			if self[sfunc] and type( self[sfunc] ) == "function" then
				self[sfunc](self,arg1,arg2,arg3,arg4,arg5,arg6)
			end
		else
			self:Msg( addon .. " Addon LoadOnDemand Error - " .. reason )
			return reason
		end
	elseif type( self[sfunc] ) == "function" then
			self[sfunc](self,arg1,arg2,arg3,arg4,arg5,arg6)
	end
end

local MessageFrame, MessageFrameHealth_AddMessage, MessageFrameMana_AddMessage, MessageFrameAggro_AddMessage
local function CreateMessageFrame()
	if not MessageFrame then
		MessageFrame = CreateFrame("MessageFrame", "VitalWatchMessageFrame", UIParent )
		MessageFrame:SetWidth(512)
		MessageFrame:SetHeight(60)
		MessageFrame:SetPoint("CENTER", 0, 250)
		MessageFrame:SetInsertMode("TOP")
		MessageFrame:SetToplevel(true)
		MessageFrame:SetFontObject(NumberFontNormalHuge)
		MessageFrame:SetJustifyH("CENTER")
		MessageFrame:Show()
	end
end

local function StopFrameFlash(frame)
	UIFrameFlashRemoveFrame(frame)
	UIFrameFadeRemoveFrame(frame)
	if frame:IsVisible() then frame:Hide() end
end

-- Thanks to TNE_LowHealthWarning for part of this.
local function AdjustFlashRate(frame, rate)
	if rate and rate < 1 then
    if UIFrameIsFlashing(frame) then
      frame.flashDuration = frame.flashDuration + rate + 1
			if rate < 1 then
  	    frame.fadeInTime = rate * 0.15
    	  frame.fadeOutTime = rate * 0.85
      	frame.flashInHoldTime = 0
      elseif rate > 0 then
        frame.fadeInTime = 0.2
	      frame.fadeOutTime = 0.8
  	    frame.flashInHoldTime = rate - 1
			else
				StopFrameFlash(frame)
			end
		elseif rate > 0 then
				UIFrameFlash(frame, 0.2, 0.8, 10, nil, rate -1, 0)
		else
				StopFrameFlash(frame)
		end
	end
end

-- I want to get rid of this
local function PlayHeartbeatSound()
	PlaySoundFile( HeartbeatSound )
end

-- Alternative message frames. I used BigWigs as a template.
local colourtable
local function SCT4_AddMessage(frame, text, r, g, b, alpha)
		if not colourtable then colourtable = {} end
		colourtable.r, colourtable.g, colourtable.b = r, g, b
		SCT_Display_Message( text, colourtable )
end

local function SCT_AddMessage(frame, text, r, g, b, alpha)
		SCT_MSG_FRAME:AddMessage(text, r, g, b, alpha)
end

local function MikSBT_AddMessage(frame, text, r, g, b)
	MikSBT.DisplayMessage(text, MikSBT.DISPLAYTYPE_NOTIFICATION, false, r * 255, g * 255, b * 255)
end

local function BigWigs_AddMessage(frame, text, r, g, b, alpha)
	if not colourtable then colourtable = {} end
	colourtable.r, colourtable.g, colourtable.b = r,g,b
	VitalWatch:TriggerEvent("BigWigs_Message", text, colourtable, true, nil)
end

local function Blizzard_FCT_AddMessage(frame, text, r, g, b, alpha)
		CombatText_AddMessage(text, COMBAT_TEXT_SCROLL_FUNCTION, r, g, b, "sticky", nil)
end

-------------------------------------------------------------------------
-- WoW Event Processing

local playerInBG
function VitalWatch:PLAYER_ENTERING_WORLD()
	local isIn,typeOf=IsInInstance()
	playerInBG = isIn and (typeOf == "pvp")
end

function VitalWatch:ProcessUnitHealthOther(unit, name, class, petTag)
	local percentage = UnitHealth(unit) / UnitHealthMax(unit)
	if percentage < (db["ThresholdCritHealth"] or DEFAULT_ThresholdCritHealth) and 
		 (not LastPercentageHealth[unit] or 
		 LastPercentageHealth[unit] >= (db["ThresholdCritHealth"] or DEFAULT_ThresholdCritHealth)) then
				if class and ClassColors[class] then
			 		self:MessageLogUpdate("|cFF" .. ClassColors[class] .. name .. "|r" ..
										 	 				 VitalWatchLocale.Floating_Message_CritHealth,
	 										 	 			 db["ColourCritHealthOtherR"] or 1,
												 			 db["ColourCritHealthOtherG"] or 0,
												 			 db["ColourCritHealthOtherB"] or 0)
				else
			 		self:MessageLogUpdate(name .. VitalWatchLocale.Floating_Message_CritHealth .. (petTag or ""),
	 										 	 			 db["ColourCritHealthOtherR"] or 1,
												 			 db["ColourCritHealthOtherG"] or 0,
												 			 db["ColourCritHealthOtherB"] or 0)
				end
		if db["MessageFrameHealth"] ~= 5 then
					MessageFrameHealth_AddMessage(MessageFrame, 
																				MessageLog[NumMessageLog].text,
																				MessageLog[NumMessageLog].r,
																				MessageLog[NumMessageLog].g,
																				MessageLog[NumMessageLog].b,
																				MessageFrameMessageAlpha,
																				MessageFrameHoldTime)
		end

		tmp = db["SoundCritHealthByClass"]
		tmp = tmp ~= nil and tmp[(class or "pet")]
		if tmp then
			PlaySoundFile( DEFAULT_SoundCritHealthByClass[class] )
		else
			tmp = db["SoundCritHealthOther"]
			if tmp ~= "DISABLED" then
				PlaySoundFile( (tmp ~= nil and (SoundPath .. tmp .. ".wav") ) or DEFAULT_SoundCritHealth)
			end
		end

		tmp = db["MsgChanOther"]
		if not db["DisableMsg"] and tmp ~= "DISABLED" and
			(not NextQueuedMessagePriority or (NextQueuedMessagePriority < 3 and 
			 not petTag)) and db["MsgCritHealth"] and not playerInBG and 
			 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
			 (tmp == "PARTY" and GetNumPartyMembers() > 0) or 
			 (tmp == "RAID" and GetNumRaidMembers() > 0)) then
					-------
					NextQueuedMessage = "<< " ..
															name .. 
															db["MsgOtherCritHealth"] ..
															(petTag or (" (" .. UnitClass(unit) .. ") ")) ..
															" >>"
					NextQueuedMessageChan = db["MsgChanOther"]
					NextQueuedMessagePriority = (petTag and 1) or 2
					--------
		end
	elseif percentage < (db["ThresholdLowHealth"] or DEFAULT_ThresholdLowHealth) and 
		(not LastPercentageHealth[unit] or 
		LastPercentageHealth[unit] >= (db["ThresholdLowHealth"] or DEFAULT_ThresholdLowHealth)) then
				
		if class and ClassColors[class] then
			 self:MessageLogUpdate("|cFF" .. ClassColors[class] .. name .. "|r" ..
									 	 				 VitalWatchLocale.Floating_Message_LowHealth,
	 									 	 			 db["ColourLowHealthOtherR"] or 1,
											 			 db["ColourLowHealthOtherG"] or 0,
											 			 db["ColourLowHealthOtherB"] or 0)
		else
		 		self:MessageLogUpdate(name .. VitalWatchLocale.Floating_Message_LowHealth .. (petTag or ""),
 										 	 			 db["ColourLowHealthOtherR"] or 1,
														 db["ColourLowHealthOtherG"] or 0,
														 db["ColourLowHealthOtherB"] or 0)
		end
		if db["MessageFrameHealth"] ~= 5 then
					MessageFrameHealth_AddMessage(MessageFrame, 
																				MessageLog[NumMessageLog].text,
																				MessageLog[NumMessageLog].r,
																				MessageLog[NumMessageLog].g,
																				MessageLog[NumMessageLog].b,
																				MessageFrameMessageAlpha,
																				MessageFrameHoldTime)
		end

		tmp = db["SoundLowHealthByClass"]
		tmp = tmp ~= nil and tmp[(class or "pet")]
		if tmp then
			PlaySoundFile( DEFAULT_SoundLowHealthByClass[class] )
		else
			tmp = db["SoundLowHealthOther"]
			if tmp ~= "DISABLED" then
				PlaySoundFile( (tmp ~= nil and (SoundPath .. tmp .. ".wav") ) or DEFAULT_SoundLowHealth)
			end
		end

		tmp = db["MsgChanOther"]
		if not db["DisableMsg"] and tmp ~= "DISABLED" and
			(not NextQueuedMessagePriority or (NextQueuedMessagePriority < 2 and 
			 not petTag)) and db["MsgCritHealth"] and not playerInBG and 
			 db["MsgOtherLowHealth"] and not playerInBG and 
			 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
			  (tmp == "PARTY" and GetNumPartyMembers() > 0) or 
				(tmp == "RAID" and GetNumRaidMembers() > 0)) then
					-------
					NextQueuedMessage = "<< " ..
															name .. 
															db["MsgOtherLowHealth"] ..
															(petTag or (" (" .. UnitClass(unit) .. ")")) ..
															" >>"
					NextQueuedMessageChan = db["MsgChanOther"]
					NextQueuedMessagePriority = (not petTag and 1) or nil
					--------
		end
	end
	LastPercentageHealth[unit] = percentage	
end

function VitalWatch:UNIT_HEALTH(unit)
	if unit and unit ~= "target" and unit ~= "focus" and UnitAffectingCombat(unit) and 
		 UnitHealth(unit) > 0 and not UnitIsDeadOrGhost(unit) then
			if unit == "player" or UnitIsUnit(unit, "player") then
				local flashRestart
				local percentage = UnitHealth(unit) / UnitHealthMax(unit)
				if percentage < (db["ThresholdCritHealth"] or DEFAULT_ThresholdCritHealth) and 
						(not LastPercentageHealth[unit] or 
						 LastPercentageHealth[unit] >= (db["ThresholdCritHealth"] or DEFAULT_ThresholdCritHealth)) then
					if db["FlashFrameHealth"] then
						AdjustFlashRate(LowHealthFrame, (2.0 * percentage) + 0.5)
						flashRestart = true
					end
					if db["Heartbeat"] then
						self:ScheduleRepeatingEvent( "Heartbeat", 
																				 PlayHeartbeatSound, 
																				(2.0 * percentage) + 0.5 )
					end
					self:MessageLogUpdate(VitalWatchLocale.Floating_Message_Self_CritHealth,
																db["ColourCritHealthR"] or 1,
																db["ColourCritHealthG"] or 0,
																db["ColourCritHealthB"] or 0)
					if db["MessageFrameHealth"] ~= 5 then
						MessageFrameHealth_AddMessage(MessageFrame, 
																					MessageLog[NumMessageLog].text,
																					MessageLog[NumMessageLog].r,
																					MessageLog[NumMessageLog].g,
																					MessageLog[NumMessageLog].b,
																					MessageFrameMessageAlpha,
																					MessageFrameHoldTime)
					end
					local skipsound
					tmp = db["EmoteCritHealth"]
	    		if tmp and not playerInBG then
						local doEmote
						_,_,doEmote = strfind(tmp, "^/(.+)")
						if doEmote then
							_,_,NextQueuedDoEmote = doEmote
							skipsound = true
						else
							NextQueuedEmote = tmp
						end
					end
					tmp = db["SoundCritHealth"]
					if not skipsound and tmp ~= "DISABLED" then
						PlaySoundFile( (tmp ~= nil and (SoundPath .. tmp .. ".wav") ) or DEFAULT_SoundCritHealth)
					end	
					tmp = db["MsgChan"]
					if not db["DisableMsg"] and tmp ~= "DISABLED" and
					 db["MsgCritHealth"] ~= "DISABLED" and not playerInBG and 
					 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
					  ((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
						(tmp == "RAID" and GetNumRaidMembers() > 0)) then
							-------
					 		NextQueuedMessage =  "<< " ..
																	 (db["MsgCritHealth"] or VitalWatchLocale.DEFAULT_MsgCritHealth) ..
																	 " >>"
							NextQueuedMessageChan = db["MsgChan"] or "PARTY"
							NextQueuedMessagePriority = 4
							--------
					end
				elseif percentage < (db["ThresholdLowHealth"] or DEFAULT_ThresholdLowHealth) and 
						(not LastPercentageHealth[unit] or 
						 LastPercentageHealth[unit] >= (db["ThresholdLowHealth"] or DEFAULT_ThresholdLowHealth)) then
					if db["FlashFrameHealth"] then
						AdjustFlashRate(LowHealthFrame, (2.0 * percentage) + 0.5)
						flashRestart = true
					end
					if db["Heartbeat"] then
						self:ScheduleRepeatingEvent( "Heartbeat", 
																				 PlayHeartbeatSound, 
																				(2.0 * percentage) + 0.5 )
					end
					self:MessageLogUpdate(VitalWatchLocale.Floating_Message_Self_LowHealth,
																db["ColourLowHealthR"] or 1,
																db["ColourLowHealthG"] or 0,
																db["ColourLowHealthB"] or 0)
					if db["MessageFrameHealth"] ~= 5 then
						MessageFrameHealth_AddMessage(MessageFrame, 
																					MessageLog[NumMessageLog].text,
																					MessageLog[NumMessageLog].r,
																					MessageLog[NumMessageLog].g,
																					MessageLog[NumMessageLog].b,
																					MessageFrameMessageAlpha,
																					MessageFrameHoldTime)
					end
					local skipsound
					tmp = db["EmoteLowHealth"]
		    	if tmp and not playerInBG then
						local doEmote
						_,_,doEmote = strfind(tmp, "^/(.+)")
						if doEmote then
							_,_,NextQueuedDoEmote = doEmote
							skipsound = true
						else
							NextQueuedEmote = tmp
						end
					end
					tmp = db["SoundLowHealth"]
					if not skipsound and tmp ~= "DISABLED" then
						PlaySoundFile( (tmp ~= nil and (SoundPath .. tmp .. ".wav") ) or DEFAULT_SoundLowHealth)
					end	
					tmp = db["MsgChan"] 
					if not db["DisableMsg"] and tmp ~= "DISABLED" and NextQueuedPriority == nil and 
					 db["MsgLowHealth"] and not playerInBG and 
					 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
					  ((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
						(tmp == "RAID" and GetNumRaidMembers() > 0)) then
							-----
					 		NextQueuedMessage =  "<< " ..
																	 db["MsgLowHealth"] ..
																	 " >>"
							NextQueuedMessageChan = db["MsgChan"] or "PARTY"
							NextQueuedMessagePriority = 3
							-----
					end
				end
				if db["FlashFrameHealth"] and not flashRestart then
					StopFrameFlash(LowHealthFrame)
				end
				LastPercentageHealth[unit] = percentage	
			elseif UnitIsPlayer(unit) then 
				local _,c = UnitClass(unit)
				local name = (UnitName(unit)) or "Name Unknown"
				if ((db["HealthWatch"] and db["HealthWatch"] > 1 and UnitInParty(unit)) or 
						(db["HealthWatch"] == 3 and UnitInRaid(unit))) and 
					 (not db["HealthNoWatchClass"] or not db["HealthNoWatchClass"][c]) and 
					 (not db["HealthNoWatchName"] or not db["HealthNoWatchName"][name]) then
					 		-------
 							self:ProcessUnitHealthOther(unit, name, class)
							-------
				end
			elseif db["PetHealthWatch"] ~= 1 and unit == "pet" then
				self:ProcessUnitHealthOther(unit, (UnitName(unit)) or "Name Unknown", nil, VitalWatchLocale.MyPetTag)
			elseif (db["PetHealthWatch"] and db["PetHealthWatch"] > 1 and UnitPlayerOrPetInParty(unit)) or
						 (db["PetHealthWatch"] == 3 and UnitPlayerOrPetInRaid(unit)) then
				self:ProcessUnitHealthOther(unit, (UnitName(unit)) or "Name Unknown", nil, VitalWatchLocale.PetTag)
			end
		end
end

function VitalWatch:UNIT_MANA(unit)
	if unit and unit ~= "target" and unit ~= "focus" and UnitAffectingCombat(unit) and 
		 UnitMana(unit) > 0 and not UnitIsDeadOrGhost(unit) and UnitPowerType(unit) == 0 then
			if unit == "player" or UnitIsUnit(unit, "player") then
				local flashRestart
				local percentage = UnitMana(unit) / UnitManaMax(unit)
				if not percentage then return end
				if percentage < (db["ThresholdCritMana"] or DEFAULT_ThresholdCritMana) and 
					(not LastPercentageMana[unit] or 
					LastPercentageMana[unit] >= (db["ThresholdCritMana"] or DEFAULT_ThresholdCritMana)) then
					if db["FlashFrameMana"] then
						AdjustFlashRate(OutOfControlFrame, (2.0 * percentage) + 0.5)
						flashRestart = true
					end
					self:MessageLogUpdate(VitalWatchLocale.Floating_Message_Self_CritMana,
																db["ColourCritManaR"] or 1,
																db["ColourCritManaG"] or 0,
																db["ColourCritManaB"] or 0)
					if db["MessageFrameMana"] ~= 5 then
							MessageFrameMana_AddMessage(MessageFrame, 
																					MessageLog[NumMessageLog].text,
																					MessageLog[NumMessageLog].r,
																					MessageLog[NumMessageLog].g,
																					MessageLog[NumMessageLog].b,
																					MessageFrameMessageAlpha,
																					MessageFrameHoldTime)
					end
					local skipsound
					tmp = db["EmoteCritMana"]
	    		if tmp ~= "DISABLED" and not playerInBG then
						local doEmote
            _,_,doEmote = strfind(tmp or VitalWatchLocale.DEFAULT_EmoteCritMana, "^/(.+)") 
						if doEmote then
							NextQueuedDoEmote = doEmote 
							skipsound = true
						else
							NextQueuedEmote = tmp
						end
					end
					tmp = db["SoundCritMana"]
					if not skipsound and tmp then
						PlaySoundFile( SoundPath .. tmp .. ".wav" )
					end	
					tmp = db["MsgChan"]
					if not db["DisableMsg"] and tmp ~= "DISABLED" and 
					 db["MsgCritMana"] and not playerInBG and 
					 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
					  ((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
						(tmp == "RAID" and GetNumRaidMembers() > 0)) then
							-------
					 		NextQueuedMessage =  "<< " ..
																	 db["MsgCritMana"] ..
																	 " >>"
							NextQueuedMessageChan = db["MsgChan"] or "PARTY"
							NextQueuedMessagePriority = 3
							--------
					end
				elseif (percentage < (db["ThresholdLowMana"] or DEFAULT_ThresholdLowMana)) and 
						(not LastPercentageMana[unit] or 
						 LastPercentageMana[unit] >= (db["ThresholdLowMana"] or DEFAULT_ThresholdLowMana)) then
					if db["FlashFrameMana"] then
						AdjustFlashRate(OutOfControlFrame, (2.0 * percentage) + 0.5)
						flashRestart = true
					end
					self:MessageLogUpdate(VitalWatchLocale.Floating_Message_Self_LowMana,
																db["ColourLowManaR"] or 1,
																db["ColourLowManaG"] or 0,
																db["ColourLowManaB"] or 0)
					if db["MessageFrameMana"] ~= 5 then
							MessageFrameMana_AddMessage(MessageFrame, 
																					MessageLog[NumMessageLog].text,
																					MessageLog[NumMessageLog].r,
																					MessageLog[NumMessageLog].g,
																					MessageLog[NumMessageLog].b,
																					MessageFrameMessageAlpha,
																					MessageFrameHoldTime)
					end
					local skipsound
					tmp = db["EmoteLowMana"]
		    	if tmp and not playerInBG then
						local doEmote
						_,_,doEmote = strfind(tmp, "^/(.+)")
						if doEmote then
							_,_,NextQueuedDoEmote = doEmote
							skipsound = true
						else
							NextQueuedEmote = tmp
						end
					end
					tmp = db["SoundLowMana"]
					if not skipsound and tmp then
						PlaySoundFile( SoundPath .. tmp .. ".wav" )
					end	
					tmp = db["MsgChan"] 
					if not db["DisableMsg"] and tmp ~= "DISABLED" and
						(not NextQueuedMessagePriority or NextQueuedMessagePriority < 3) and
						db["MsgLowMana"] and not playerInBG and 
					 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
					  ((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
						(tmp == "RAID" and GetNumRaidMembers() > 0)) then
							-----
					 		NextQueuedMessage =  "<< " ..
																	 db["MsgLowMana"] ..
																	 " >>"
							NextQueuedMessageChan = db["MsgChan"] or "PARTY"
							NextQueuedMessagePriority = 2
							-----
					end
				end
				if db["FlashFrameMana"] and not flashRestart then
					StopFrameFlash(OutOfControlFrame)
				end
				LastPercentageMana[unit] = percentage	
			elseif UnitIsPlayer(unit) then 
				local _,c = UnitClass(unit)
				local name = (UnitName(unit)) or "Name Unknown"
				if ((db["ManaWatch"] and db["ManaWatch"] > 1 and UnitInParty(unit)) or 
						(db["ManaWatch"] == 3 and UnitInRaid(unit))) and 
					 (not db["ManaNoWatchClass"] or not db["ManaNoWatchClass"][c]) and 
					 (not db["ManaNoWatchName"] or not db["ManaNoWatchName"][name]) then
							local percentage = UnitMana(unit) / UnitManaMax(unit)
							if percentage < (db["ThresholdCritMana"] or DEFAULT_ThresholdCritMana) and 
		 					(not LastPercentageMana[unit] or 
		 					 LastPercentageMana[unit] >= (db["ThresholdCritMana"] or DEFAULT_ThresholdCritMana)) then
									if c and ClassColors[c] then
										self:MessageLogUpdate("|cFF" .. ClassColors[c] .. name .. "|r" ..
				  																VitalWatchLocale.Floating_Message_CritMana,
																					db["ColourCritManaOtherR"] or 0,
																					db["ColourCritManaOtherG"] or 0,
																					db["ColourCritManaOtherB"] or 1)
									else
										self:MessageLogUpdate(name .. VitalWatchLocale.Floating_Message_CritMana,
																					db["ColourCritManaOtherR"] or 0,
																					db["ColourCritManaOtherG"] or 0,
																					db["ColourCritManaOtherB"] or 1)
									end
									if db["MessageFrameMana"] ~= 5 then
										MessageFrameMana_AddMessage(MessageFrame, 
																								MessageLog[NumMessageLog].text,
																								MessageLog[NumMessageLog].r,
																								MessageLog[NumMessageLog].g,
																								MessageLog[NumMessageLog].b,
																								MessageFrameMessageAlpha,
																								MessageFrameHoldTime)
									end
									tmp = db["SoundCritManaByClass"]
									tmp = tmp ~= nil and tmp[class]
									if tmp then
										PlaySoundFile( DEFAULT_SoundCritHealthByClass[class] )
									else
										tmp = db["SoundCritManaOther"]
										if tmp then
											PlaySoundFile( SoundPath .. tmp .. ".wav")
										end
									end
									tmp = db["MsgChanOther"]
									if not db["DisableMsg"] and tmp ~= "DISABLED" and
									 (not NextQueuedMessagePriority or NextQueuedMessagePriority < 3) and 
									 db["MsgOtherCritMana"] and not playerInBG and 
									 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
									 ((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
									 (tmp == "RAID" and GetNumRaidMembers() > 0)) then
					 						-------
											NextQueuedMessage = "<< " ..
																					name .. 
																					db["MsgOtherCritMana"] ..
																					" (" .. UnitClass(unit) ..
																					") >>"
											NextQueuedMessageChan = db["MsgChanOther"] or "PARTY"
											NextQueuedMessagePriority = 2
											--------
									end
							elseif (percentage < (db["ThresholdLowMana"] or DEFAULT_ThresholdLowMana)) and 
								(not LastPercentageMana[unit] or 
								LastPercentageMana[unit] >= (db["ThresholdLowMana"] or DEFAULT_ThresholdLowMana)) then
										if c and ClassColors[c] then
											self:MessageLogUpdate("|cFF" .. ClassColors[c] .. name .. "|r" ..
				  																	VitalWatchLocale.Floating_Message_LowMana,
																						db["ColourLowManaOtherR"] or 0,
																						db["ColourLowManaOtherG"] or 0,
																						db["ColourLowManaOtherB"] or 1)
										else
											self:MessageLogUpdate(name .. VitalWatchLocale.Floating_Message_LowMana,
																						db["ColourLowManaOtherR"] or 0,
																						db["ColourLowManaOtherG"] or 0,
																						db["ColourLowManaOtherB"] or 1)
										end
										if db["MessageFrameMana"] ~= 5 then
											MessageFrameMana_AddMessage(MessageFrame, 
																									MessageLog[NumMessageLog].text,
																									MessageLog[NumMessageLog].r,
																									MessageLog[NumMessageLog].g,
																									MessageLog[NumMessageLog].b,
																									MessageFrameMessageAlpha,
																									MessageFrameHoldTime)
										end
										tmp = db["SoundLowManaOther"]
										if tmp then
											PlaySoundFile( SoundPath .. tmp .. ".wav" )
										end	
										tmp = db["MsgChanOther"]
										if not db["DisableMsg"] and tmp ~= "DISABLED" and NextQueuedMessagePriority == nil and 
										 db["MsgOtherLowMana"] and not playerInBG and 
										 ((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
										  ((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
											(tmp == "RAID" and GetNumRaidMembers() > 0)) then
												-------
												NextQueuedMessage = "<< " ..
																						name .. 
																						db["MsgOtherLowMana"] ..
																						" (" .. UnitClass(unit) ..
																						") >>"
												NextQueuedMessageChan = db["MsgChanOther"] or "PARTY"
												NextQueuedMessagePriority = nil
												--------
										end
							end
							LastPercentageMana[unit] = percentage	
					end -- big-ass if statement
				end
		end
end

-------------------------------------------------------------------
-- Custom Events (Banzai)


function VitalWatch:Banzai_UnitGainedAggro( unitId, unitTable )
	if unitId and unitTable and (db["AggroWatch"] ~= 1 or GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0) then
		local ru = roster:GetUnitObjectFromUnit(unitId)
		if ru then
			if unitId == "player" or UnitIsUnit(unitId, "player") then
				if db["AggroWatch"] ~= 4 and db["AggroWatch"] ~= 5 then 
					if not ru.lastAggroAlert or ((GetTime() - ru.lastAggroAlert) > (db["AggroWatchRate"] or DEFAULT_AggroWatchRate)) then

					ru.lastAggroAlert = GetTime()

					if db["FlashFrameAggro"] then 
						local rate
						if ru.banzaiModifier and ru.banzaiModifier > 0 then rate = 10 / ru.banzaiModifier else rate = 1 end
						if db["FlashFrameAggro"] == 1 then
							AdjustFlashRate( LowHealthFrame, (2.0 * rate) + 0.5)
						else
							AdjustFlashRate( OutOfControlFrame, (2.0 * rate) + 0.5)
						end
					end

					local tname,tid = UnitName(unitTable[1]) or "?", unitTable[1] or "?"
					VitalWatch:MessageLogUpdate(VitalWatchLocale.Floating_Message_Aggro .. 
																			tname ..
																			" (" ..
																			(ru.banzaiModifier or "!") ..
																			")",
																			db["ColourAggroR"] or 0.7,
																			db["ColourAggroG"] or 0.7,
																			db["ColourAggroB"] or 0.7)

					if db["MessageFrameAggro"] then
						MessageFrameAggro_AddMessage(MessageFrame, 
																				MessageLog[NumMessageLog].text,
																				MessageLog[NumMessageLog].r,
																				MessageLog[NumMessageLog].g,
																				MessageLog[NumMessageLog].b,
																				MessageFrameMessageAlpha,
																				MessageFrameHoldTime)
					end
					local skipsound
					tmp = db["EmoteAggro"]
					if tmp and not playerInBG then
						local doEmote
						_,_,doEmote = strfind(tmp, "^/(.+)")
						if doEmote then
							_,_,NextQueuedDoEmote = doEmote
							skipsound = true
						else
							NextQueuedEmote = tmp
						end
					end
					tmp = db["MsgAggroChan"] 
					if not db["DisableMsg"] and tmp ~= "DISABLED" and db["MsgAggro"] and not playerInBG and 
						(NextQueuedMessagePriority == nil or (ru.banzaiModifier and ru.banzaiModifier > 20)) and 
						((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
						((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
						(tmp == "RAID" and GetNumRaidMembers() > 0)) and not IsMounted() then
							NextQueuedMessage = "<< (" ..
																UnitClass("player") ..
																") " ..
																db["MsgAggro"] ..
																" " ..
																tname ..
																" (" ..
																(ru.banzaiModifier or "!") ..
																") >>"
							NextQueuedMessageChan = db["MsgAggroChan"] or "PARTY"
							NextQueuedMessagePriority = nil
					end
					if not skipsound and db["SoundAggro"] then
						PlaySoundFile( SoundPath .. db["SoundAggro"] .. ".wav" )
					end
				end
			end
	
			-- other players
		elseif ((db["AggroWatch"] > 4) or (db["AggroWatch"] > 2 and UnitInParty(unitId))) and 
					 (not db["AggroNoWatchClass"] or not db["AggroNoWatchClass"][ru.class]) and 
					 (not db["AggroNoWatchName"] or not db["AggroNoWatchName"][ru.name]) and 
					 (not ru.lastAggroAlert or 
					  ((GetTime() - ru.lastAggroAlert) > (db["AggroWatchOtherRate"] or DEFAULT_AggroWatchOtherRate))) then
					
					ru.lastAggroAlert = GetTime()

					local tname,tid = UnitName(unitTable[1]) or "?", unitTable[1] or "?"
					if ru.class and ClassColors[ru.class] then
						self:MessageLogUpdate("|cFF" .. ClassColors[ru.class] .. ru.name .. "|r" ..
																	" -- " ..
																	VitalWatchLocale.Floating_Message_Aggro .. 
																	tname ..
																	" (" ..
																	(ru.banzaiModifier or "!") ..
																	")",
																	db["ColourAggroOtherR"] or 0.5,
																	db["ColourAggroOtherG"] or 0.5,
																	db["ColourAggroOtherB"] or 0.5)
					else
						self:MessageLogUpdate(ru.name ..
																	" -- " ..
																	VitalWatchLocale.Floating_Message_Aggro .. 
																	tname ..
																	" (" ..
																	(ru.banzaiModifier or "!") ..
																	")",
																	db["ColourAggroOtherR"] or 0.5,
																	db["ColourAggroOtherG"] or 0.5,
																	db["ColourAggroOtherB"] or 0.5)
					end	

					if db["MessageFrameAggro"] then
						MessageFrameAggro_AddMessage(MessageFrame, 
																				MessageLog[NumMessageLog].text,
																				MessageLog[NumMessageLog].r,
																				MessageLog[NumMessageLog].g,
																				MessageLog[NumMessageLog].b,
																				MessageFrameMessageAlpha,
																				MessageFrameHoldTime)
					end
					tmp = db["MsgAggroOtherChan"] 
					if not db["DisableMsg"] and tmp ~= "DISABLED" and db["MsgAggroOther"] and not playerInBG and 
						(NextQueuedMessagePriority == nil or (ru.banzaiModifier and ru.banzaiModifier > 30)) and 
						((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
						((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
						(tmp == "RAID" and GetNumRaidMembers() > 0)) then
							NextQueuedMessage = "<< " .. 
																	ru.name ..
																	" (" ..
																	UnitClass(unitId) ..
																	" ) " ..
																	db["MsgAggroOther"] ..
																	" " ..
																	tname ..
																	" (" ..
																	(ru.banzaiModifier or "!") ..
																	") >>"
							NextQueuedMessageChan = db["MsgAggroOtherChan"] or "PARTY"
							NextQueuedMessagePriority = nil
					end
					tmp = db["SoundAggroByClass"]
					tmp = tmp ~= nil and ru.class ~= nil and tmp[ru.class]
					if tmp then
						PlaySoundFile( DEFAULT_SoundAggroByClass[class] )
					else
						tmp = db["SoundAggroOther"]
						if tmp then
							PlaySoundFile( SoundPath .. tmp .. ".wav")
						end
					end
			end
		end
	end
end

function VitalWatch:Banzai_UnitLostAggro( unitId )
		if unitId and (db["AggroLostWatch"] ~= 1 or GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0) then
			local ru = roster:GetUnitObjectFromUnit(unitId)
			if ru then
				if unitId == "player" or UnitIsUnit(unitId, "player") then 
					if db["AggroWatch"] ~= 4 and db["AggroWatch"] ~= 5 then
						if db["FlashFrameAggro"] then
							if db["FlashFrameAggro"] == 1 then
								StopFrameFlash( LowHealthFrame )
							else
								StopFrameFlash( OutOfControlFrame )
							end
						end
	
						VitalWatch:MessageLogUpdate(VitalWatchLocale.Floating_Message_Aggro .. 
																				VitalWatchLocale.Floating_Message_AggroLost ..
																				" (" ..
																				(ru.banzaiModifier or "-") ..
																				")",
																				db["ColourAggroLostR"] or 1,
																				db["ColourAggroLostG"] or 1,
																				db["ColourAggroLostB"] or 1)

						if db["MessageFrameAggro"] then
							MessageFrameAggro_AddMessage(MessageFrame, 
																					MessageLog[NumMessageLog].text,
																					MessageLog[NumMessageLog].r,
																					MessageLog[NumMessageLog].g,
																					MessageLog[NumMessageLog].b,
																					MessageFrameMessageAlpha,
																					MessageFrameHoldTime)
						end
						local skipsound
						tmp = db["EmoteAggroLost"]
						if tmp and not playerInBG then
							local doEmote
							_,_,doEmote = strfind(tmp, "^/(.+)")
							if doEmote then
								_,_,NextQueuedDoEmote = doEmote
								skipsound = true
							else
								NextQueuedEmote = tmp
							end
						end
						tmp = db["MsgAggroChan"] 
						if not db["DisableMsg"] and tmp ~= "DISABLED" and db["MsgAggroLost"] and not playerInBG and 
							NextQueuedMessagePriority == nil and 
							((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
							((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
							(tmp == "RAID" and GetNumRaidMembers() > 0)) and not IsMounted() then
								NextQueuedMessage = "<< (" ..
																		UnitClass("player") ..
																		") " ..
																		db["MsgAggroLost"] ..
																		" >> (" ..
																		(ru.banzaiModifier or "-") ..
																		")"
								NextQueuedMessageChan = db["MsgAggroChan"] or "PARTY"
								NextQueuedMessagePriority = nil
						end
						if not skipsound and db["SoundAggroLost"] then
							PlaySoundFile( SoundPath .. db["SoundAggroLost"] .. ".wav" )
						end
					end
			-- other players
		elseif ((db["AggroWatch"] > 4) or (db["AggroWatch"] > 2 and GetNumPartyMembers() > 0)) and
					 (not db["AggroNoWatchClass"] or not db["AggroNoWatchClass"][ru.class]) and 
					 (not db["AggroNoWatchName"] or not db["AggroNoWatchName"][ru.name]) then

					if ru.class and ClassColors[ru.class] then
						self:MessageLogUpdate("|cFF" .. ClassColors[ru.class] .. ru.name .. "|r" ..
																	" -- " ..
																	VitalWatchLocale.Floating_Message_Aggro .. 
																	VitalWatchLocale.Floating_Message_AggroLost ..
																	" (" ..
																	(ru.banzaiModifier or "-") ..
																	")",
																	db["ColourAggroLostOtherR"] or 1,
																	db["ColourAggroLostOtherG"] or 1,
																	db["ColourAggroLostOtherB"] or 1)
					else	
						self:MessageLogUpdate(ru.name ..
																	" -- " ..
																	VitalWatchLocale.Floating_Message_Aggro .. 
																	VitalWatchLocale.Floating_Message_AggroLost ..
																	" (" ..
																	(ru.banzaiModifier or "-") ..
																	")",
																	db["ColourAggroLostOtherR"] or 1,
																	db["ColourAggroLostOtherG"] or 1,
																	db["ColourAggroLostOtherB"] or 1)
					end	
					if db["MessageFrameAggro"] then
						MessageFrameAggro_AddMessage(MessageFrame, 
																				MessageLog[NumMessageLog].text,
																				MessageLog[NumMessageLog].r,
																				MessageLog[NumMessageLog].g,
																				MessageLog[NumMessageLog].b,
																				MessageFrameMessageAlpha,
																				MessageFrameHoldTime)
					end	
			
					tmp = db["MsgAggroOtherChan"] 
					if not db["DisableMsg"] and tmp ~= "DISABLED" and db["MsgAggroLostOther"] and not playerInBG and 
						NextQueuedMessagePriority == nil and 
						((tmp and tmp ~= "PARTY" and tmp ~= "RAID") or 
						((not tmp or tmp == "PARTY") and GetNumPartyMembers() > 0) or 
							(tmp == "RAID" and GetNumRaidMembers() > 0)) then
							NextQueuedMessage = "<< " .. 
																	ru.name ..
																	" (" ..
																	UnitClass(unitId) ..
																	" ) " ..
																	db["MsgAggroLostOther"] ..
																	" (" ..
																	(ru.banzaiModifier or "-") ..
																	") >>"
							NextQueuedMessageChan = db["MsgAggroOtherChan"] or "PARTY"
							NextQueuedMessagePriority = nil
					end
					if db["SoundAggroLostOther"] then
						PlaySoundFile( SoundPath .. db["SoundAggroLostOther"] .. ".wav" )
					end
			end
		end	
	end
end


-------------------------------------------------------------------
-- Timed Events

function VitalWatch:SendQueuedMessages()
	if NextQueuedMessage and NextQueuedMessageChan then
		SendChatMessage( NextQueuedMessage, NextQueuedMessageChan) 
		NextQueuedMessage = nil
		NextQueuedMessageChan = nil
		NextQueuedMessagePriority = nil
	end
	if NextQueuedEmote then
		SendChatMessage( NextQueuedEmote, "EMOTE" )
		NextQueuedEmote = nil
	end
	if NextQueuedDoEmote then
		DoEmote( NextQueuedDoEmote )
		NextQueuedDoEmote = nil
	end
end

function VitalWatch:StopTimers()
	NextQueuedMessage = nil
	NextQueuedEmote = nil
	NextQueuedDoEmote = nil
	NextQueuedMessageChan = nil
	NextQueuedMessagePriority = nil
	if db["FlashFrameHealth"] then StopFrameFlash(LowHealthFrame) end
	if db["FlashFrameMana"] then StopFrameFlash(OutOfControlFrame) end
	if db["FlashFrameAggro"] then
		if db["FlashFrameAggro"] == 1 then
			StopFrameFlash( LowHealthFrame )
		else
			StopFrameFlash( OutOfControlFrame )
		end
	end
	self:CancelScheduledEvent("Heartbeat")
end

function VitalWatch:FadeOldMessagesInLog()
	if NumMessageLog > 0 then
		local numRecent = 0
		local currTime = GetTime()
		local fadeTime = db["MessageLogFade"] or 15
		for i = 1,NumMessageLog do
			if currTime < MessageLog[i].time + fadeTime then
				numRecent = numRecent + 1
			end
		end
		if numRecent ~= NumMessageLog then
			local oldi
			for i = 1,numRecent do
				oldi = NumMessageLog - numRecent + i
				MessageLog[i].text = MessageLog[oldi].text
				MessageLog[i].ftext = MessageLog[oldi].ftext
				MessageLog[i].r = MessageLog[oldi].r
				MessageLog[i].g = MessageLog[oldi].g
				MessageLog[i].b = MessageLog[oldi].b
				MessageLog[i].time = MessageLog[oldi].time
			end
			NumMessageLog = numRecent
			self:UpdateText()
			self:UpdateTooltip()
		end
	end
end


-----------------------------------------------------------------------
-- Tablet / Message Log

function VitalWatch:OnTooltipUpdate()
	local cat = tablet:AddCategory("columns", 1, "showWithoutChildren", true, "hideBlankLine", false)
	if MessageLog and NumMessageLog > 0 then
		for i = 1,NumMessageLog do
			cat:AddLine('text',  MessageLog[i].ftext, 
									'textR', MessageLog[i].r,
									'textG', MessageLog[i].g,
									'textB', MessageLog[i].b,
								  'wrap', false)
		end
	end
end

function VitalWatch:OnTextUpdate()
	if NumMessageLog > 0 then
		self:SetText( "VW: " .. MessageLog[NumMessageLog].text )
	else
		self:SetText( "VitalWatch" )
	end
end

function VitalWatch:OnMenuRequest(level, value)
	self:LoDRun( "VitalWatchOptions", "CreateDDMenu", level, value)
end

function VitalWatch:MessageLogUpdate(text, r, g, b)
	local max = (db["MaxMessages"] or 6)
	if NumMessageLog == max then
		for i = max,2,-1 do
			MessageLog[i-1].text = MessageLog[i].text
			MessageLog[i-1].ftext = MessageLog[i].ftext
			MessageLog[i-1].r = MessageLog[i].r
			MessageLog[i-1].g = MessageLog[i].g
			MessageLog[i-1].b = MessageLog[i].b
			MessageLog[i-1].time = MessageLog[i].time
		end
		MessageLog[max].text = text
		MessageLog[max].r = r
		MessageLog[max].g = g
		MessageLog[max].b = b
		MessageLog[max].time = GetTime()
		MessageLog[max].ftext = "[" .. date('*t').sec .. "s] " .. text
	else
		NumMessageLog = NumMessageLog + 1
		if not MessageLog[NumMessageLog] then MessageLog[NumMessageLog] = {} end
		MessageLog[NumMessageLog].text = text
		MessageLog[NumMessageLog].r = r
		MessageLog[NumMessageLog].g = g
		MessageLog[NumMessageLog].b = b
		MessageLog[NumMessageLog].time = GetTime()
		MessageLog[NumMessageLog].ftext = "[" .. date('*t').sec .. "s] " .. text
	end
	self:UpdateTooltip()
	self:UpdateText()
end


----------------------------------------------------------------
-- Initialization

-- oRA2 additions via BanzaiAlert by vhaarr
--[[
local function InitoRA()
	oRAPAggroAlert = oRA:NewModule(VitalWatchLocale.oRAModule)
	oRAPAggroAlert.participant = true
	oRAPAggroAlert.name = VitalWatchLocale.oRAModuleName
end

function VitalWatch:ADDON_LOADED()
	if arg1 == "oRA" and oRA and not oRAPAggroAlert then
		InitoRA()
	end
end
--]]
function VitalWatch:OnInitialize()
	self:RegisterDB("VitalWatchDB", "VitalWatchCharDB")
	db = self.db.profile
end

function VitalWatch:OnDataUpdate()
	db = self.db.profile
end

function VitalWatch:OnEnable()
	LastPercentageHealth = {}
	LastPercentageMana = {}
	MessageLog = {}
	self:ReInitialize()
--[[
	if oRA and not oRAPAggroAlert then
		InitoRA()
	end
	--]]
end

function VitalWatch:ReInitialize()
	self:UnregisterAllEvents()
	self:CancelAllScheduledEvents()
	db = self.db.profile
	-- self:RegisterEvent("ADDON_LOADED")
	if db["HealthWatch"] ~= 1 then
		self:RegisterEvent("UNIT_HEALTH")
	end
	if db["ManaWatch"] ~= 1 then
		self:RegisterEvent("UNIT_MANA")
	end

	if db["FlashFrameHealth"] or db["FlashFrameMana"] or db["Heartbeat"] or db["FlashFrameAggro"] then
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "StopTimers")
		self:RegisterEvent("PLAYER_REGEN_DISABLED", "StopTimers")
	end

	if db["MessageFrameHealth"] then
		if db["MessageFrameHealth"] == 1 then -- SCT
			if SCT_Display_Message then
				MessageFrameHealth_AddMessage = SCT4_AddMessage
			elseif SCT and SCT_MSG_FRAME and SCT_MSG_FRAME.AddMessage then
				MessageFrameHealth_AddMessage = SCT_AddMessage
			end
		elseif db["MessageFrameHealth"] == 2 and MikSBT and MikSBT.DisplayMessage then -- MikSBT
			MessageFrameHealth_AddMessage = MikSBT_AddMessage
		elseif db["MessageFrameHealth"] == 3 and CombatText_AddMessage then -- Blizzard's Floating Combat Text
			MessageFrameHealth_AddMessage = Blizzard_FCT_AddMessage
		elseif db["MessageFrameHealth"] == 4 then -- BigWigs
			MessageFrameHealth_AddMessage = BigWigs_AddMessage
		end
	else
		CreateMessageFrame()
		MessageFrameHealth_AddMessage = MessageFrame.AddMessage
	end
	if db["MessageFrameMana"] then
		if db["MessageFrameMana"] == 1 then -- SCT
			if SCT_Display_Message then
				MessageFrameMana_AddMessage = SCT4_AddMessage
			elseif SCT and SCT_MSG_FRAME and SCT_MSG_FRAME.AddMessage then
				MessageFrameMana_AddMessage = SCT_AddMessage
			end
		elseif db["MessageFrameMana"] == 2 and MikSBT and MikSBT.DisplayMessage then -- MikSBT
			MessageFrameMana_AddMessage = MikSBT_AddMessage
		elseif db["MessageFrameMana"] == 3 and CombatText_AddMessage then -- Blizzard's Floating Combat Text
			MessageFrameMana_AddMessage = Blizzard_FCT_AddMessage
		elseif db["MessageFrameMana"] == 4 then -- BigWigs
			MessageFrameMana_AddMessage = BigWigs_AddMessage
		end
	else
			CreateMessageFrame()
			MessageFrameMana_AddMessage = MessageFrame.AddMessage
	end
	if db["MessageFrameAggro"] then
		if db["MessageFrameAggro"] == 1 then -- SCT
			if SCT_Display_Message then
				MessageFrameAggro_AddMessage = SCT4_AddMessage
			elseif SCT and SCT_MSG_FRAME and SCT_MSG_FRAME.AddMessage then
				MessageFrameAggro_AddMessage = SCT_AddMessage
			end
		elseif db["MessageFrameAggro"] == 2 and MikSBT and MikSBT.DisplayMessage then -- MikSBT
			MessageFrameAggro_AddMessage = MikSBT_AddMessage
		elseif db["MessageFrameAggro"] == 3 and CombatText_AddMessage then -- Blizzard's Floating Combat Text
			MessageFrameAggro_AddMessage = Blizzard_FCT_AddMessage
		elseif db["MessageFrameAggro"] == 4 then -- BigWigs
			MessageFrameAggro_AddMessage = BigWigs_AddMessage
		elseif db["MessageFrameAggro"] == 5 then
			CreateMessageFrame()
			MessageFrameAggro_AddMessage = MessageFrame.AddMessage
		end
	end

	if not db["EnableInBGs"] then
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
	end
	self:ScheduleRepeatingEvent("QueuedMessages", self.SendQueuedMessages, db["MsgRate"] or 0.2, self)
	self:ScheduleRepeatingEvent("FadeOldMessagesInLog", self.FadeOldMessagesInLog, db["MessageLogFade"] or 5, self)

	-- BanzaiLib
	if db["AggroWatch"] then
		if not roster then roster = AceLibrary("Roster-2.1") end
		self:RegisterEvent("Banzai_UnitGainedAggro")
	end
	if db["AggroLostWatch"] then
		if not roster then roster = AceLibrary("Roster-2.1") end
		self:RegisterEvent("Banzai_UnitLostAggro")
	end
end

function VitalWatch:OnDisable()
	self:UnregisterAllEvents()
	self:CancelAllScheduledEvents()
	playerInBG = nil
	LastHealthPercentage = nil
	LastManaPercentage = nil
	NumMessageLog = 0
	MessageLog = nil
	roster = nil
end
