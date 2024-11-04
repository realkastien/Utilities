local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Janitor = require(ReplicatedFirst.Packages.Janitor)

export type UIAnimation = {
    OnBegin: ()->()?;
    OnEnd: ()->()?;

    Tweens: {Tween};
}

export type UIAnimations = {
    FadeIn: UIAnimation?;
    FadeOut: UIAnimation?;
}

export type UIController = {
	Screen: Frame;
	State: boolean;
	ScreenType: string;

	Animations: UIAnimations;
	
	OnStartClosing: RBXScriptSignal;
	OnClosed: RBXScriptSignal;
	OnOpened: RBXScriptSignal;

	Connections: Janitor.Janitor
}

return nil