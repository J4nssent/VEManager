---@class VisualEnvironmentObject
---@field ve VisualEnvironmentEntityData
---@field entity VisualEnvironmentEntity|Entity|nil
---@field supportedClasses table<string>
---@overload fun(arg: VisualEnvironmentObject): VisualEnvironmentObject
---@diagnostic disable-next-line: assign-type-mismatch
VisualEnvironmentObject = class "VisualEnvironmentObject"

---@type VEMLogger
local m_VEMLogger = VEMLogger("VisualEnvironmentObject", true)

---@type VisualEnvironmentHandler
local m_VisualEnvironmentHandler = require("VisualEnvironmentHandler")

-- Supported types by VisualEnvironmentStates https://docs.veniceunleashed.net/vext/ref/client/type/visualenvironmentstate/
local veComponentTypes = {
	"CameraParams",
	"CharacterLighting",
	"ColorCorrection",
	"DamageEffect",
	"Dof",
	"DynamicAO",
	"DynamicEnvmap",
	"Enlighten",
	"FilmGrain",
	"Fog",
	"LensScope",
	"MotionBlur",
	"OutdoorLight",
	"PlanarReflection",
	"ScreenEffect",
	"Sky",
	"SunFlare",
	"Tonemap",
	"Vignette",
	"Wind",
	"ShaderParams"
}

---@param p_Preset table
function VisualEnvironmentObject:__init(p_Preset)
	m_VEMLogger:Write("Initializing VE Object: " .. tostring(p_Preset.Name))

	self.name = p_Preset.Name or ('unknown_preset_'
		.. tostring(m_VisualEnvironmentHandler:GetTotalVEObjectCount()))
	self.type = p_Preset.Type or 'generic'
	self.priority = tonumber(p_Preset.Priority) or (self.type == 'Dynamic' and 200 or 1)
	self.rawPreset = p_Preset

	-- spawning from blueprint alone doesn´t work somehow, would have been nice tho since we can store the name there
	local s_VE = UtilityFunctions:InitEngineType("VisualEnvironmentEntityData")
	s_VE.enabled = true
	s_VE.priority = self.priority
	s_VE.visibility = 1
	self.ve = s_VE

	self:_CreateComponents()
end

-- Create the engine types from the preset
function VisualEnvironmentObject:_CreateComponents()
	local s_Count = 0

	for _, l_Type in ipairs(veComponentTypes) do
		local s_RawValue = self.rawPreset[l_Type]
		if s_RawValue ~= nil then
			-- Value is array-like, handle each element as a component
			if s_RawValue[1] ~= nil then
				for _, l_RawElement in ipairs(s_RawValue) do
					s_Count = self:_HandleComponent(l_RawElement, l_Type, s_Count)
				end
			-- Value is object-like, handle value as component
			elseif s_RawValue ~= nil then
				s_Count = self:_HandleComponent(s_RawValue, l_Type, s_Count)
			end
		end
	end

	self.ve.runtimeComponentCount = s_Count
end

---@param p_RawComponent table
---@param p_Type string
---@param p_Count number
function VisualEnvironmentObject:_HandleComponent(p_RawComponent, p_Type, p_Count)
	local s_Component = self:_CreateComponent(p_RawComponent, p_Type, p_Count)
	if s_Component ~= nil then
		self.ve.components:add(s_Component)
		return p_Count + 1
	end

	return p_Count
end

---@param p_RawComponent table
---@param p_Type string
---@param p_Count number
function VisualEnvironmentObject:_CreateComponent(p_RawComponent, p_Type, p_Count)
	local s_Component = UtilityFunctions:InitEngineType(p_Type .. "ComponentData")
	s_Component.isEventConnectionTarget = 3
	s_Component.isPropertyConnectionTarget = 3
	s_Component.indexInBlueprint = p_Count

	-- Iterate fields of the component type
	for _, l_FieldInfo in ipairs(s_Component.typeInfo.fields) do
		local s_FieldName = l_FieldInfo.name
		if s_FieldName == "End" then
			s_FieldName = "EndValue"
		end

		local s_RawValue = p_RawComponent[s_FieldName]
		local s_ParsedValue = self:_ParseField(p_Type, l_FieldInfo, s_FieldName, s_RawValue)
		if s_ParsedValue ~= nil then
			s_Component[UtilityFunctions:FirstToLower(s_FieldName)] = s_ParsedValue
		-- else
			-- return nil here if the whole component should be ignored
		end
	end

	return s_Component
end

---@param p_ComponentType string
---@param p_FieldInfo FieldInformation
---@param p_FieldName string
---@param p_RawValue string
function VisualEnvironmentObject:_ParseField(p_ComponentType, p_FieldInfo, p_FieldName, p_RawValue)
	local s_FieldType = p_FieldInfo.typeInfo.name -- Boolean, Int32, Vec3 etc.

	-- If a value is defined in preset, parse and return
	if p_RawValue ~= nil then
		if UtilityFunctions:IsBasicType(s_FieldType) then
			return UtilityFunctions:ParseValue(s_FieldType, p_RawValue)

		elseif p_FieldInfo.typeInfo.enum then
			return tonumber(p_RawValue)

		elseif s_FieldType == "TextureAsset" then
			local s_Texture = UtilityFunctions:GetTexture(p_RawValue)
			if s_Texture ~= nil then
				return s_Texture
			else
				m_VEMLogger:Write("\t- TextureAsset not found ("
					.. p_RawValue .. " | " .. tostring(p_FieldName) .. ")")
				-- Another value will be assigned below even when no texture is defined
				-- We don't want a Sky without a defined texture to be blank sky
			end
		end

		if p_FieldInfo.typeInfo.array then
			m_VEMLogger:Write("\t- Failed to parse field. Found unexpected array")
			return nil
		else
			m_VEMLogger:Write("\t- Failed to parse field. Found unexpected type")
			return nil
		end
	end

	-- If no value was defined, return a value from the active states
	-- This prevents default values from overriding the previous state,
	-- since any defined component will fully override the previous state's component
	local s_FoundValue = self:_GetValueFromStates(p_ComponentType, p_FieldInfo)
	if s_FoundValue ~= nil then
		return s_FoundValue

	-- else
	-- 	m_VEMLogger:Write("\t- Could not find current value for " ..
	-- 		tostring(p_ComponentType) .. " | " .. tostring(p_FieldName))
	end
end


---@param p_ComponentType string
---@param p_FieldInfo FieldInformation
function VisualEnvironmentObject:_GetValueFromStates(p_ComponentType, p_FieldInfo)
	if p_FieldInfo.typeInfo.enum then
		if p_FieldInfo.typeInfo.name == "Realm" then
			return Realm.Realm_Client
		else
			m_VEMLogger:Write("\t- Found unhandled enum, " .. p_FieldInfo.typeInfo.name)
			return 0
		end
	end

	-- Return the first value of this field that is found in the active states
	local s_States = VisualEnvironmentManager:GetStates()
	for _, l_State in ipairs(s_States) do
		if l_State.entityName ~= "Levels/Web_Loading/Lighting/Web_Loading_VE"
			and l_State.entityName ~= 'EffectEntity' then
			local s_Component = l_State[UtilityFunctions:FirstToLower(p_ComponentType)]
			if s_Component ~= nil then
				return s_Component[UtilityFunctions:FirstToLower(p_FieldInfo.name)]
			end
		end
	end
end


---@class VisualEnvironmentEntity
---@field state VisualEnvironmentState


return VisualEnvironmentObject
