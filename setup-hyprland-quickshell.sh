#!/usr/bin/env bash
# =============================================================================
# Automated Hyprland + Quickshell workstation installer (Arch Linux)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# -------------------------------------------------------------------------
# Helper functions
# -------------------------------------------------------------------------
log() { echo -e "\e[1;34m>> $*\e[0m"; }
error() { echo -e "\e[1;31m!! $*\e[0m" >&2; }
die() {
  error "$*"
  exit 1
}

# -------------------------------------------------------------------------
# 1️⃣  Write the custom /etc/makepkg.conf (the exact file you supplied)
# -------------------------------------------------------------------------
log "Writing custom /etc/makepkg.conf"
sudo bash -c "cat > /etc/makepkg.conf <<'EOF'
#!/hint/bash
# shellcheck disable=2034

#
# /etc/makepkg.conf
#

#########################################################################
# SOURCE ACQUISITION
#########################################################################
#
DLAGENTS=('file::/usr/bin/curl -qgC - -o %o %u'
          'ftp::/usr/bin/curl -qgfC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'
          'http::/usr/bin/curl -qgb \"\" -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'https::/usr/bin/curl -qgb \"\" -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'rsync::/usr/bin/rsync --no-motd -z %u %o'
          'scp::/usr/bin/scp -C %u %o')
#-- VCS clients
VCSCLIENTS=('bzr::breezy'
            'fossil::fossil'
            'git::git'
            'hg::mercurial'
            'svn::subversion')

#########################################################################
# ARCHITECTURE, COMPILE FLAGS
#########################################################################
CARCH="x86_64"
CHOST="x86_64-pc-linux-gnu"
PACKAGECARCH="x86_64"
CFLAGS="-march=native -O3 -pipe -fno-plt -fexceptions \
  -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security \
  -fstack-clash-protection -fcf-protection"
CXXFLAGS="\$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,-z,relro -Wl,-z,now"
MAKEFLAGS="-j\$\(nproc\)"
NINJAFLAGS="-j\$\(nproc\)"
DEBUG_CFLAGS="-g"
DEBUG_CXXFLAGS="\$DEBUG_CFLAGS"

# BUILD ENVIRONMENT
BUILDENV=(!distcc color !ccache check !sign)

# GLOBAL PACKAGE OPTIONS
OPTIONS=(strip !libtool !staticlibs emptydirs zipman purge !debug lto !autodeps)

# GLOBAL FLAGS
INTEGRITY_CHECK=(sha256)
STRIP_BINARIES="--strip-all"
STRIP_SHARED="--strip-unneeded"

# PKG EXTENSIONS
PKGEXT=".pkg.tar.zst"
SRCEXT=".src.tar.gz"
# vim: set ft=sh ts=2 sw=2 et:
EOF"
log "/etc/makepkg.conf written"

# -------------------------------------------------------------------------
# 2️⃣  Install build prerequisites (git + base-devel)
# -------------------------------------------------------------------------
log "Ensuring git and base-devel are installed"
sudo pacman -Sy --needed --noconfirm git base-devel

# -------------------------------------------------------------------------
# 3️⃣  Install the AUR helper *paru* (manual git + makepkg)
# -------------------------------------------------------------------------
if ! command -v paru &>/dev/null; then
  log "Installing paru (AUR helper) from the AUR"
  TMPDIR=$(mktemp -d)
  git clone https://aur.archlinux.org/paru.git "$TMPDIR/paru"
  (cd "$TMPDIR/paru" && makepkg -si --noconfirm)
  rm -rf "$TMPDIR"
  log "paru installed"
else
  log "paru already installed"
fi

# -------------------------------------------------------------------------
# 4️⃣  Install official repository packages (one per line, no comments)
# -------------------------------------------------------------------------
OFFICIAL_PKGS=(
  hyprland
  hyprpaper
  hypridle
  hyprlock
  gtk4-layer-shell
  kvantum
  kvantum-qt5
  adw-gtk-theme
  kitty
  neovim
  pipewire
  pipewire-pulse
  wireplumber
  blueberry
  grim
  slurp
  xdg-desktop-portal-hyprland
  xdg-utils
  jq
  btop
  chromium
)

log "Installing official repository packages"
sudo pacman -S --needed --noconfirm "${OFFICIAL_PKGS[@]}"

# -------------------------------------------------------------------------
# 5️⃣  Install AUR packages (one per line, no comments)
# -------------------------------------------------------------------------
AUR_PKGS=(
  quickshell
  nerd-fonts-sf-mono
  matugen-bin
  vimix-icon-theme-git
)

log "Installing AUR packages via paru"
paru -S --needed --noconfirm "${AUR_PKGS[@]}"

# -------------------------------------------------------------------------
# 6️⃣  Disable NetworkManager, enable systemd‑networkd (part of systemd)
# -------------------------------------------------------------------------
log "Disabling NetworkManager (if present)"
sudo systemctl stop NetworkManager.service 2>/dev/null || true
sudo systemctl disable NetworkManager.service 2>/dev/null || true
sudo systemctl mask NetworkManager.service 2>/dev/null || true
systemctl --user mask NetworkManager.service 2>/dev/null || true

log "Enabling systemd‑networkd"
sudo systemctl enable --now systemd-networkd.service
sudo systemctl enable --now systemd-networkd-wait-online.service

