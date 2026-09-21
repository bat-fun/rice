-- Programs: keep these centralized so changing an app does not require
-- hunting through keybindings.

local programs = {
    terminal    = "kitty",
    browser     = "brave",
    menu        = "rofi -show drun -theme ~/.config/rofi/config.rasi",
    code        = "code",
    fileManager = "thunar",
}

_G.noir_programs = programs

