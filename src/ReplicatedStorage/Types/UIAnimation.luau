local UIController = require(script.Parent.UIController)

export type UIAnimationType = "FadeIn" | "FadeOut"

export type UIAnimation = {
    OnBegin: ()->()?;
    OnEnd: ()->()?;

    Tweens: {Tween};
}

export type UIAnimationPreset = {
    AnimationType: UIAnimationType;
    new: (UIController: UIController.UIController)->UIAnimation;
}

return nil