# -------------------------------------------------------------------------
# 7️⃣  Create $HOME/.config hierarchy
# -------------------------------------------------------------------------
BASE="$HOME/.config"
log "Creating configuration directories under $BASE"
mkdir -p "$BASE/hypr"
mkdir -p "$BASE/quickshell"
mkdir -p "$BASE/scripts"
mkdir -p "$BASE/systemd/user"
mkdir -p "$BASE/ai"

# -------------------------------------------------------------------------
# Helper to write files safely (writes raw text, sets mode 644)
# -------------------------------------------------------------------------
FORCE_OVERWRITE=0
while (("$#")); do
  case "$1" in
  --force)
    FORCE_OVERWRITE=1
    shift
    ;;
  -h | --help)
    cat <<EOF
Usage: $0 [--force]

  --force   Overwrite existing files
EOF
    exit 0
    ;;
  *) break ;;
  esac
done

write_file() {
  local dst=$1
  shift
  if [[ -e "$dst" && $FORCE_OVERWRITE -eq 0 ]]; then
    log "Skipping $dst (use --force to overwrite)"
    return
  fi
  install -d "$(dirname "$dst")"
  # $* contains the full heredoc, so we use a temporary heredoc
  cat "$@" | install -Dm644 /dev/stdin "$dst"
  log "Wrote $dst"
}

# -------------------------------------------------------------------------
# 8️⃣  Hyprland configuration (exact copy, plain‑text labels, no Unicode)
# -------------------------------------------------------------------------
write_file "$BASE/hypr/hyprland.conf" - <<'EOF'
# General appearance – flat, fast, no rounded corners
general {
    border_size = 2
    col.active_border   = rgba(0,0,0,0.90)
    col.inactive_border = rgba(120,120,120,0.45)
    gaps_in = 5
    gaps_out = 5
    layout = dwindle
    resize_on_border = true
}

# Animation – snappy 150 ms
animation {
    enabled = true
    duration = 150
    curve = easeOutExpo
}
decoration {
    blur = 0
    rounding = 0
}

# INPUT – disable mouse acceleration (native Hyprland)
input {
    kb_layout = us
    repeat_rate = 25
    repeat_delay = 250
    mouse {
        accel_profile = flat
        acceleration = 0
        natural_scroll = true
    }
}

# Exec‑once (system daemons)
exec-once = dbus-launch --exit-with-session hyprpaper
exec-once = dbus-launch --exit-with-session hypridle
exec-once = dbus-launch --exit-with-session hyprlock
exec-once = dbus-launch --exit-with-session blueberry-tray

# Monitors (2 × 1440p @ 165 Hz)
monitor = DP-1,2560x1440@165,0x0,1
monitor = DP-2,2560x1440@165,2560x0,1

# Workspaces (numeric, used by the panel)
workspace = 1, name:1
workspace = 2, name:2
workspace = 3, name:3
workspace = 4, name:4
workspace = 5, name:5
workspace = 6, name:6
workspace = 7, name:7
workspace = 8, name:8
workspace = 9, name:9
workspace = 10, name:10

# Keybindings (Super = $mod)
$mod = SUPER

# Core apps
bind = $mod, RETURN, exec, kitty
bind = $mod, C, exec, chromium
bind = $mod, M, exec, btop
bind = $mod, B, exec, blueberry
bind = $mod, L, exec, $HOME/.config/scripts/lock.sh
bind = $mod, G, exec, $HOME/.config/scripts/gamemode.sh

# Workspace switching
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod, 6, workspace, 6
bind = $mod, 7, workspace, 7
bind = $mod, 8, workspace, 8
bind = $mod, 9, workspace, 9
bind = $mod, 0, workspace, 10

# Move window to workspace (example for 1)
bind = $mod+SHIFT, 1, movetoworkspace, 1

# Screenshots
bind = $mod, PRINT, exec, $HOME/.config/scripts/screenshot.sh full
bind = $mod+SHIFT, PRINT, exec, $HOME/.scripts/screenshot.sh area
bind = $mod+CTRL, PRINT, exec, $HOME/.scripts/screenshot.sh window
bind = $mod+ALT, PRINT, exec, $HOME/.scripts/screenshot.sh monitor

# Wallpaper navigation
bind = $mod, RIGHT, exec, $HOME/.scripts/wallpaper_next.sh
bind = $mod, LEFT, exec, $HOME/.scripts/wallpaper_prev.sh
bind = $mod, UP, exec, $HOME/.scripts/wallpaper_random.sh

# Quickshell UI toggles
bind = $mod, SPACE, exec, $HOME/.scripts/show-launcher.sh
bind = $mod, W, exec, $HOME/.scripts/show-wallpaper-selector.sh
bind = $mod, I, exec, $HOME/.scripts/show-ai-sidebar.sh

# Reload Quickshell UI (SIGUSR1)
bind = $mod, R, exec, kill -SIGUSR1 quickshell

# OSDs for hardware keys
bind = , XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5% && $HOME/.config/scripts/osd_notify.sh "Volume" "Volume up 5 %" "audio-volume-high"
bind = , XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5% && $HOME/.config/scripts/osd_notify.sh "Volume" "Volume down 5 %" "audio-volume-low"
bind = , XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle && $HOME/.config/scripts/osd_notify.sh "Volume" "Mute toggled" "audio-volume-muted"
bind = , XF86MonBrightnessUp, exec, brightnessctl set +5% && $HOME/.config/scripts/osd_notify.sh "Brightness" "Brightness up 5 %" "display-brightness-high"
bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%- && $HOME/.config/scripts/osd_notify.sh "Brightness" "Brightness down 5 %" "display-brightness-low"

