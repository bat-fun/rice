-- RICE semantic theme.
-- Matugen overrides these values after a wallpaper is applied.

local theme = {
    bg        = "#090A0C",
    surface   = "#111318",
    surface2  = "#181B21",
    text      = "#E7E4DC",
    muted     = "#777B82",
    accent    = "#D6A85F",
    secondary = "#8FA6A0",
    tertiary  = "#B59B72",
    danger    = "#C46D6D",
    outline   = "#3A3D43",
    signal    = "#352A19",
    inactive  = "#3A3D43",
}

local generated_path = os.getenv("HOME") .. "/.cache/noir-signal/hyprland-colors.lua"
local ok, generated = pcall(dofile, generated_path)

if ok and type(generated) == "table" then
    for key, value in pairs(generated) do
        if type(value) == "string" and value ~= "" then
            theme[key] = value
        end
    end
end

_G.noir_theme = theme

