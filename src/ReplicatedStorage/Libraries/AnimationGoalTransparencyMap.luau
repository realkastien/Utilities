local ImageTransparency = {"ImageTransparency"}
local TextTransparency = {"TextTransparency", "BackgroundTransparency"}
local BackgroundTransparency = {"BackgroundTransparency"}
local Transparency = {"Transparency"}

return table.freeze({
    ImageLabel = ImageTransparency;
    ImageButton = ImageTransparency;

    TextLabel = TextTransparency;
    TextButton = TextTransparency;

    Frame = BackgroundTransparency;

    UIStroke = Transparency
}) :: {[string]: {string}}