# Logout / lock (fallback)
bind = $mod+SHIFT, ESCAPE, exec, $HOME/.config/scripts/lock.sh

# Idle handling (hypridle)
exec-once = hypridle
EOF

# -------------------------------------------------------------------------
# hyprpaper.conf (simple preload)
# -------------------------------------------------------------------------
write_file "$BASE/hypr/hyprpaper.conf" - <<'EOF'
preload = $HOME/Pictures/wallpaper/*
wallpaper = DP-1, $HOME/Pictures/wallpaper/default.jpg
wallpaper = DP-2, $HOME/Pictures/wallpaper/default.jpg
EOF

# -------------------------------------------------------------------------
# hypridle.conf (idle → lock after 5 min, suspend after 15 min)
# -------------------------------------------------------------------------
write_file "$BASE/hypr/hypridle.conf" - <<'EOF'
default_timeout = 300
default_lock = $HOME/.config/scripts/lock.sh

timeout 900 {
    exec = systemctl suspend
}
EOF

# -------------------------------------------------------------------------
# hyprlock.conf (simple lock‑screen)
# -------------------------------------------------------------------------
write_file "$BASE/hypr/hyprlock.conf" - <<'EOF'
background {
    path = $HOME/.config/hyprlock.jpg
    blur_passes = 0
}
input-field {
    size = 250 40
    position = 0 0
    outline_thickness = 0
    font_family = "SFMono Nerd Font Mono"
    font_size = 18
    placeholder_text = "Enter password..."
    background_color = rgba(0,0,0,0.6)
    text_color = rgba(255,255,255,0.9)
}
EOF

# -------------------------------------------------------------------------
# Quickshell QML files (panel, launcher, wallpaper selector, AI sidebar)
# -------------------------------------------------------------------------

# panel.qml – plain‑text labels (no Unicode icons)
write_file "$BASE/quickshell/panel.qml" - <<'EOF'
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0
import "palette.json" as Palette
import Qt.labs.platform 1.1

Item {
    width: Screen.width
    height: 32
    visible: true

    LayerSurface {
        anchors.fill: parent
        layer: LayerSurface.Top
        exclusiveZone: height
        keyboardInteractivity: LayerSurface.ExclusiveKeyboard
        anchor: Qt.TopEdge
    }

    Rectangle { anchors.fill: parent; color: Palette.base; opacity: 0.85 }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 12

        // Workspace numbers (plain text)
        Text {
            text: {
                var p = new Process()
                p.start("sh", ["-c", "hyprctl workspaces -j | jq -r '.[] .name' | paste -sd ' ' -"])
                p.waitForFinished()
                return p.readAllStandardOutput().trim()
            }
            color: Palette.onBase
            font.family: "SFMono Nerd Font Mono"
            font.pixelSize: 13
        }

        // Network (wired + wifi) – plain text
        Item {
            width: 120
            RowLayout { anchors.fill: parent; spacing: 4 }

            Text {
                text: "Wired"
                color: netState ? Palette.onBase : "grey"
                font.family: "SFMono Nerd Font Mono"
                MouseArea {
                    anchors.fill: parent
                    onClicked: Qt.openUrlExternally("foot -e bash -c \"nmcli device wifi list; read\"")
                }
            }

            Text {
                id: wifi
                text: netInfo
                color: wifiOn ? Palette.onBase : "grey"
                font.family: "SFMono Nerd Font Mono"
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var cmd = wifiOn ? "nmcli radio wifi off" : "nmcli radio wifi on"
                        var p = new Process()
                        p.start("sh", ["-c", cmd])
                        p.waitForFinished()
                    }
                }
            }

            property bool wifiOn: false
            property bool netState: false
            property string netInfo: ""

            Component.onCompleted: {
                updateTimer.start()
                update()
            }
            Timer {
                id: updateTimer; interval: 5000; running: true; repeat: true
                onTriggered: update()
            }
            function update() {
                var p = new Process()
                p.start("sh", ["-c", "ip link show up | grep -E 'state UP' | wc -l"])
                p.waitForFinished()
                netState = parseInt(p.readAllStandardOutput().trim()) > 0
                var w = new Process()
                w.start("sh", ["-c", "iwgetid -r || echo ''"])
                w.waitForFinished()
                netInfo = w.readAllStandardOutput().trim()
                wifiOn = netInfo !== ""
            }
        }

        // Volume
        Item {
            width: 80
            RowLayout { anchors.fill: parent; spacing: 4 }

            Text {
                id: volLabel
                text: mute ? "Muted" : "Volume"
                color: Palette.onBase
                font.family: "SFMono Nerd Font Mono"
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var p = new Process()
                        p.start("sh", ["-c", "pactl set-sink-mute @DEFAULT_SINK@ toggle"])
                        p.waitForFinished()
                        mute = !mute
                        Qt.openUrlExternally("notify-send \"Volume\" " + (mute ? "Muted" : "Unmuted"))
                    }
                }
            }

            Text {
                id: volPct
                text: pct + "%"
                color: Palette.onBase
                font.family: "SFMono Nerd Font Mono"
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: {
                        var delta = wheel.angleDelta.y > 0 ? "+5%" : "-5%"
                        var p = new Process()
                        p.start("sh", ["-c", "pactl set-sink-volume @DEFAULT_SINK@ " + delta])
                        p.waitForFinished()
                        update()
                    }
                }
            }

            property bool mute: false
            property int pct: 0
            Component.onCompleted: update()
            function update() {
                var m = new Process()
                m.start("sh", ["-c", "pactl get-sink-mute @DEFAULT_SINK@ | grep -q yes && echo muted || echo unmuted"])
                m.waitForFinished()
                mute = m.readAllStandardOutput().trim() === "muted"
                var v = new Process()
                v.start("sh", ["-c", "pactl get-sink-volume @DEFAULT_SINK@ | grep -Po '[0-9]+' | head -1"])
                v.waitForFinished()
                pct = parseInt(v.readAllStandardOutput().trim())
            }
        }

        // Battery / power profile (laptop)
        Item {
            id: battery
            visible: isLaptop
            width: 120
            RowLayout { anchors.fill: parent; spacing: 4 }

            Text { text: "Battery"; font.family: "SFMono Nerd Font Mono"; color: Palette.onBase }
            Text { id: batPct; text: capacity + "%"; color: Palette.onBase; font.family: "SFMono Nerd Font Mono" }
            Text { id: batState; text: charging ? "Charging" : ""; color: Palette.onBase; font.family: "SFMono Nerd Font Mono" }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var profile = currentProfile === "performance" ? "powersave" : "performance"
                    var p = new Process()
                    p.start("sh", ["-c", "powerprofilesctl set " + profile])
                    p.waitForFinished()
                    currentProfile = profile
                    Qt.openUrlExternally("notify-send \"Power profile\" " + profile)
                }
            }

            property bool isLaptop: false
            property int capacity: 0
            property bool charging: false
            property string currentProfile: "performance"

            Component.onCompleted: {
                var f = new QFile("/sys/class/power_supply/BAT0")
                isLaptop = f.exists()
                if (isLaptop) update()
                timer.start()
            }
            Timer {
                id: timer; interval: 60000; running: true; repeat: true
                onTriggered: update()
            }
            function update() {
                var c = new Process()
                c.start("sh", ["-c", "cat /sys/class/power_supply/BAT0/capacity"])
                c.waitForFinished()
                capacity = parseInt(c.readAllStandardOutput().trim())
                var ch = new Process()
                ch.start("sh", ["-c", "cat /sys/class/power_supply/BAT0/status"])
                ch.waitForFinished()
                charging = ch.readAllStandardOutput().trim() === "Charging"
                var p = new Process()
                p.start("sh", ["-c", "powerprofilesctl get"])
                p.waitForFinished()
                currentProfile = p.readAllStandardOutput().trim()
            }
        }

        // Brightness (laptop only)
        Item {
            visible: battery.isLaptop
            width: 80
            RowLayout { anchors.fill: parent; spacing: 4 }

            Text { text: "Brightness"; font.family: "SFMono Nerd Font Mono"; color: Palette.onBase }
            Text { id: brightPct; text: level + "%"; color: Palette.onBase; font.family: "SFMono Nerd Font Mono" }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: {
                    var delta = wheel.angleDelta.y > 0 ? "+5%" : "5%-"
                    var p = new Process()
                    p.start("sh", ["-c", "brightnessctl set " + delta])
                    p.waitForFinished()
                    update()
                }
            }

            property int level: 0
            Component.onCompleted: update()
            function update() {
                var cur = new Process()
                cur.start("sh", ["-c", "brightnessctl get"])
                cur.waitForFinished()
                var curVal = parseInt(cur.readAllStandardOutput().trim())
                var max = new Process()
                max.start("sh", ["-c", "brightnessctl max"])
                max.waitForFinished()
                var maxVal = parseInt(max.readAllStandardOutput().trim())
                level = Math.round(curVal / maxVal * 100)
            }
        }

        // Clock
        Text {
            text: Qt.formatTime(new Date(), "HH:mm")
            color: Palette.onBase
            font.family: "SFMono Nerd Font Mono"
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally("gnome-calendar") }
            Timer { interval: 60000; running: true; repeat: true; onTriggered: text = Qt.formatTime(new Date(), "HH:mm") }
        }
    }

    // OSD overlay (used by hardware‑key bindings)
    NotifyOverlay {
        anchors.fill: parent
        margin: 8
        radius: 0
        background: Rectangle { color: Palette.surface; opacity: 0.93 }
        textColor: Palette.onSurface
        titleFont.family: "SFMono Nerd Font Mono"
        bodyFont.family: "SFMono Nerd Font Mono"
        timeout: 1500
        animationDuration: 150
    }
}
EOF

# launcher.qml – app launcher grid
write_file "$BASE/quickshell/launcher.qml" - <<'EOF'
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0
import "palette.json" as Palette
import Qt.labs.platform 1.1

Item {
    width: Screen.width
    height: Screen.height
    visible: false
    focus: true

    LayerSurface {
        anchors.fill: parent
        layer: LayerSurface.Overlay
        exclusiveZone: -1
        keyboardInteractivity: LayerSurface.ExclusiveKeyboard
        margin: 0
    }

    Rectangle { anchors.fill: parent; color: Palette.base; opacity: 0.85 }

    GridView {
        focus: true
        anchors.centerIn: parent
        cellWidth: 96; cellHeight: 96; spacing: 12
        clip: true
        model: ListModel { id: appModel }

        delegate: Item {
            width: 96; height: 96
            Rectangle {
                anchors.fill: parent
                radius: 0
                color: hovered ? Palette.surface : "transparent"
                Image {
                    anchors.centerIn: parent
                    sourceSize.width: 64; sourceSize.height: 64
                    source: model.icon
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: model.name
                    font.pixelSize: 12
                    font.family: "SFMono Nerd Font Mono"
                    color: Palette.onSurface
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var p = new Process()
                        p.start("sh", ["-c", model.exec])
                        root.visible = false
                    }
                }
                property bool hovered: false
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: parent.hovered = true
                    onExited:  parent.hovered = false
                }
            }
        }
    }

    Component.onCompleted: {
        var folder = Qt.labs.platform.FolderListModel {
            folder: "file:///usr/share/applications"
            nameFilters: ["*.desktop"]
        }
        for (var i = 0; i < folder.count; ++i) {
            var entry = folder.get(i)
            var lines = entry.fileContent.split("\n")
            var name = "", exec = "", icon = ""
            for (var l = 0; l < lines.length; ++l) {
                var line = lines[l].trim()
                if (line.startsWith("Name=") && !name) name = line.slice(5)
                if (line.startsWith("Exec=") && !exec) exec = line.slice(5).replace(/%[UuFf]/g, "")
                if (line.startsWith("Icon=") && !icon) icon = line.slice(5)
                if (name && exec && icon) break
            }
            if (name && exec) {
                var iconUrl = icon ? "file:///usr/share/pixmaps/" + icon + ".png" : ""
                appModel.append({ "name": name, "exec": exec, "icon": iconUrl })
            }
        }
    }

    Keys.onReleased: if (event.key === Qt.Key_Escape) root.visible = false
}
EOF

# wallpaper-selector.qml – wallpaper selector grid
write_file "$BASE/quickshell/wallpaper-selector.qml" - <<'EOF'
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0
import "palette.json" as Palette
import Qt.labs.platform 1.1

Item {
    width: Screen.width
    height: Screen.height
    visible: false
    focus: true

    LayerSurface {
        anchors.fill: parent
        layer: LayerSurface.Overlay
        exclusiveZone: -1
        keyboardInteractivity: LayerSurface.ExclusiveKeyboard
        margin: 0
    }

    Rectangle { anchors.fill: parent; color: Palette.base; opacity: 0.85 }

    GridView {
        id: thumbGrid
        focus: true
        anchors.centerIn: parent
        cellWidth: 200; cellHeight: 150; spacing: 12
        clip: true
        model: ListModel { id: wpModel }

        delegate: Item {
            width: 200; height: 150
            Image {
                anchors.fill: parent
                source: fileUrl
                sourceSize.width: 200
                sourceSize.height: 150
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var set = new Process()
                    set.start("sh", ["-c", "hyprctl keyword decoration:active_wallpaper \"" + filePath + "\""])
                    set.waitForFinished()
                    var mat = new Process()
                    mat.start("sh", ["-c", "$HOME/.config/scripts/apply_matugen.sh"])
                    mat.waitForFinished()
                    root.visible = false
                }
                Rectangle {
                    anchors.fill: parent
                    color: hovered ? "white" : "transparent"
                    opacity: hovered ? 0.2 : 0
                }
                property bool hovered: false
                hoverEnabled: true
                onEntered: hovered = true
                onExited: hovered = false
            }
        }
    }

    Component.onCompleted: {
        var folder = Qt.labs.Platform.FolderListModel {
            folder: "file://" + Qt.getenv("HOME") + "/Pictures/wallpaper"
            nameFilters: ["*.jpg","*.jpeg","*.png","*.webp"]
        }
        for (var i = 0; i < folder.count; ++i) {
            var entry = folder.get(i)
            wpModel.append({ "filePath": entry.filePath, "fileUrl": entry.fileUrl })
        }
    }

    Keys.onReleased: if (event.key === Qt.Key_Escape) visible = false
}
EOF

# ai-sidebar.qml – ChatGPT, Gemini, Zukijourney, Ollama
write_file "$BASE/quickshell/ai-sidebar.qml" - <<'EOF'
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0
import "palette.json" as Palette
import Qt.labs.platform 1.1

Item {
    width: 380
    height: Screen.height
    visible: false
    focus: true

    LayerSurface {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        layer: LayerSurface.Overlay
        exclusiveZone: width
        keyboardInteractivity: LayerSurface.ExclusiveKeyboard
        margin: 0
    }

    Rectangle { anchors.fill: parent; color: Palette.base; opacity: 0.95; radius: 0 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 12

        RowLayout {
            spacing: 8
            ComboBox {
                id: backendSelect
                model: ["ChatGPT", "Google Gemini", "Zukijourney", "Ollama"]
                currentIndex: state.backendIndex
                onCurrentIndexChanged: {
                    state.backend = model[currentIndex]
                    state.backendIndex = currentIndex
                    saveState()
                }
                font.family: "SFMono Nerd Font Mono"
                background: Rectangle { color: "transparent" }
            }
            ComboBox {
                id: modelSelect
                visible: backendSelect.currentText === "Ollama"
                model: ollamaModels
                currentIndex: state.modelIndex
                onCurrentIndexChanged: {
                    state.model = model[currentIndex]
                    state.modelIndex = currentIndex
                    saveState()
                }
                font.family: "SFMono Nerd Font Mono"
                background: Rectangle { color: "transparent" }
            }
        }

        ScrollView {
            id: scrollArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            TextArea {
                id: chatBox
                readOnly: true
                wrapMode: TextEdit.Wrap
                font.family: "SFMono Nerd Font Mono"
                text: ""
                background: Rectangle { color: "transparent" }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            TextField {
                id: inputField
                Layout.fillWidth: true
                placeholderText: "Ask the AI…"
                font.family: "SFMono Nerd Font Mono"
                onAccepted: sendMessage()
            }
            Button {
                text: "Send"
                font.family: "SFMono Nerd Font Mono"
                onClicked: sendMessage()
            }
        }
    }

    // Persistence (backend + optional model)
    property var state: {
        "backend": "ChatGPT",
        "backendIndex": 0,
        "model": "",
        "modelIndex": 0
    }

    function loadState() {
        var file = FileIO.readFile("$HOME/.config/ai/sidebar_state.json")
        if (file) {
            try { state = JSON.parse(file) } catch (e) {}
        }
    }
    function saveState() {
        var json = JSON.stringify(state, null, 2)
        FileIO.writeFile("$HOME/.config/ai/sidebar_state.json", json)
    }

    Component.onCompleted: {
        loadState()
        if (backendSelect.currentText === "Ollama") fetchOllamaModels()
    }

    ListModel { id: ollamaModels }
    function fetchOllamaModels() {
        var proc = new Process()
        proc.start("sh", ["-c", "curl -s http://127.0.0.1:11434/api/tags | jq -r 'models[].name'"])
        proc.waitForFinished()
        var out = proc.readAllStandardOutput().trim()
        ollamaModels.clear()
        out.split("\n").forEach(function (m) { ollamaModels.append({ "name": m }) })
        if (!state.model && ollamaModels.count > 0) {
            state.model = ollamaModels.get(0).name
            state.modelIndex = 0
        }
    }

    function sendMessage() {
        var msg = inputField.text.trim()
        if (!msg) return
        chatBox.append("<b>Me:</b> " + msg + "\n")
        inputField.text = ""

        var backend = backendSelect.currentText
        var cmd = ""

        if (backend === "ChatGPT") {
            // OpenAI‑style API key ($OPENAI_API_KEY)
            cmd = `curl -s -X POST https://api.openai.com/v1/chat/completions \\
                -H "Authorization: Bearer $OPENAI_API_KEY" \\
                -H "Content-Type: application/json" \\
                -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"${msg}"}]}' | jq -r '.choices[0].message.content'`
        } else if (backend === "Google Gemini") {
            cmd = `curl -s -X POST https://generativelanguage.googleapis.com/v1/models/gemini-pro:generateContent?key=$GEMINI_API_KEY \\
                -H "Content-Type: application/json" \\
                -d '{"contents":[{"role":"user","parts":[{"text":"${msg}"}]}]}' | jq -r '.candidates[0].content.parts[0].text'`
        } else if (backend === "Zukijourney") {
            // Zukijourney uses the same “Bearer token” format as OpenAI
            cmd = `curl -s -X POST https://zukijourney.com/api/v1/chat \\
                -H "Content-Type: application/json" \\
                -H "Authorization: Bearer $ZUKI_API_KEY" \\
                -d '{"message":"${msg}"}' | jq -r '.response'`
        } else if (backend === "Ollama") {
            var model = modelSelect.currentText
            cmd = `curl -s -X POST http://127.0.0.1:11434/api/chat \\
                -H "Content-Type: application/json" \\
                -d '{"model":"${model}","messages":[{"role":"user","content":"${msg}"}]}' | jq -r '.message.content'`
        }

        var proc = new Process()
        proc.start("sh", ["-c", cmd])
        proc.finished.connect(function() {
            var reply = proc.readAllStandardOutput().trim()
            if (!reply) reply = "(no answer)"
            chatBox.append("<b>" + backend + ":</b> " + reply + "\n")
            scrollArea.contentY = scrollArea.contentHeight
        })
    }

    Keys.onReleased: if (event.key === Qt.Key_Escape) visible = false
}
EOF

# -------------------------------------------------------------------------
# Helper scripts (OSD, launcher, selector, AI, lock, gamemode, screenshot,
#                  wallpaper navigation)
# -------------------------------------------------------------------------

# osd_notify.sh – used by the panel and keybindings
write_file "$BASE/scripts/osd_notify.sh" - <<'EOF'
#!/usr/bin/env bash
title=$1
body=$2
icon=${3:-dialog-information}
notify-send -i "$icon" "$title" "$body" -t 1500
EOF
chmod +x "$BASE/scripts/osd_notify.sh"

# show-launcher.sh
write_file "$SCRIPT/show-launcher.sh" - <<'EOF'
#!/usr/bin/env bash
qdbus org.kde.quickshell /org/kde/quickshell org.kde.quickshell.Eval "launcher.visible = true; launcher.forceActiveFocus()"
EOF
chmod +x "$SCRIPT/show-launcher.sh"

# show-wallpaper-selector.sh
write_file "$SCRIPT/show-wallpaper-selector.sh" - <<'EOF'
#!/usr/bin/env bash
qdbus org.kde.quickshell /org/kde/quickshell org.kde.quickshell.Eval "wallpaperSelector.visible = true; wallpaperSelector.forceActiveFocus()"
EOF
chmod +x "$SCRIPT/show-wallpaper-selector.sh"

# show-ai-sidebar.sh
write_file "$SCRIPT/show-ai-sidebar.sh" - <<'EOF'
#!/usr/bin/env bash
qdbus org.kde.quickshell /org/kde/quickshell org.kde.quickshell.Eval "aiSidebar.visible = true; aiSidebar.forceActiveFocus()"
EOF
chmod +x "$SCRIPT/show-ai-sidebar.sh"

# lock.sh
write_file "$SCRIPT/lock.sh" - <<'EOF'
#!/usr/bin/env bash
WALL=$(hyprctl getoption decoration:active_wallpaper -j | jq -r '.str')
exec hyprlock -c $HOME/.config/hypr/hyprlock.conf -b "$WALL"
EOF
chmod +x "$SCRIPT/lock.sh"

# gamemode.sh (adds/removes a dummy variable; just a placeholder)
write_file "$SCRIPT/gamemode.sh" - <<'EOF'
#!/usr/bin/env bash
if grep -q "gmod=1" $HOME/.config/hypr/hyprland.conf; then
    sed -i '/gmod=1/d' $HOME/.config/hypr/hyprland.conf
    hyprctl reload
else
    echo "gmod=1" >> $HOME/.config/hypr/hyprland.conf
    hyprctl reload
fi
EOF
chmod +x "$SCRIPT/gamemode.sh"

# screenshot.sh (full / area / window / monitor)
write_file "$SCRIPT/screenshot.sh" - <<'EOF'
#!/usr/bin/env bash
mode=$1
out=$HOME/Pictures/screenshots/$(date +%Y-%m-%d-%H%M%S).png
mkdir -p "$(dirname "$out")"

case "$mode" in
    full)   grim "$out" ;;
    area)   grim -g "$(slurp)" "$out" ;;
    window) grim -g "$(hyprctl activewindow -j | jq -r '.at | @sh')" "$out" ;;
    monitor) grim -o "$(hyprctl monitors -j | jq -r '.[0].name')" "$out" ;;
    *) echo "Usage: $0 {full|area|window|monitor}"; exit 1 ;;
esac

wl-copy < "$out"
notify-send "Screenshot" "Saved to $out" -i camera-photo
EOF
chmod +x "$SCRIPT/screenshot.sh"

# wallpaper_next.sh
write_file "$SCRIPT/wallpaper_next.sh" - <<'EOF'
#!/usr/bin/env bash
DIR=$HOME/Pictures/wallpaper
shopt -s nullglob
files=("$DIR"/*.{jpg,jpeg,png,webp})
[[ ${#files[@]} -eq 0 ]] && exit 0
cur=$(hyprctl getoption decoration:active_wallpaper -j | jq -r '.str')
for i in "${!files[@]}"; do
    [[ "${files[$i]}" == "$cur" ]] && idx=$i && break
done
next=$(((idx+1) % ${#files[@]}))
hyprctl keyword decoration:active_wallpaper "${files[$next]}"
$HOME/.config/scripts/apply_matugen.sh
EOF
chmod +x "$SCRIPT/wallpaper_next.sh"

# wallpaper_prev.sh
write_file "$SCRIPT/wallpaper_prev.sh" - <<'EOF'
#!/usr/bin/env bash
DIR=$HOME/Pictures/wallpaper
shopt -s nullglob
files=("$DIR"/*.{jpg,jpeg,png,webp}})
[[ ${#files[@]} -eq 0 ]] && exit 0
cur=$(hyprctl getoption decoration:active_wallpaper -j | jq -r '.str')
for i in "${!files[@]}"; do
    [[ "${files[$i]}" == "$cur" ]] && idx=$i && break
done
prev=$(((idx-1+${#files[@]}) % ${#files[@]}))
hyprctl keyword decoration:active_wallpaper "${files[$prev]}"
$HOME/.config/scripts/apply_matugen.sh
EOF
chmod +x "$SCRIPT/wallpaper_prev.sh"

# wallpaper_random.sh
write_file "$SCRIPT/wallpaper_random.sh" - <<'EOF'
#!/usr/bin/env bash
DIR=$HOME/Pictures/wallpaper
shopt -s nullglob
files=("$DIR"/*.{jpg,jpeg,png,webp}})
[[ ${#files[@]} -eq 0 ]] && exit 0
rand=$((RANDOM % ${#files[@]}))
hyprctl keyword decoration:active_wallpaper "${files[$rand]}"
$HOME/.config/scripts/apply_matugen.sh
EOF
chmod +x "$SCRIPT/wallpaper_random.sh"

# -------------------------------------------------------------------------
# apply_matugen.sh – generate Material‑You palette and update the UI
# -------------------------------------------------------------------------
write_file "$SCRIPT/apply_matugen.sh" - <<'EOF'
#!/usr/bin/env bash
# Generate a Material‑You palette from the current wallpaper
WALL=$(hyprctl getoption decoration:active_wallpaper -j | jq -r '.str')
# matugen‑bin is the AUR binary that implements the Matugen crate
matugen-bin -i "$WALL" -m tonalspot -o "$HOME/.config/matugen/palette.json"

# GTK settings (Material‑You)
cat > "$HOME/.config/gtk-3.0/settings.ini" <<INI
[Settings]
gtk-theme-name = Matugen
gtk-font-name = "SFMono Nerd Font Mono 10"
INI
cat > "$HOME/.config/gtk-4.0/settings.ini" <<INI
[Settings]
gtk-theme-name = Matugen
gtk-font-name = "SFMono Nerd Font Mono 10"
INI

# Kvantum theme (mirrors the palette)
cat > "$HOME/.config/Kvantum/Matugen.kvconfig" <<KV
<kvantum>
  <Color name="Background" value="$(jq -r '.scheme.base' "$HOME/.config/matugen/palette.json")"/>
  <Color name="Foreground" value="$(jq -r '.scheme.on_base' "$HOME/.config/matugen/palette.json")"/>
  <Color name="Accent" value="$(jq -r '.scheme.accent' "$HOME/.config/matugen/palette.json")"/>
</kvantum>
KV

# btop theme
cat > "$HOME/.config/btop/btop.conf" <<BT
theme=custom
[custom_theme]
background=$(jq -r '.scheme.base' "$HOME/.config/matugen/palette.json")
foreground=$(jq -r '.on_base' "$HOME/.config/matugen/palette.json")
accent=$(jq -r '.accent' "$HOME/.config/matugen/palette.json")
BT

# Quickshell palette (used by panel, launcher, etc.)
cat > "$HOME/.config/quickshell/palette.json" <<JSON
{
  "accent":   "$(jq -r '.scheme.accent' "$HOME/.config/matugen/palette.json")",
  "base":     "$(jq -r '.scheme.base' "$HOME/.config/matugen/palette.json")",
  "onBase":  "$(jq -r '.scheme.on_base' "$HOME/.config/matugen/palette.json")",
  "surface": "$(jq -r '.scheme.surface' "$HOME/.config/matugen/palette.json")",
  "onSurface":"$(jq -r '.scheme.on_surface' "$HOME/.config/matugen/palette.json")"
}
JSON

# Tell Quickshell to reload its QML files (SIGUSR1)
kill -SIGUSR1 quickshell 2>/dev/null || true
EOF
chmod +x "$SCRIPT/apply_matugen.sh"

# -------------------------------------------------------------------------
# systemd‑user services (quickshell, hypridle)
# -------------------------------------------------------------------------
write_file "$BASE/systemd/user/quickshell.service" - <<'EOF'
[Unit]
Description=Quickshell – panel, launcher, wallpaper selector, AI sidebar
After=graphical-session.target

[Service]
ExecStart=/usr/bin/quickshell \
    -c $HOME/.config/quickshell/panel.qml \
    -c $HOME/.config/quickshell/launcher.qml \
    -c $HOME/.config/quickshell/wallpaper-selector.qml \
    -c $HOME/.config/quickshell/ai-sidebar.qml
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

write_file "$BASE/systemd/user/hypridle.service" - <<'EOF'
[Unit]
Description=Hypridle – idle timeout & lock
After=graphical-session.target

[Service]
ExecStart=/usr/bin/hypridle
Restart=always

[Install]
WantedBy=default.target
EOF

# -------------------------------------------------------------------------
# Enable the user services
# -------------------------------------------------------------------------
log "Reloading systemd‑user daemon"
systemctl --user daemon-reload

log "Enabling quickshell.service"
systemctl --user enable --now quickshell.service

log "Enabling hypridle.service"
systemctl --user enable --now hypridle.service

# -------------------------------------------------------------------------
# Clone LazyVim (official method)
# -------------------------------------------------------------------------
if [[ -d "$HOME/.config/nvim" && $FORCE_OVERWRITE -eq 0 ]]; then
  log "LazyVim already present – use --force to replace."
else
  log "Cloning LazyVim into $HOME/.config/nvim"
  git clone https://github.com/LazyVim/LazyVim.git "$HOME/.config/nvim"
  log "LazyVim cloned – run nvim once to install plugins."
fi

# -------------------------------------------------------------------------
# Generate the initial Material‑You palette (so the panel starts coloured)
# -------------------------------------------------------------------------
log "Generating initial Material‑You palette"
"$SCRIPT/apply_matugen.sh"

# -------------------------------------------------------------------------
# Final instructions
# -------------------------------------------------------------------------
log "============================================================"
log "Setup finished"
log ""
log "Next steps:"
log "  • Log out and log back in, or start Hyprland with \"Hyprland\"."
log "  • The top panel (Super+Space for launcher, Super+W for wallpaper selector,"
log "    Super+I for AI sidebar) should be visible."
log "  • All UI uses the \"SFMono Nerd Font Mono\" family."
log "  • Volume/brightness hardware keys now show OSD pop‑ups."
log "  • Export your AI keys:"
log "      • export OPENAI_API_KEY=…   # ChatGPT"
log "      • export GEMINI_API_KEY=…   # Google Gemini"
log "      • export ZUKI_API_KEY=…    # Zukijourney (same format as OpenAI)"
log "      • Run Ollama locally on port 11434 for the Ollama backend."
log "  • The chosen backend/model is stored at"
log "      $HOME/.config/ai/sidebar_state.json"
log "  • Run nvim once to finish LazyVim setup."
log "============================================================"
