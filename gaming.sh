#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# oblivion_host.sh · one-shot bootstrap for a head-less Steam-Link host
# • Ubuntu 22.04 base (vastai/linux-desktop:cuda-12.4-ubuntu-22.04)
# • Installs Steam + SteamCMD
# • Pre-downloads Elder Scrolls IV: Oblivion GOTY (AppID 22330)
# • Starts GPU-backed dummy X server, PulseAudio, and Steam Big-Picture
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
log(){ printf '\e[1;36m==> %s\n' "$*"; }

###############################################################################
# 0 · USER SETTINGS – tweak as you like
###############################################################################
RES_W=3840 RES_H=2160            # encoded stream resolution
STEAM_AUTO=yes                   # auto-start Steam Big-Picture
STEAM_USER="${STEAM_USER:-}"     # set as template secret in Vast
STEAM_PASS="${STEAM_PASS:-}"     # set as template secret in Vast

# Oblivion GOTY - AppID 22330  (swap for your own titles)
APPIDS=(2623190)

###############################################################################
# 1 · bare-minimum runtime deps
###############################################################################
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update -qq
apt-get install -yqq --no-install-recommends \
        curl ca-certificates software-properties-common gnupg \
        xserver-xorg-video-dummy xinit xrandr pulseaudio dbus-user-session \
        libgl1:i386 libgl1-mesa-dri:i386 libc6:i386 libstdc++6:i386 \
        steamcmd                                          # pulls ±25 MB

###############################################################################
# 2 · unprivileged gamer account
###############################################################################
if ! id gamer &>/dev/null; then
  log "Creating user 'gamer'"
  useradd -m -s /bin/bash gamer
  echo 'gamer ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-gamer
fi

###############################################################################
# 3 · install full Steam client (needed for Big-Picture / NVENC streaming)
###############################################################################
if ! command -v steam &>/dev/null; then
  log "Installing Steam client"
  curl -fsSL -o /tmp/steam.deb \
       https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y /tmp/steam.deb && rm /tmp/steam.deb
fi

###############################################################################
# 4 · head-less GPU-driven X server (dummy monitor)
###############################################################################
mkdir -p /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/10-headless.conf <<EOF
Section "Device"
  Identifier  "GPU0"
  Driver      "nvidia"
  Option      "AllowEmptyInitialConfiguration" "True"
EndSection
Section "Screen"
  Identifier "Screen0"
  Device     "GPU0"
  Monitor    "Monitor0"
  DefaultDepth 24
  SubSection "Display"
    Depth     24
    Modes     "${RES_W}x${RES_H}"
  EndSubSection
EndSection
Section "Monitor"
  Identifier "Monitor0"
  Option     "Ignore" "false"
EndSection
EOF

###############################################################################
# 5 · pre-download game(s) with SteamCMD
###############################################################################
install_dir="/home/gamer/SteamLibrary"
sudo -u gamer mkdir -p "$install_dir"

if [[ -n "$STEAM_USER" && -n "$STEAM_PASS" ]]; then
  log "Downloading games via SteamCMD (this can take a while)…"
  for id in "${APPIDS[@]}"; do
    sudo -u gamer steamcmd +@sSteamCmdForcePlatformType windows \
          +login "$STEAM_USER" "$STEAM_PASS" \
          +force_install_dir "$install_dir/$id" \
          +app_update "$id" validate \
          +quit
  done
else
  log "⚠️  No Steam credentials provided → skipping auto-download"
fi

###############################################################################
# 6 · one-shot runtime launcher
###############################################################################
cat >/usr/local/bin/start-steam-host <<"EOF"
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=:0
export HOME=/home/gamer

# Xorg head-less + GPU
if ! pgrep -fx "X .*:0"; then
  /usr/bin/X :0 -config /etc/X11/xorg.conf.d/10-headless.conf -nocursor \
               &> /var/log/Xorg.0.log &
fi

# PulseAudio (system mode is fine in container)
pgrep -x pulseaudio || pulseaudio --system --disallow-exit --disable-shm &

# OPTIONAL VNC peek – uncomment for debugging then disable
# pgrep -f "x11vnc.*5900" || \
#   x11vnc -display :0 -forever -shared -nopw -rfbport 5900 &

# Steam Big-Picture auto-login
if [[ "${STEAM_AUTO}" == "yes" ]]; then
  sudo -u gamer bash -c '
    if ! pgrep -x steam; then
      if [[ -n "$STEAM_USER" && -n "$STEAM_PASS" ]]; then
        steam -silent -tenfoot -login "$STEAM_USER" "$STEAM_PASS" &
      else
        steam -silent -tenfoot &
      fi
    fi'
fi

wait -n
EOF
chmod +x /usr/local/bin/start-steam-host

###############################################################################
# 7 · launch and finish
###############################################################################
log "Starting Steam-Link host…"
/usr/local/bin/start-steam-host >/var/log/steam-host.log 2>&1 &

log "Setup complete."
log "• Steam control port : 27036/tcp  (host side may be remapped)"
log "• Steam data port    : 27037/udp  (host side may be remapped)"
log "• Disk provisioned   : ensure --disk 130 when you create the instance"
exit 0
