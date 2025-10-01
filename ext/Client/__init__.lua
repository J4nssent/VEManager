---@class VEManagerClient
---@overload fun():VEManagerClient
---@diagnostic disable-next-line: assign-type-mismatch
VEManagerClient = class 'VEManagerClient'

---@type VEMLogger
local m_VEMLogger = VEMLogger("VEManagerClient", true)

--#region Imports
require "Types/VisualEnvironmentObject"
---@type VisualEnvironmentHandler
local m_VisualEnvironmentHandler = require("VisualEnvironmentHandler")
---@type RuntimeEntityHandler
local m_RuntimeEntityHandler = require("RuntimeEntityHandler")
---@type Patches
local m_Patches = require("Patches")
---@type Time
local m_Time = require("Time")
--#endregion

function VEManagerClient:__init()
	m_VEMLogger:Write('Initializing VEManagerClient')
	self:RegisterVars()
	self:RegisterEvents()
end

function VEManagerClient:RegisterVars()
	-- Table of raw JSON presets
	-- Default Dynamic day-night cycle Presets
	self._RawPresets = {
		DefaultNight = require("Presets/DefaultNight"),
		DefaultLateNight = require("Presets/DefaultLateNight"),
		DefaultMorning = require("Presets/DefaultMorning"),
		DefaultNoon = require("Presets/DefaultNoon"),
		DefaultEvening = require("Presets/DefaultEvening"),
		Vanilla = require("Presets/Vanilla"),
	}
end

function VEManagerClient:RegisterEvents()
	Events:Subscribe('Partition:Loaded', self, self._OnPartitionLoaded)
	Events:Subscribe('Level:Loaded', self, self._OnLevelLoaded)
	Events:Subscribe('Level:Destroy', self, self._OnLevelDestroy)
	Events:Subscribe('UpdateManager:Update', self, self._OnUpdateManager)

	Events:Subscribe('VEManager:RegisterPreset', self, self._RegisterPreset)
	Events:Subscribe('VEManager:EnablePreset', self, self._OnEnablePreset)
	Events:Subscribe('VEManager:DisablePreset', self, self._OnDisablePreset)
	Events:Subscribe('VEManager:SetVisibility', self, self._OnSetVisibility)
	Events:Subscribe('VEManager:SetSingleValue', self, self._OnSetSingleValue)
	Events:Subscribe('VEManager:FadeTo', self, self._OnFadeTo)
	Events:Subscribe('VEManager:FadeIn', self, self._OnFadeIn)
	Events:Subscribe('VEManager:FadeOut', self, self._OnFadeOut)
	Events:Subscribe('VEManager:Pulse', self, self._OnPulse)
	Events:Subscribe('VEManager:VEGuidRequest', self, self._OnVEGuidRequest)
	Events:Subscribe('VEManager:Reload', self, self._OnReload)
	Events:Subscribe('VEManager:ReplaceVE', self, self._OnReplaceVE)
	Events:Subscribe('VEManager:Reinitialize', self, self._OnReinitialize)
	Events:Subscribe('VEManager:ApplyTexture', self, self._OnApplyTexture)

	NetEvents:Subscribe('VEManager:EnablePreset', self, self._OnEnablePreset)
end

--#region VU Event Functions

---@param p_LevelName string
---@param p_GameModeName string
---@param p_IsDedicatedServer boolean
function VEManagerClient:_OnLevelLoaded(p_LevelName, p_GameModeName, p_IsDedicatedServer)
	LEVEL_LOADED = true
	m_Patches:OnLevelLoaded(p_LevelName, p_GameModeName, p_IsDedicatedServer)
	self:_LoadPresets()
end

function VEManagerClient:_OnLevelDestroy()
	LEVEL_LOADED = false
	self:RegisterVars()
	m_VisualEnvironmentHandler:OnLevelDestroy()
	collectgarbage('collect')
end

---@param p_Partition DatabasePartition
function VEManagerClient:_OnPartitionLoaded(p_Partition)
	m_Patches:PatchComponents(p_Partition)
end

---@param p_DeltaTime number
---@param p_UpdatePass UpdatePass
function VEManagerClient:_OnUpdateManager(p_DeltaTime, p_UpdatePass)
	if p_UpdatePass == UpdatePass.UpdatePass_PreSim then
		m_RuntimeEntityHandler:OnUpdateManagerPreSim(p_DeltaTime)
	elseif p_UpdatePass == UpdatePass.UpdatePass_PostSim then
		m_VisualEnvironmentHandler:UpdateLerp(p_DeltaTime)
	end
end

--#endregion

---@param p_ID string
---@param p_Preset string
function VEManagerClient:_RegisterPreset(p_ID, p_Preset)
	self._RawPresets[p_ID] = json.decode(p_Preset)
	m_VEMLogger:Write("Registered Preset: " .. p_ID)
end

---@param p_ID string
function VEManagerClient:_OnEnablePreset(p_ID)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	-- reset all running priority 1 lerps as EnablePreset() is a function to apply the main visual environment
	m_VisualEnvironmentHandler:ResetPriorityOneLerps()

	m_VEMLogger:Write("Enabling preset: " .. tostring(p_ID))

	local s_Initialized, s_AlreadyExists = m_VisualEnvironmentHandler:InitializeVE(p_ID, 1.0)

	if not s_Initialized and not s_AlreadyExists then
		m_VEMLogger:Error("Failed to create VE Entity from preset " .. tostring(p_ID))
	elseif not s_Initialized and s_AlreadyExists then
		m_VEMLogger:Warning("Didnt create VE Entity, since it already exists. This shouldnt happen. Making " ..
			tostring(p_ID) .. " visible nevertheless")
	end
