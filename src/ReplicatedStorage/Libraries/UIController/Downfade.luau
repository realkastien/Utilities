local TWEEN_INFO: TweenInfo = TweenInfo.new(.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AnimationGoalTransparencyMap: {[string]: {string}} = require(ReplicatedStorage.Libraries.AnimationGoalTransparencyMap)
local UIControllerType = require(ReplicatedStorage.Types.UIController)

export type UIController = UIControllerType.UIController

local Downfade = {
	AnimationType = "FadeOut"
}

function Downfade.new(UIController: UIController): {Tween}	
	local ScreenGoal: {[string]: any} = {
		Position = UIController.Screen.Position+UDim2.fromScale(0,.3);
	};

	for _, Goal: string in AnimationGoalTransparencyMap[UIController.Screen.ClassName] do
		ScreenGoal[Goal] = 1
	end

	local Tweens: {Tween} = {
		TweenService:Create(UIController.Screen, TWEEN_INFO, ScreenGoal)
	}

	local function AddToAnimation(UI: Instance): ()
		local Class: string = UI.ClassName
			
		local Goals: {[string]: any} = {}
	
		local TransparencyMap: {string} = AnimationGoalTransparencyMap[Class]
		if not TransparencyMap then
			return
		end
	
		for _, Goal: string in TransparencyMap do
			Goals[Goal] = 1
		end
	
		table.insert(Tweens, TweenService:Create(UI, TWEEN_INFO, Goals))
	end

	for _, UI: GuiObject in UIController.Screen:GetDescendants() :: any do
		AddToAnimation(UI)
	end

	return {
		OnEnd = function(): ()
			local Screen: Frame = UIController.Screen
			Screen.Visible = false
		end;

		Tweens = Tweens;
	}
end

return Downfade