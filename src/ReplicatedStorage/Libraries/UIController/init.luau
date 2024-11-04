local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Janitor = require(ReplicatedFirst.Packages.Janitor)
local Promise = require(ReplicatedFirst.Packages.Promise)
local UIAnimationType = require(ReplicatedStorage.Types.UIAnimation)
local UIControllerType = require(ReplicatedStorage.Types.UIController)

export type Promise<Resolve, Reject> = Promise.Promise<Resolve, Reject>
export type ChainedPromise<Resolve, Reject> = Promise.ChainedPromise<Resolve, Reject>
export type Promisified<Return> = Promise.Promisified<Return>
export type UIAnimationPreset = UIAnimationType.UIAnimationPreset
export type UIAnimation = UIAnimationType.UIAnimation
export type Janitor = Janitor.Janitor
export type UIController = UIControllerType.UIController

local CurrentScreen = {};
local Controllers = {}

local UIControllerApplication = {}
local UIAnimations: {[string]: UIAnimationPreset} = {}

for _, UIAnimation: ModuleScript in script:GetChildren() :: any do
	UIAnimations[UIAnimation.Name] = require(UIAnimation)
end

local function TweenDuration(Tween: TweenInfo): number	
	return Tween.Time + Tween.DelayTime
end

local _MockPlayAnimation: Promisified<nil> = Promise.promisify(function(): ()

end)

local PlayAnimation: Promisified<nil> = Promise.promisify(function(UIAnimation: UIAnimation): ()
	local BiggestTween: Tween;

	if UIAnimation.OnBegin then
		UIAnimation.OnBegin()
	end

	for _, Tween in UIAnimation.Tweens do
		BiggestTween = (BiggestTween and TweenDuration(Tween.TweenInfo) > TweenDuration(BiggestTween.TweenInfo) and Tween) or BiggestTween or Tween
		Tween:Play()
	end

	if UIAnimation.OnEnd then
		BiggestTween.Completed:Connect(UIAnimation.OnEnd)
	end

	if BiggestTween then
		BiggestTween.Completed:Wait()
	end
end)

function UIControllerApplication.new(Screen: Frame, ForcedState: boolean?, ScreenType: string): UIController
	Screen.Visible = ForcedState == nil and Screen.Visible or ForcedState

	local OnOpened: BindableEvent, OnClosed: BindableEvent = Instance.new("BindableEvent"), Instance.new("BindableEvent")
	local OnStartClosing: BindableEvent = Instance.new("BindableEvent")

	local NewUIController: UIController = {
		Screen = Screen;
		State = Screen.Visible;
		ScreenType = ScreenType;

		Animations = {};

		__onopened = OnOpened;
		__onclosed = OnClosed;
		__onstartclosing = OnStartClosing;

		OnOpened = OnOpened.Event;
		OnClosed = OnClosed.Event;
		OnStartClosing = OnStartClosing.Event;

		Connections = Janitor.new();
	}
	
	Controllers[Screen] = NewUIController

	return NewUIController
end

function UIControllerApplication.bulkImportAnimation(UIController: UIController, ...: string): ()
	for _, Animation: string in {...} do
		local UIAnimation: UIAnimationPreset = UIAnimations[Animation]
		if not UIAnimation then
			warn(`[UIController] UIAnimation {Animation} not found`)
			continue
		end

		UIController.Animations[UIAnimation.AnimationType] = UIAnimation.new(UIController)
	end
end

function UIControllerApplication.importAnimation(UIController: UIController, Animation: string): ()
	local UIAnimation: UIAnimationPreset = UIAnimations[Animation]
	if not UIAnimation then
		warn(`[UIController] UIAnimation {Animation} not found`)
		return 
	end

	UIController.Animations[UIAnimation.AnimationType] = UIAnimation.new(UIController)
end

function UIControllerApplication.setVisible(UIController: UIController, State: boolean): ChainedPromise<nil,nil>
	if CurrentScreen[UIController.ScreenType] and State == true then
		UIControllerApplication.close(Controllers[CurrentScreen[UIController.ScreenType]])
	end
	
	if UIController.State ~= State then
		local Animation: {Tween}? = UIController.Animations[State and "FadeIn" or "FadeOut"]
		if Animation then
			UIController.State = not UIController.State
			
			if UIController.ScreenType then
				CurrentScreen[UIController.ScreenType] = State and UIController.Screen or nil
			end
			
			if State == false then
				UIController.__onstartclosing:Fire()
			end
			
			return PlayAnimation(Animation, State):andThen(function(): ()
				(UIController :: any)[State and "__onopened" or "__onclosed"]:Fire()
			end)
		else 
			print("Animation not found!")
		end
	end

	return _MockPlayAnimation():andThen(function(): () 
		(UIController :: any).__onopened:Fire()
	end)
end

function UIControllerApplication.open(UIController: UIController): ChainedPromise<nil,nil>
	return UIControllerApplication.setVisible(UIController, true)
end

function UIControllerApplication.close(UIController: UIController): ChainedPromise<nil,nil>
	return UIControllerApplication.setVisible(UIController, false)
end

return UIControllerApplication