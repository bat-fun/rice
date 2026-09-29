#!/usr/bin/env bash

# Rice installer
# Opinionated daily-driver installation for Arch Linux + Hyprland.
#
# Design goals:
#   - Safe by default: backups before config replacement.
#   - Deterministic: installs the complete Rice stack.
#   - Dynamic: detects the current system and only installs what is missing.
#   - Recoverable: failed configuration installs restore the previous state.
#   - Self-contained: one script, no installer framework.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename -- "$0")"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

CONFIG_DIR="$HOME/.config"
STATE_DIR="$HOME/.local/state/noir-signal"
BACKUP_ROOT="$STATE_DIR/backups"
WALLPAPER_DIR="$HOME/Pictures/wallpaper"

DRY_RUN=0
CURRENT_PHASE="initialization"
BACKUP_DIR=""
STAGING_DIR=""
INSTALL_STARTED=0
BACKUP_CREATED=0
ROLLBACK_IN_PROGRESS=0
THEME_GENERATED=0
THEME_SKIPPED=0

# Package groups. These are the packages Rice itself expects.
# AUR packages are kept explicit because we know they are AUR targets;
# everything else is verified against the local official Arch package DB.
CORE_PACKAGES=(
    hyprland
    hyprlock
    waybar
    dunst
    rofi
    kitty
    matugen
    starship
    thunar
    code
)

RUNTIME_PACKAGES=(
    git
    jq
    awww
    cliphist
    wl-clipboard
    grim
    slurp
    playerctl
    pipewire
    pipewire-audio
    pipewire-pulse
    wireplumber
    libnotify
    networkmanager
    network-manager-applet
    blueman
    brightnessctl
    ttf-jetbrains-mono-nerd
)

AUR_PACKAGES=(
    brave-bin
    wlogout
)

# Commands that should be available after installation.
REQUIRED_COMMANDS=(
    hyprland
    hyprlock
    waybar
    rofi
    kitty
    matugen
    starship
    thunar
    code
    brave
    awww
    awww-daemon
    cliphist
    wl-copy
    wl-paste
    grim
    slurp
    playerctl
    wpctl
    notify-send
    dunst
    nm-applet
    blueman-manager
    brightnessctl
    jq
    wlogout
)

CONFIG_TARGETS=(
    hypr
    kitty
    matugen
    rofi
    waybar
    dunst
    wlogout
    gtk-3.0
    starship.toml
)

# Color is purely presentational. NO_COLOR disables it.
C_AMBER=$'\033[38;5;179m'
C_SAGE=$'\033[38;5;108m'
C_TEXT=$'\033[38;5;252m'
C_MUTED=$'\033[38;5;245m'
C_RED=$'\033[38;5;167m'
C_RESET=$'\033[0m'

if [[ -n "${NO_COLOR:-}" ]]; then
    C_AMBER=""
    C_SAGE=""
    C_TEXT=""
    C_MUTED=""
    C_RED=""
    C_RESET=""
fi

log_file=""

usage() {
    cat <<USAGE
Rice Installer

Usage:
  ./install.sh [options]

Options:
  --dry-run         Preview package/config changes without modifying the system
  -h, --help        Show this help

The normal installation installs the complete Rice daily-driver stack.
Wallpapers are independent and must already exist in ~/Pictures/wallpaper.
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf '%sError:%s unknown option: %s\n' "$C_RED" "$C_RESET" "$1" >&2
                printf 'Use --help for usage.\n' >&2
                exit 2
                ;;
        esac
        shift
    done

}

init_logging() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_file="${TMPDIR:-/tmp}/noir-signal-dry-run.log"
    else
        mkdir -p -- "$STATE_DIR"
        log_file="$STATE_DIR/install.log"
    fi

    exec > >(tee -a "$log_file") 2>&1
}

print_banner() {
    printf '\n'
    printf '%s╭──────────────────────────────────────────────────────╮%s\n' "$C_AMBER" "$C_RESET"
    printf '%s│%s                       RICE                       %s│%s\n' "$C_AMBER" "$C_TEXT" "$C_AMBER" "$C_RESET"
    printf '%s│%s              installation setup                   %s│%s\n' "$C_AMBER" "$C_MUTED" "$C_AMBER" "$C_RESET"
    printf '%s╰──────────────────────────────────────────────────────╯%s\n' "$C_AMBER" "$C_RESET"
    printf '\n'
}

info() {
    printf '%s•%s %s\n' "$C_AMBER" "$C_RESET" "$*"
}

success() {
    printf '%s✓%s %s\n' "$C_SAGE" "$C_RESET" "$*"
}

warn() {
    printf '%s!%s %s\n' "$C_AMBER" "$C_RESET" "$*" >&2
}

fail() {
    printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
}