end

---@param p_ID string
function VEManagerClient:_OnDisablePreset(p_ID)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VEMLogger:Write("Disabling preset: " .. tostring(p_ID))

	if not m_VisualEnvironmentHandler:DestroyVE(p_ID) then
		m_VEMLogger:Error("Failed to destroy VE of preset " .. tostring(p_ID))
	end
end

---@param p_ID string
function VEManagerClient:_OnSetVisibility(p_ID, p_Visibility)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VisualEnvironmentHandler:SetVisibility(p_ID, p_Visibility)
end

---@param p_ID string
---@param p_Class string
---@param p_Property string
---@param p_Value any
function VEManagerClient:_OnSetSingleValue(p_ID, p_Class, p_Property, p_Value)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VisualEnvironmentHandler:SetSingleValue(p_ID, p_Class, p_Property, p_Value)
end

---@param p_ID string
---@param p_VisibilityStart number|nil
---@param p_VisibilityEnd number
---@param p_FadeTime number time of the transition in miliseconds
---@param p_TransitionType EasingTransitions|nil
function VEManagerClient:_OnFadeTo(p_ID, p_VisibilityStart, p_VisibilityEnd, p_FadeTime, p_TransitionType)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VisualEnvironmentHandler:FadeTo(p_ID, p_VisibilityStart, p_VisibilityEnd, p_FadeTime, p_TransitionType)
end

---@param p_ID string
---@param p_FadeTime number
function VEManagerClient:_OnFadeIn(p_ID, p_FadeTime)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VisualEnvironmentHandler:FadeTo(p_ID, 0, 1, p_FadeTime)
end

---@param p_ID string
---@param p_FadeTime number
function VEManagerClient:_OnFadeOut(p_ID, p_FadeTime)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VisualEnvironmentHandler:FadeTo(p_ID, nil, 0, p_FadeTime)
end

---@param p_ID string
---@param p_PulseTime number time of the transition in miliseconds
---@param p_DecreaseFirst boolean sets if the first pulse decreases the current value until 0
---@param p_TransitionType EasingTransitions|nil
function VEManagerClient:_OnPulse(p_ID, p_PulseTime, p_DecreaseFirst, p_TransitionType)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VisualEnvironmentHandler:Pulse(p_ID, p_PulseTime, p_DecreaseFirst, p_TransitionType)
end

---@param p_ID string
function VEManagerClient:_OnVEGuidRequest(p_ID)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	local s_Guid = m_VisualEnvironmentHandler:GetEntityDataGuid(p_ID)

	if s_Guid then
		Events:Dispatch("VEManager:AnswerVEGuidRequest", s_Guid)
	end
end

---@param p_ID string
function VEManagerClient:_OnReload(p_ID)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	m_VisualEnvironmentHandler:Reload(p_ID)
end

---@param p_ID string
---@param p_Replacement string
function VEManagerClient:_OnReplaceVE(p_ID, p_Replacement)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	local s_Preset = json.decode(p_Replacement)

	if not s_Preset then
		m_VEMLogger:Warning('Error when parsing the replacement preset. Id: ' .. tostring(p_ID))
	end
	self._RawPresets[p_ID] = s_Preset
	m_VisualEnvironmentHandler:DestroyVE(p_ID)
	-- We need to trigger the recreation the the VEObject again and replace it by loading it. So we call:
	self:_LoadPresets()
	m_VisualEnvironmentHandler:InitializeVE(p_ID, 1)
end

function VEManagerClient:_OnReinitialize()
	m_VisualEnvironmentHandler:__init()
end

---@param p_ID string
---@param p_Guid Guid
---@param p_Path string
function VEManagerClient:_OnApplyTexture(p_ID, p_Guid, p_Path)
	if not m_VisualEnvironmentHandler:CheckIfExists(p_ID) then return end

	-- m_VisualEnvironmentHandler:__init()
	m_VisualEnvironmentHandler:ApplyTexture(p_ID, p_Guid, p_Path)
end

---@return table<string, string>
function VEManagerClient:GetRawPresets()
	return self._RawPresets
end

function VEManagerClient:_LoadPresets()
	m_VEMLogger:Write("Loading presets...")

	for _, l_State in ipairs(VisualEnvironmentManager:GetStates()) do
		if l_State.entityName ~= "EffectEntity" and l_State.entityName ~= "Levels/Web_Loading/Lighting/Web_Loading_VE" then
			-- SET VANILLA VE TO PRIORITY 0
			l_State.priority = 0
			l_State.visibility = 0
		end
	end

	for l_ID, l_Preset in pairs(self._RawPresets) do
		-- Create custom VE object for each preset
		local s_VEObject = VisualEnvironmentObject(l_Preset)
		m_VisualEnvironmentHandler:RegisterVisualEnvironmentObject(l_ID, s_VEObject)
		self._RawPresets[l_ID] = nil
	end

	-- Enabling Vanilla by default :)
	self._OnEnablePreset(self, 'Vanilla')
	Events:Dispatch("VEManager:PresetsLoaded")
	NetEvents:Send("VEManager:PresetsLoaded")
	NetEvents:Send("VEManager:PlayerReady")
	m_VEMLogger:Write("Presets loaded")
end

return VEManagerClient()
