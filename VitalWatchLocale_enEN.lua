--[[ VitalWatch by Thrae
-- 
--
-- English Localization (Default)
-- 
-- VitalWatchLocale should be defined in your FIRST localization
-- code.
-- 
--]]

VitalWatchLocale = {}
VitalWatchLocale.locale = getglobal("GetLocale")()

if VitalWatchLocale.locale then
	VitalWatchLocale.LogTitle = "VitalWatch Log"

	VitalWatchLocale.Floating_Message_Self_LowHealth 	= "Your health is low!"
	VitalWatchLocale.Floating_Message_Self_CritHealth = "Your health is CRITICAL!"
	VitalWatchLocale.Floating_Message_Self_LowMana 		= "Your mana is low!"
	VitalWatchLocale.Floating_Message_Self_CritMana 	= "Your mana is CRITICAL!"

	VitalWatchLocale.Floating_Message_LowHealth 	= "'s health is low!"
	VitalWatchLocale.Floating_Message_CritHealth	= "'s health is CRITICAL!"
	VitalWatchLocale.Floating_Message_LowMana 		= "'s mana is low!"
	VitalWatchLocale.Floating_Message_CritMana		= "'s mana is CRITICAL!"

	VitalWatchLocale.Floating_Message_Aggro				= "AGGRO: "
	VitalWatchLocale.Floating_Message_AggroLost		= "Lost aggro."

	VitalWatchLocale.MyPetTag				= " (my pet)"
	VitalWatchLocale.PetTag					= " (pet)"

	VitalWatchLocale.DEFAULT_MsgCritHealth		= "My health is CRITICAL!"

	-- Below are voice emotes for your locale. On an English client, you
	-- would type in /oom to announce to everyone you're out of mana. To
	-- properly translate, you must find out the command for your locale.
	VitalWatchLocale.DEFAULT_EmoteCritMana		= "/oom"

	VitalWatchLocale.locale = nil -- we no longer need this
end
