# RICE

### A dark cinematic Hyprland rice.

**Quiet UI. Warm signal. Zero clutter.**

Built from scratch for Arch Linux + Hyprland.

<div align="center">

**Wallpaper-driven. Matugen-powered. Modular Lua.**

[Features](#features) · [Installation](#installation) · [Dynamic Theme](#dynamic-theme) · [Keybinds](#keybinds)

</div>

## Preview

<div align="center">

<table>
<tr>
<td width="50%">

<img src="screenshots/desktop.png" alt="Rice desktop">

</td>
<td width="50%">

<img src="screenshots/waybar.png" alt="Rice Waybar">

</td>
</tr>
<tr>
<td width="50%">

<img src="screenshots/code-oss.png" alt="Rice Code-oss">

</td>
<td width="50%">

<img src="screenshots/wallpaper-selecter.png" alt="Rice Wallpaper selector">

</td>
</tr>

<tr>
<td width="50%">

<img src="screenshots/rofi.png" alt="Rice Rofi">

</td>
<td width="50%">

<img src="screenshots/kitty.png" alt="Rice Kitty">

</td>
</tr>
</table>

</div>

---

## THE IDEA

Rice is a personal Linux desktop built around **restraint**.

Dark surfaces.
Warm amber accents.
Wallpaper-driven colors.
Minimal information.
Nothing exists just to fill space.

The configuration is modular, transparent, and meant to be changed.

## WHY RICE

The goal is not to ship the most feature-heavy Hyprland setup.

The goal is to make the pieces behave like **one desktop**.

```text
                 WALLPAPER
                     │
                     ▼
                  MATUGEN
                     │
             semantic color source
                     │
     ┌───────────────┼────────────────┐
     ▼               ▼                ▼
  Hyprland         Waybar           Kitty
     │               │                │
     └───────────────┼────────────────┘
                     ▼
              Rofi · Dunst
                     │
              Hyprlock · Wlogout
```

A wallpaper change is the starting point for the visual system, not just the background.

The repository keeps the configuration sources together, while Matugen generates the runtime color files used by the desktop components.

---

## FEATURES

|                |                                                        |
| -------------- | ------------------------------------------------------ |
| **Hyprland**   | Modular Lua configuration                              |
| **Matugen**    | Wallpaper-driven dynamic colors                        |
| **Waybar**     | Minimal system bar                                     |
| **Dunst**      | Themed desktop notifications                           |
| **Rofi**       | Application + wallpaper launchers                      |
| **Kitty**      | Terminal with matching palette                         |
| **Hyprlock**   | Minimal lock screen                                    |
| **Starship**   | Compact developer shell prompt                        |
| **Workflows**  | Clipboard, screenshots, media & system controls       |
| **Workspaces** | Workspace dashboard + scratchpad terminal              |
| **Wallpapers** | awww transitions using an independent local collection |
| **Installer**  | Automatic setup with backup, staging & validation      |

## INSTALLATION

### AUTOMATIC

**Recommended. One command.**

Copy and paste into your terminal:

```bash
git clone https://github.com/bat-fun/rice.git && cd rice && chmod +x install.sh && ./install.sh
```

The installer checks your system, installs dependencies, backs up existing configuration, installs Rice, uses wallpapers already in `~/Pictures/wallpaper`, generates the initial theme, and validates the result.

Want to preview the changes first?

```bash
./install.sh --dry-run
```

The installer does not bootstrap an AUR helper. When `brave-bin` or `wlogout` is missing, install and review `yay` separately before running the installer.

### MANUAL

For users who want complete control.

```bash
git clone https://github.com/bat-fun/rice.git
cd rice
```

Back up your existing configuration, then install the required dependencies using your preferred Arch Linux workflow.

The automatic installer does not bootstrap an AUR helper. Install and review
`yay` separately first if you want the default Brave and wlogout packages.

Copy the configuration:

```bash
cp -r hypr kitty matugen rofi waybar dunst wlogout gtk-3.0 ~/.config/
cp starship.toml ~/.config/
chmod +x ~/.config/hypr/scripts/*
```

Create the generated theme files before starting Hyprland. The automatic
installer does this for you; for a manual install, run Matugen after placing
at least one image in `~/Pictures/wallpaper`.

Create the wallpaper directory:

```bash
mkdir -p ~/Pictures/wallpaper
```

Then place your wallpapers in:

```text
~/Pictures/wallpaper
```

---

## DYNAMIC THEME

Your wallpaper becomes the color source for the entire desktop.

```text
        WALLPAPER
            │
            ▼
         MATUGEN
            │
            ▼
       COLOR PALETTE
            │
     ┌──────┼──────┐
     ▼      ▼      ▼
 Hyprland Waybar  Kitty
     │      │      │
     └──────┼──────┘
            ▼
 Dunst · Rofi · Hyprlock · Wlogout
```

Change the wallpaper.

**The desktop changes with it.**

---

## WALLPAPERS

Wallpaper files are independent from the Rice repository and are never
downloaded or managed by its installer. Use your own collection, or manage the
separate wallpaper repository independently:

```text
~/Pictures/wallpaper
```

Rice only reads supported image files from that directory at runtime.

The installer does not download wallpapers and never overwrites your collection.

---

## KEYBINDS

The default modifier is `SUPER`.

| Key                     | Action                    |
| ----------------------- | ------------------------- |
| `SUPER + Enter`         | Terminal                  |
| `SUPER + A`             | Application launcher      |
| `SUPER + B`             | Browser                   |
| `SUPER + C`             | Code - OSS                |
| `SUPER + G`             | Google search             |
| `SUPER + E`             | File manager              |
| `SUPER + Q`             | Close window              |
| `SUPER + L`             | Lock screen               |
| `SUPER + R`             | Random wallpaper          |
| `SUPER + D`             | Wallpaper picker          |
| `SUPER + V`             | Clipboard picker          |
| `SUPER + Shift + V`     | Clear clipboard            |
| `SUPER + Shift + P`     | Control panel             |
| `SUPER + Shift + H`     | System check              |
| `SUPER + TAB`            | Workspace dashboard       |
| `SUPER + S`               | Scratchpad terminal       |
| `SUPER + Shift + S`       | Send window to scratchpad |
| `SUPER + X`               | Logout menu               |
| `SUPER + Arrow Keys`      | Move focus                |
| `SUPER + 1–9`             | Workspace                 |
| `SUPER + 0`               | Workspace 10              |
| `Print`                   | Area screenshot            |
| `Shift + Print`           | Full screenshot            |

Additional controls are defined in `hypr/module/binds.lua`.

---

## CONFIGURATION

Everything is intentionally exposed.

```text
rice/
├── hypr/
│   ├── hyprland.lua
│   ├── hyprlock.conf
│   ├── module/
│   └── scripts/
├── kitty/
├── matugen/
│   ├── fallbacks/
│   └── templates/
├── rofi/
├── waybar/
├── dunst/
├── wlogout/
├── gtk-3.0/
├── starship.toml
├── install.sh
├── LICENSE
└── README.md
```

Start customizing here:

```text
hypr/module/programs.lua
hypr/module/monitors.lua
hypr/module/binds.lua
hypr/module/decoration.lua
hypr/module/animations.lua
matugen/templates/
```

---

## REQUIREMENTS

**Arch Linux + Hyprland**

The automatic installer handles the required desktop components and supporting tools, including:

`Hyprland` · `Hyprlock` · `Waybar` · `Dunst` · `Rofi` · `Kitty` · `Matugen` · `Starship` · `Thunar` · `Brave` · `Code - OSS` · `awww` · `cliphist` · `wl-clipboard` · `grim` · `slurp` · `playerctl` · `PipeWire` · `NetworkManager` · `Blueman` · `brightnessctl` · `jq` · `wlogout`

---

## VALIDATION

Before committing changes, run:

```bash
./install.sh --dry-run
bash -n install.sh
bash -n hypr/scripts/*
git diff --check
```

The repository keeps generated theme sources under `matugen/templates/` and the
checked-in runtime configuration aligned with those sources.

---

## PHILOSOPHY

Rice is not designed to be everything.

It is designed to be **enough**.

No giant widget stack.
No unnecessary effects.
No bloated framework.

Just a desktop that stays out of the way.

---

## LICENSE

MIT
