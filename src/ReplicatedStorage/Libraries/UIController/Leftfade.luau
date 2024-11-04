local TWEEN_INFO: TweenInfo = TweenInfo.new(.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AnimationGoalTransparencyMap: {[string]: {string}} = require(ReplicatedStorage.Libraries.AnimationGoalTransparencyMap)
local UIControllerType = require(ReplicatedStorage.Types.UIController)

export type UIController = UIControllerType.UIController

local Upfade = {
	AnimationType = "FadeIn"
}

function Upfade.new(UIController: UIController): {Tween}	
	local ScreenGoal: {[string]: any} = {
		Position = UIController.Screen.Position;
	};

	for _, Goal: string in AnimationGoalTransparencyMap[UIController.Screen.ClassName] do
		ScreenGoal[Goal] = UIController.Screen[Goal]
	end

	local Tweens: {Tween} = {
		TweenService:Create(UIController.Screen, TWEEN_INFO, ScreenGoal)
	}
	
	local Objects: {{GuiObject & string}} = {};

	for _, UI: GuiObject in UIController.Screen:GetDescendants() :: any do
		local Class: string = UI.ClassName
		
		local Goals: {[string]: any} = {}

		local TransparencyMap: {string} = AnimationGoalTransparencyMap[Class]
		if not TransparencyMap then
			continue
		end

		for _, Goal: string in TransparencyMap do
			Goals[Goal] = UI[Goal]
		end

		table.insert(Objects, {UI, Class})
		table.insert(Tweens, TweenService:Create(UI, TWEEN_INFO, Goals))
	end

	return {
		OnBegin = function(): ()
			local Screen: Frame = UIController.Screen
			Screen.Visible = false

			for _, Goal: string in AnimationGoalTransparencyMap[Screen.ClassName] do
				Screen[Goal] = 1
			end

			for _, Info: {GuiObject & string} in Objects do
				local Object: GuiObject = Info[1]
				local Class: string = Info[2]
				
				for _, Goal: string in AnimationGoalTransparencyMap[Class] do
					Object[Goal] = 1
				end
			end

			Screen.Position = UDim2.fromScale(Screen.Position.X.Scale + .3, Screen.Position.Y.Scale)
			Screen.Visible = true
		end;

		Tweens = Tweens;
	}
end

return Upfade