section() {
    printf '\n%s%s%s\n' "$C_AMBER" "$*" "$C_RESET"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

join_by() {
    local delimiter="$1"
    shift
    local first=1
    local item

    for item in "$@"; do
        if [[ "$first" -eq 1 ]]; then
            printf '%s' "$item"
            first=0
        else
            printf '%s%s' "$delimiter" "$item"
        fi
    done
}

require_rootless() {
    [[ "$EUID" -ne 0 ]] || {
        fail "Do not run this installer as root. Run it as your normal user."
        exit 1
    }
}

sudo_ready() {
    sudo -v
}

run_user() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  %s+%s ' "$C_MUTED" "$C_RESET"
        printf '%q ' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

run_root() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  %s+ sudo%s ' "$C_MUTED" "$C_RESET"
        printf '%q ' "$@"
        printf '\n'
        return 0
    fi
    sudo -- "$@"
}

confirm() {
    local prompt="$1"
    local answer=""

    read -r -p "$prompt [Y/n] " answer
    [[ -z "$answer" || "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

on_error() {
    local exit_code=$?
    local line_number="${BASH_LINENO[0]:-unknown}"
    local failed_command="${BASH_COMMAND:-unknown}"

    # Ignore nested failures while we are already restoring state.
    if [[ "$ROLLBACK_IN_PROGRESS" -eq 1 ]]; then
        exit "$exit_code"
    fi

    fail "Installation failed."
    fail "Phase: $CURRENT_PHASE"
    fail "Line: $line_number"
    fail "Command: $failed_command"
    fail "Log: $log_file"

    if [[ "$DRY_RUN" -eq 0 && "$BACKUP_CREATED" -eq 1 && "$INSTALL_STARTED" -eq 1 ]]; then
        ROLLBACK_IN_PROGRESS=1
        if restore_backup; then
            success "Previous configuration restored."
        else
            fail "Automatic restore also failed. Check backup: $BACKUP_DIR"
        fi
    fi

    cleanup_temp
    exit "$exit_code"
}
trap on_error ERR

cleanup_temp() {
    if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
        rm -rf -- "$STAGING_DIR"
    fi
}
trap cleanup_temp EXIT

check_environment() {
    CURRENT_PHASE="environment checks"
    section "SYSTEM CHECK"

    require_rootless

    have_cmd bash || { fail "bash is required."; exit 1; }
    have_cmd sudo || { fail "sudo is required."; exit 1; }
    have_cmd pacman || { fail "pacman was not found. Rice targets Arch Linux."; exit 1; }

    [[ -r /etc/os-release ]] || { fail "Cannot detect the operating system."; exit 1; }
    # shellcheck disable=SC1091
    source /etc/os-release

    [[ "${ID:-}" == "arch" ]] || {
        fail "Detected ${PRETTY_NAME:-unknown}; this installer is designed for Arch Linux."
        exit 1
    }

    if [[ "$(uname -m)" != "x86_64" ]]; then
        warn "Detected architecture: $(uname -m). Package availability may differ."
    fi

    local required_repo_files=(
        "$REPO_ROOT/hypr/hyprland.lua"
        "$REPO_ROOT/hypr/hyprlock.conf"
        "$REPO_ROOT/kitty/kitty.conf"
        "$REPO_ROOT/matugen/config.toml"
        "$REPO_ROOT/rofi/config.rasi"
        "$REPO_ROOT/waybar/config.jsonc"
        "$REPO_ROOT/dunst/dunstrc"
        "$REPO_ROOT/wlogout/layout"
        "$REPO_ROOT/wlogout/style.css"
        "$REPO_ROOT/gtk-3.0/settings.ini"
        "$REPO_ROOT/hypr/scripts/workspace-dashboard"
        "$REPO_ROOT/starship.toml"
    )
    local file

    for file in "${required_repo_files[@]}"; do
        [[ -f "$file" ]] || {
            fail "Required repository file is missing: ${file#"$REPO_ROOT/"}"
            exit 1
        }
    done

    if ! sudo -n true 2>/dev/null; then
        info "sudo authentication will be required for package installation."
    fi

    success "Arch Linux detected."
    success "Rice repository structure verified."
}

system_summary() {
    CURRENT_PHASE="system summary"

    # shellcheck disable=SC1091
    source /etc/os-release

    local kernel arch shell_name session desktop cpu memory gpu hyprland_version
    kernel="$(uname -r)"
    arch="$(uname -m)"
    shell_name="$(basename -- "${SHELL:-unknown}")"
    session="${XDG_SESSION_TYPE:-unknown}"
    desktop="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-unknown}}"
    cpu="$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
    memory="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2; exit}')"
    gpu="$(lspci 2>/dev/null | awk -F': ' '/VGA compatible controller|3D controller|Display controller/ {print $2; exit}')"
    hyprland_version=""

    [[ -n "$cpu" ]] || cpu="not detected"
    [[ -n "$memory" ]] || memory="not detected"
    [[ -n "$gpu" ]] || gpu="not detected"

    if have_cmd hyprctl; then
        hyprland_version="$(hyprctl version 2>/dev/null | awk -F': ' '/^Hyprland version/ {print $2; exit}')"
    fi

    section "SYSTEM SUMMARY"
    printf '  %-16s %s\n' "OS" "${PRETTY_NAME:-Arch Linux}"
    printf '  %-16s %s\n' "Kernel" "$kernel"
    printf '  %-16s %s\n' "Architecture" "$arch"
    printf '  %-16s %s\n' "Session" "$session"
    printf '  %-16s %s\n' "Desktop" "$desktop"
    printf '  %-16s %s\n' "Shell" "$shell_name"
    printf '  %-16s %s\n' "CPU" "$cpu"
    printf '  %-16s %s\n' "Memory" "$memory"
    printf '  %-16s %s\n' "GPU" "$gpu"
    if [[ -n "$hyprland_version" ]]; then
        printf '  %-16s %s\n' "Hyprland" "$hyprland_version"
    fi
}

package_in_array() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

is_installed_package() {
    pacman -Q -- "$1" >/dev/null 2>&1
}

is_official_package() {
    pacman -Si -- "$1" >/dev/null 2>&1
}

OFFICIAL_MISSING=()
AUR_MISSING=()

resolve_packages() {
    CURRENT_PHASE="dependency audit"
    OFFICIAL_MISSING=()
    AUR_MISSING=()

    section "DEPENDENCY AUDIT"

    local package
    for package in "${CORE_PACKAGES[@]}" "${RUNTIME_PACKAGES[@]}"; do
        if is_installed_package "$package"; then
            success "$package"
            continue
        fi

        if is_official_package "$package"; then
            OFFICIAL_MISSING+=("$package")
            info "missing / official: $package"
        elif package_in_array "$package" "${AUR_PACKAGES[@]}"; then
            AUR_MISSING+=("$package")
            info "missing / AUR: $package"
        else
            fail "Package '$package' is neither installed nor available from the configured official Arch package database."
            fail "Refresh your Arch package databases and run the installer again."
            exit 1
        fi
    done

    for package in "${AUR_PACKAGES[@]}"; do
        if is_installed_package "$package"; then
            success "$package"
        else
            AUR_MISSING+=("$package")
        fi
    done

    # Remove duplicates while preserving order.
    if ((${#AUR_MISSING[@]})); then
        local -a unique_aur=()
        local seen
        for package in "${AUR_MISSING[@]}"; do
            seen=0
            if package_in_array "$package" "${unique_aur[@]}"; then
                seen=1
            fi
            [[ "$seen" -eq 0 ]] && unique_aur+=("$package")
        done
        AUR_MISSING=("${unique_aur[@]}")
    fi

    printf '\n'
    if ((${#OFFICIAL_MISSING[@]})); then
        printf '  Official packages to install: %s\n' "$(join_by ', ' "${OFFICIAL_MISSING[@]}")"
    else
        success "No missing official packages."
    fi

    if ((${#AUR_MISSING[@]})); then
        printf '  AUR packages to install:      %s\n' "$(join_by ', ' "${AUR_MISSING[@]}")"
    else
        success "No missing AUR packages."
    fi
}

show_install_plan() {
    CURRENT_PHASE="installation plan"
    section "INSTALLATION PLAN"

    printf '%sApplications%s\n' "$C_TEXT" "$C_RESET"
    printf '  Terminal       → Kitty\n'
    printf '  Browser        → Brave\n'
    printf '  Editor         → Code - OSS\n'
    printf '  File manager   → Thunar\n'
    printf '  Launcher       → Rofi\n'

    printf '\n%sCore desktop%s\n' "$C_TEXT" "$C_RESET"
    printf '  Hyprland · Hyprlock · Waybar · Rofi · Kitty · Matugen · Starship\n'

    printf '\n%sDaily-driver workflows%s\n' "$C_TEXT" "$C_RESET"
    printf '  Wallpapers · Clipboard · Screenshots · Media · Audio\n'
    printf '  Brightness · Network · Bluetooth · Logout\n'

    printf '\n%sConfiguration targets%s\n' "$C_TEXT" "$C_RESET"
    local target
    for target in "${CONFIG_TARGETS[@]}"; do
        printf '  ~/.config/%s\n' "$target"
    done

    printf '\n%sBackup%s\n' "$C_TEXT" "$C_RESET"
    printf '  Existing targets are backed up before replacement.\n'
}

create_backup() {
    CURRENT_PHASE="configuration backup"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        section "BACKUP (DRY RUN)"
        info "Existing Rice targets would be backed up before replacement."
        return 0
    fi

    section "BACKUP"
    mkdir -p -- "$BACKUP_ROOT"
    BACKUP_DIR="$BACKUP_ROOT/$(date '+%Y-%m-%d_%H-%M-%S')"

    # Handle the rare case of a timestamp collision.
    local suffix=1
    while [[ -e "$BACKUP_DIR" ]]; do
        BACKUP_DIR="$BACKUP_ROOT/$(date '+%Y-%m-%d_%H-%M-%S')-$suffix"
        suffix=$((suffix + 1))
    done

    mkdir -p -- "$BACKUP_DIR"

    local target
    local count=0

    : > "$BACKUP_DIR/manifest.txt"
    : > "$BACKUP_DIR/cache-manifest.txt"

    for target in "${CONFIG_TARGETS[@]}"; do
        if [[ -e "$CONFIG_DIR/$target" || -L "$CONFIG_DIR/$target" ]]; then
            cp -a -- "$CONFIG_DIR/$target" "$BACKUP_DIR/$target"
            printf '%s\n' "$target" >> "$BACKUP_DIR/manifest.txt"
            count=$((count + 1))
        fi
    done

    local cache_target cache_source
    for cache_target in ".cache/noir-signal" ".cache/noir-signal-wallpaper"; do
        cache_source="$HOME/$cache_target"
        if [[ -e "$cache_source" || -L "$cache_source" ]]; then
            mkdir -p -- "$BACKUP_DIR/$(dirname -- "$cache_target")"
            cp -a -- "$cache_source" "$BACKUP_DIR/$cache_target"
            printf 'present %s\n' "$cache_target" >> "$BACKUP_DIR/cache-manifest.txt"
        else
            printf 'absent %s\n' "$cache_target" >> "$BACKUP_DIR/cache-manifest.txt"
        fi
    done

    BACKUP_CREATED=1
    success "Backup created: $BACKUP_DIR"
    info "$count existing target(s) preserved."
}

prepare_stage() {
    CURRENT_PHASE="configuration staging"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        section "STAGING (DRY RUN)"
        info "Repository configuration would be staged and validated."
        return 0
    fi

    section "STAGING"
    STAGING_DIR="$(mktemp -d -t noir-signal-stage.XXXXXX)"
    mkdir -p -- "$STAGING_DIR/config"

    cp -a -- "$REPO_ROOT/hypr" "$STAGING_DIR/config/hypr"
    cp -a -- "$REPO_ROOT/kitty" "$STAGING_DIR/config/kitty"
    cp -a -- "$REPO_ROOT/matugen" "$STAGING_DIR/config/matugen"
    cp -a -- "$REPO_ROOT/rofi" "$STAGING_DIR/config/rofi"
    cp -a -- "$REPO_ROOT/waybar" "$STAGING_DIR/config/waybar"
    cp -a -- "$REPO_ROOT/dunst" "$STAGING_DIR/config/dunst"
    cp -a -- "$REPO_ROOT/wlogout" "$STAGING_DIR/config/wlogout"
    cp -a -- "$REPO_ROOT/gtk-3.0" "$STAGING_DIR/config/gtk-3.0"
    cp -a -- "$REPO_ROOT/starship.toml" "$STAGING_DIR/config/starship.toml"

    success "Configuration staged."
}

validate_stage() {
    CURRENT_PHASE="staged configuration validation"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    local required_files=(
        "$STAGING_DIR/config/hypr/hyprland.lua"
        "$STAGING_DIR/config/hypr/hyprlock.conf"
        "$STAGING_DIR/config/hypr/module/animations.lua"
        "$STAGING_DIR/config/hypr/module/binds.lua"
        "$STAGING_DIR/config/hypr/module/decoration.lua"
        "$STAGING_DIR/config/hypr/module/input.lua"
        "$STAGING_DIR/config/hypr/module/layout.lua"
        "$STAGING_DIR/config/hypr/module/monitors.lua"
        "$STAGING_DIR/config/hypr/module/programs.lua"
        "$STAGING_DIR/config/hypr/module/rules.lua"
        "$STAGING_DIR/config/hypr/module/startup.lua"
        "$STAGING_DIR/config/hypr/module/theme.lua"
        "$STAGING_DIR/config/hypr/module/workspaces.lua"
        "$STAGING_DIR/config/hypr/scripts/clipboard-picker"
        "$STAGING_DIR/config/hypr/scripts/screenshot"
        "$STAGING_DIR/config/hypr/scripts/wallpaper-picker"
        "$STAGING_DIR/config/hypr/scripts/workspace-dashboard"
        "$STAGING_DIR/config/hypr/scripts/control-panel"
        "$STAGING_DIR/config/hypr/scripts/google-search"
        "$STAGING_DIR/config/hypr/scripts/system-check"
        "$STAGING_DIR/config/kitty/kitty.conf"
        "$STAGING_DIR/config/matugen/config.toml"
        "$STAGING_DIR/config/matugen/templates/hyprland-colors.lua"
        "$STAGING_DIR/config/matugen/templates/hyprlock-colors.conf"
        "$STAGING_DIR/config/matugen/templates/kitty-colors.conf"
        "$STAGING_DIR/config/matugen/templates/dunst-colors.conf"
        "$STAGING_DIR/config/matugen/templates/noir-colors.css"
        "$STAGING_DIR/config/matugen/templates/rofi-colors.rasi"
        "$STAGING_DIR/config/matugen/templates/waybar-colors.css"
        "$STAGING_DIR/config/rofi/config.rasi"
        "$STAGING_DIR/config/rofi/control-panel.rasi"
        "$STAGING_DIR/config/rofi/noir-signal-wallpaper.rasi"
        "$STAGING_DIR/config/wlogout/layout"
        "$STAGING_DIR/config/wlogout/style.css"
        "$STAGING_DIR/config/gtk-3.0/settings.ini"
        "$STAGING_DIR/config/waybar/config.jsonc"
        "$STAGING_DIR/config/waybar/style.css"
        "$STAGING_DIR/config/dunst/dunstrc"
        "$STAGING_DIR/config/starship.toml"
    )

    local file
    for file in "${required_files[@]}"; do
        [[ -f "$file" ]] || {
            fail "Staged validation failed: missing ${file#"$STAGING_DIR/config/"}"
            exit 1
        }
    done

    success "All expected Rice files are present."
}

install_packages() {
    CURRENT_PHASE="package installation"

    section "PACKAGES"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if ((${#OFFICIAL_MISSING[@]})); then
            run_root pacman -S --needed "${OFFICIAL_MISSING[@]}"
        fi
        if ((${#AUR_MISSING[@]})); then
            info "yay must be installed separately before AUR packages can be installed."
            info "Would run: yay -S --needed --noconfirm $(join_by ' ' "${AUR_MISSING[@]}")"
        fi
        return 0
    fi

    sudo_ready

    if ((${#OFFICIAL_MISSING[@]})); then
        info "Installing missing packages from the official Arch repositories..."
        # Intentionally use -S instead of -Syu. The installer should not
        # perform an unexpected full system upgrade.
        sudo pacman -S --needed --noconfirm "${OFFICIAL_MISSING[@]}"
        success "Official packages installed."
    fi

    if ((${#AUR_MISSING[@]})); then
        install_yay
        info "Installing AUR packages..."
        yay -S --needed --noconfirm "${AUR_MISSING[@]}"
        success "AUR packages installed."
    fi
}

install_yay() {
    CURRENT_PHASE="AUR helper setup"

    have_cmd yay && return 0

    section "AUR HELPER"
    info "AUR packages are required for the Rice defaults:"
    printf '  %s\n' "$(join_by ', ' "${AUR_MISSING[@]}")"
    fail "yay is not installed. Install and review yay separately, then rerun this installer."
    return 1
}

install_configuration() {
    CURRENT_PHASE="configuration installation"
    INSTALL_STARTED=1

    section "CONFIGURATION"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        local target
        for target in "${CONFIG_TARGETS[@]}"; do
            info "Would install ~/.config/$target"
        done
        return 0
    fi

    mkdir -p -- "$CONFIG_DIR"

    local target
    for target in "${CONFIG_TARGETS[@]}"; do
        rm -rf -- "$CONFIG_DIR/$target"
        cp -a -- "$STAGING_DIR/config/$target" "$CONFIG_DIR/$target"
        success "Installed ~/.config/$target"
    done
}

set_script_permissions() {
    CURRENT_PHASE="script permissions"
    section "SCRIPTS"

    local scripts=(
        "$CONFIG_DIR/hypr/scripts/clipboard-picker"
        "$CONFIG_DIR/hypr/scripts/control-panel"
        "$CONFIG_DIR/hypr/scripts/google-search"
        "$CONFIG_DIR/hypr/scripts/screenshot"
        "$CONFIG_DIR/hypr/scripts/system-check"
        "$CONFIG_DIR/hypr/scripts/wallpaper-picker"
        "$CONFIG_DIR/hypr/scripts/workspace-dashboard"
    )
    local script

    for script in "${scripts[@]}"; do
        [[ -f "$script" ]] || {
            fail "Missing installed script: $script"
            exit 1
        }

        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "Would set executable: ${script#"$CONFIG_DIR/"}"
        else
            chmod 755 -- "$script"
            success "Executable: ${script#"$CONFIG_DIR/"}"
        fi
    done
}

wallpaper_count() {
    if [[ ! -d "$WALLPAPER_DIR" ]]; then
        printf '0\n'
        return 0
    fi

    find "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
        -iname '*.jpg' -o \
        -iname '*.jpeg' -o \
        -iname '*.png' -o \
        -iname '*.webp' \
    \) -print | wc -l
}

select_initial_wallpaper() {
    CURRENT_PHASE="initial wallpaper selection"

    local -a wallpapers=()
    mapfile -d '' wallpapers < <(
        find "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
            -iname '*.jpg' -o \
            -iname '*.jpeg' -o \
            -iname '*.png' -o \
            -iname '*.webp' \
        \) -print0 2>/dev/null
    )

    if [[ "${#wallpapers[@]}" -eq 0 ]]; then
        return 1
    fi

    NOIR_SIGNAL_SELECTED_WALLPAPER="${wallpapers[RANDOM % ${#wallpapers[@]}]}"
    export NOIR_SIGNAL_SELECTED_WALLPAPER
    return 0
}

write_runtime_wallpaper_cache() {
    local wallpaper="$1"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "Would record $wallpaper as the current Rice wallpaper."
        return 0
    fi

    mkdir -p -- "$HOME/.cache/noir-signal"
    printf '%s\n' "$wallpaper" > "$HOME/.cache/noir-signal-wallpaper"
}

ensure_theme_fallbacks() {
    local cache_dir="$HOME/.cache/noir-signal"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "Would create fallback theme files in $cache_dir."
        return 0
    fi

    mkdir -p -- "$cache_dir"

    [[ -s "$cache_dir/colors.css" ]] || cat > "$cache_dir/colors.css" <<'EOF'
:root {
    --noir-bg: #080A0F;
    --noir-surface: #10141C;
    --noir-surface-alt: #181E28;
    --noir-text: #F1F3ED;
    --noir-muted: #8992A1;
    --noir-accent: #B9D86B;
    --noir-secondary: #7CC7D9;
    --noir-tertiary: #8496D5;
    --noir-danger: #EF7180;
    --noir-outline: #303845;
}
EOF

    [[ -s "$cache_dir/hyprland-colors.lua" ]] || cat > "$cache_dir/hyprland-colors.lua" <<'EOF'
return {
    accent = "#B9D86B",
    secondary = "#7CC7D9",
    danger = "#EF7180",
    inactive = "#303845",
}
EOF

    [[ -s "$cache_dir/hyprlock-colors.conf" ]] || cat > "$cache_dir/hyprlock-colors.conf" <<'EOF'
$accent = #B9D86B
$secondary = #7CC7D9
$danger = #EF7180
$text = #F1F3ED
$muted = #8992A1
$background = #080A0F
EOF

    [[ -s "$cache_dir/kitty-colors.conf" ]] || cat > "$cache_dir/kitty-colors.conf" <<'EOF'
background #080A0F
foreground #F1F3ED
selection_background #28351E
selection_foreground #F1F3ED
cursor #B9D86B
cursor_text_color #080A0F
color0 #10141C
color1 #EF7180
color2 #7CC7D9
color3 #B9D86B
color4 #8496D5
color5 #9A879A
color6 #7FA09A
color7 #BFC0BA
color8 #4C5057
color9 #D77C7C
color10 #A7BCB5
color11 #E2BA70
color12 #91A0B0
color13 #B39AB3
color14 #94B6AF
color15 #F1F3ED
EOF

    [[ -s "$cache_dir/rofi-colors.rasi" ]] || cat > "$cache_dir/rofi-colors.rasi" <<'EOF'
* {
    noir-accent: #B9D86B;
    noir-secondary: #7CC7D9;
    noir-tertiary: #8496D5;
    noir-muted: #8992A1;
    noir-outline: #303845;
    noir-danger: #EF7180;
    noir-bg: #080A0F;
    noir-surface: #10141C;
    noir-surface-alt: #181E28;
    noir-text: #F1F3ED;
}
EOF

    [[ -s "$cache_dir/dunst-colors.conf" ]] || cat > "$cache_dir/dunst-colors.conf" <<'EOF'
[global]
    background = "#10141C"
    foreground = "#F1F3ED"
    frame_color = "#B9D86B"

[urgency_low]
    background = "#10141C"
    foreground = "#8992A1"
    frame_color = "#7CC7D9"

[urgency_normal]
    background = "#181E28"
    foreground = "#F1F3ED"
    frame_color = "#B9D86B"

[urgency_critical]
    background = "#3A2024"
    foreground = "#F4D8D8"
    frame_color = "#EF7180"
EOF

    [[ -s "$CONFIG_DIR/waybar/waybar-colors.css" ]] || cat > "$CONFIG_DIR/waybar/waybar-colors.css" <<'EOF'
@define-color noir_bg #080A0F;
@define-color noir_surface #10141C;
@define-color noir_surface_alt #181E28;
@define-color noir_text #F1F3ED;
@define-color noir_muted #8992A1;
@define-color noir_accent #B9D86B;
@define-color noir_secondary #7CC7D9;
@define-color noir_tertiary #8496D5;
@define-color noir_danger #EF7180;
@define-color noir_outline #303845;
EOF
}

bootstrap_theme() {
    CURRENT_PHASE="Matugen bootstrap"
    section "THEME BOOTSTRAP"

    local selected="${NOIR_SIGNAL_SELECTED_WALLPAPER:-}"

    if [[ -z "$selected" ]]; then
        if ! select_initial_wallpaper; then
            THEME_SKIPPED=1
            ensure_theme_fallbacks
            warn "No wallpaper is available for initial Matugen generation."
            warn "Add an image to $WALLPAPER_DIR and run the wallpaper picker after installation."
            return 0
        fi
        selected="$NOIR_SIGNAL_SELECTED_WALLPAPER"
    fi

    info "Initial wallpaper: $(basename -- "$selected")"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "Would generate the initial Matugen palette."
        return 0
    fi

    # Apply the wallpaper only when a Wayland display is available. The same
    # awww/matugen workflow is used by Rice's existing wallpaper script.
    if [[ -n "${WAYLAND_DISPLAY:-}" ]] && have_cmd awww; then
        if have_cmd awww-daemon && ! pgrep -x awww-daemon >/dev/null 2>&1; then
            awww-daemon >/dev/null 2>&1 &
            sleep 1
        fi

        if pgrep -x awww-daemon >/dev/null 2>&1; then
            awww img "$selected" \
                --transition-type fade \
                --transition-duration 1.2 \
                --transition-fps 60
            success "Initial wallpaper applied."
        else
            warn "awww-daemon could not be started; wallpaper application skipped."
        fi
    else
        info "No active Wayland session detected; wallpaper application skipped."
    fi

    matugen --mode dark --type scheme-fidelity --source-color-index 0 --quiet image "$selected"
    write_runtime_wallpaper_cache "$selected"

    local expected=(
        "$HOME/.cache/noir-signal/colors.css"
        "$HOME/.cache/noir-signal/hyprland-colors.lua"
        "$HOME/.cache/noir-signal/hyprlock-colors.conf"
        "$HOME/.cache/noir-signal/kitty-colors.conf"
        "$HOME/.cache/noir-signal/rofi-colors.rasi"
        "$CONFIG_DIR/dunst/dunstrc"
        "$CONFIG_DIR/waybar/waybar-colors.css"
        "$CONFIG_DIR/starship.toml"
        "$CONFIG_DIR/wlogout/style.css"
    )
    local file

    for file in "${expected[@]}"; do
        [[ -s "$file" ]] || {
            fail "Matugen did not generate the expected file: $file"
            return 1
        }
    done

    THEME_GENERATED=1
    success "Matugen palette generated and verified."

    # Apply live reloads only to components that are actually running.
    if pgrep -x waybar >/dev/null 2>&1; then
        killall -SIGUSR2 waybar 2>/dev/null || true
        success "Waybar theme reloaded."
    fi

    if pgrep -x dunst >/dev/null 2>&1; then
        killall -HUP dunst 2>/dev/null || true
        success "Dunst theme reloaded."
    fi

    if pgrep -x kitty >/dev/null 2>&1; then
        while read -r pid; do
            kill -SIGUSR1 "$pid" 2>/dev/null || true
        done < <(pgrep -x kitty || true)
        success "Kitty theme signalled for reload."
    fi

    if have_cmd hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        if hyprctl reload >/dev/null 2>&1; then
            success "Hyprland configuration reloaded."
        else
            warn "Hyprland reload failed; restart Hyprland to apply the configuration."
        fi
    fi
}

validate_installed_commands() {
    CURRENT_PHASE="command validation"
    section "COMMAND VALIDATION"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "Would verify all Rice commands after package installation."
        return 0
    fi

    local command missing=0
    for command in "${REQUIRED_COMMANDS[@]}"; do
        if have_cmd "$command"; then
            success "$command"
        else
            warn "Missing command after package installation: $command"
            missing=$((missing + 1))
        fi
    done

    if [[ "$missing" -gt 0 ]]; then
        fail "$missing required command(s) are missing after installation."
        return 1
    fi
}

validate_installation() {
    CURRENT_PHASE="final validation"
    section "FINAL VALIDATION"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        success "Dry-run validation complete; no changes were made."
        return 0
    fi

    local target
    for target in "${CONFIG_TARGETS[@]}"; do
        [[ -e "$CONFIG_DIR/$target" || -L "$CONFIG_DIR/$target" ]] || {
            fail "Installed target is missing: ~/.config/$target"
            return 1
        }
    done

    local scripts=(
        "$CONFIG_DIR/hypr/scripts/clipboard-picker"
        "$CONFIG_DIR/hypr/scripts/control-panel"
        "$CONFIG_DIR/hypr/scripts/google-search"
        "$CONFIG_DIR/hypr/scripts/screenshot"
        "$CONFIG_DIR/hypr/scripts/system-check"
        "$CONFIG_DIR/hypr/scripts/wallpaper-picker"
        "$CONFIG_DIR/hypr/scripts/workspace-dashboard"
    )
    local script
    for script in "${scripts[@]}"; do
        [[ -x "$script" ]] || {
            fail "Installed script is not executable: $script"
            return 1
        }
    done

    # Verify that dynamic output references are still pointing at the expected
    # runtime locations. This catches accidental path drift in public installs.
    grep -Fq '$HOME' "$CONFIG_DIR/hypr/module/decoration.lua" || true
    grep -Fq 'waybar-colors.css' "$CONFIG_DIR/waybar/style.css" || {
        fail "Waybar style is not referencing generated waybar-colors.css."
        return 1
    }

    success "Configuration targets verified."
    success "Scripts and permissions verified."
}

service_summary() {
    CURRENT_PHASE="service summary"
    section "SERVICE CHECK"

    if ! have_cmd systemctl; then
        warn "systemctl unavailable; service state could not be checked."
        return 0
    fi

    if systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
        success "NetworkManager is running."
    elif systemctl is-enabled --quiet NetworkManager.service 2>/dev/null; then
        success "NetworkManager is enabled."
    else
        warn "NetworkManager is installed but not active/enabled."
    fi

    if systemctl is-active --quiet bluetooth.service 2>/dev/null; then
        success "Bluetooth service is running."
    elif systemctl is-enabled --quiet bluetooth.service 2>/dev/null; then
        success "Bluetooth service is enabled."
    else
        warn "Bluetooth service is installed but not active/enabled."
    fi
}

restore_backup() {
    [[ "$DRY_RUN" -eq 0 ]] || return 0
    [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/manifest.txt" ]] || return 1

    local target
    for target in "${CONFIG_TARGETS[@]}"; do
        rm -rf -- "$CONFIG_DIR/$target"
    done

    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        [[ -e "$BACKUP_DIR/$target" || -L "$BACKUP_DIR/$target" ]] || continue
        mkdir -p -- "$CONFIG_DIR"
        cp -a -- "$BACKUP_DIR/$target" "$CONFIG_DIR/$target"
    done < "$BACKUP_DIR/manifest.txt"

    local cache_state cache_target
    if [[ -f "$BACKUP_DIR/cache-manifest.txt" ]]; then
        while read -r cache_state cache_target; do
            [[ -n "$cache_target" ]] || continue
            rm -rf -- "$HOME/$cache_target"
            if [[ "$cache_state" == "present" ]]; then
                mkdir -p -- "$HOME/$(dirname -- "$cache_target")"
                cp -a -- "$BACKUP_DIR/$cache_target" "$HOME/$cache_target"
            fi
        done < "$BACKUP_DIR/cache-manifest.txt"
    fi
}

show_final_summary() {
    CURRENT_PHASE="final summary"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        section "RICE DRY RUN COMPLETE"
        printf '\n%sPREVIEW%s\n' "$C_TEXT" "$C_RESET"
        printf '  ✓ Repository checks completed\n'
        printf '  ✓ Package resolution plan generated\n'
        printf '  ✓ Configuration targets reviewed\n'
        printf '  ✓ No system changes were made\n'
        printf '\n%sLog%s\n  %s\n' "$C_TEXT" "$C_RESET" "$log_file"
        return 0
    fi

    section "RICE COMPLETE"

    printf '\n%sSYSTEM%s\n' "$C_TEXT" "$C_RESET"
    printf '  ✓ Arch Linux\n'
    printf '  ✓ Rice daily-driver configuration\n'

    printf '\n%sAPPLICATIONS%s\n' "$C_TEXT" "$C_RESET"
    printf '  ✓ Kitty\n'
    printf '  ✓ Brave\n'
    printf '  ✓ Code - OSS\n'
    printf '  ✓ Thunar\n'
    printf '  ✓ Rofi\n'
    printf '  ✓ Waybar\n'

    printf '\n%sTHEMING%s\n' "$C_TEXT" "$C_RESET"
    printf '  ✓ Matugen\n'
    printf '  ✓ Dynamic color templates\n'
    if [[ "$THEME_GENERATED" -eq 1 ]]; then
        printf '  ✓ Initial palette generated\n'
    else
        printf '  ! Initial palette not generated\n'
    fi

    printf '\n%sWORKFLOWS%s\n' "$C_TEXT" "$C_RESET"
    printf '  ✓ Wallpaper picker\n'
    printf '  ✓ Clipboard picker\n'
    printf '  ✓ Screenshot workflow\n'
    printf '  ✓ Media controls\n'
    printf '  ✓ Brightness controls\n'
    printf '  ✓ Network integration\n'
    printf '  ✓ Bluetooth integration\n'
    printf '  ✓ Logout menu\n'

    printf '\n%sWALLPAPERS%s\n' "$C_TEXT" "$C_RESET"
    printf '  ✓ Uses independent local collection: %s\n' "$WALLPAPER_DIR"

    printf '\n%sBACKUP%s\n' "$C_TEXT" "$C_RESET"
    if [[ -n "$BACKUP_DIR" ]]; then
        printf '  %s\n' "$BACKUP_DIR"
    else
        printf '  Not created (dry run)\n'
    fi

    printf '\n%sLOG%s\n' "$C_TEXT" "$C_RESET"
    printf '  %s\n' "$log_file"

    printf '\n%sNEXT%s\n' "$C_TEXT" "$C_RESET"
    printf '  Review ~/.config/hypr/module/programs.lua\n'
    printf '  Review ~/.config/hypr/module/monitors.lua\n'
    printf '  Restart Hyprland if it was not reloaded automatically.\n'

    if [[ "$THEME_SKIPPED" -eq 1 ]]; then
        printf '\n%sTheme note:%s add a wallpaper to %s and run the wallpaper picker to generate the initial palette.\n' "$C_AMBER" "$C_RESET" "$WALLPAPER_DIR"
    fi
}

main() {
    parse_args "$@"
    init_logging
    print_banner

    check_environment
    system_summary
    resolve_packages
    show_install_plan

    if [[ "$DRY_RUN" -eq 1 ]]; then
        section "DRY RUN"
        warn "No packages, configuration files, wallpapers, or services will be changed."
    else
        printf '\n'
        confirm "Proceed with the Rice installation?" || {
            info "Installation cancelled."
            exit 0
        }
    fi

    install_packages
    create_backup
    prepare_stage
    validate_stage
    install_configuration
    set_script_permissions
    validate_installed_commands

    # The installer uses only the user's independent local wallpaper directory.
    if [[ "$DRY_RUN" -eq 1 ]]; then
        bootstrap_theme
    elif [[ -d "$WALLPAPER_DIR" ]] && (( $(wallpaper_count) > 0 )); then
        bootstrap_theme
    else
        THEME_SKIPPED=1
        warn "No wallpapers available; initial Matugen generation skipped."
    fi

    validate_installation

    if [[ "$DRY_RUN" -eq 0 ]]; then
        service_summary
    fi

    show_final_summary
}

main "$@"
