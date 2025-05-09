#!/usr/bin/env bash
###############################################################################
#  oblivion_host.sh  ·  Head-less Steam-Link server for Vast.ai
#  – Fixes apt multi-arch mess on vastai/linux-desktop:cuda-12.4-ubuntu-22.04
#  – Pre-downloads Oblivion GOTY (AppID 22330) into /home/gamer/SteamLibrary
#  – Starts GPU dummy X + PulseAudio + Steam Big-Picture
#  – Needs: --disk 130  and ports 27036/tcp + 27037/udp open
###############################################################################
set -euo pipefail
log(){ printf '\e[1;36m==> %s\n' "$*"; }

### 0 · user parameters #######################################################
RES_W=3840 RES_H=2160                 # encoded stream resolution
STEAM_USER="${STEAM_USER:-}"          # pass as Vast secret
STEAM_PASS="${STEAM_PASS:-}"          # pass as Vast secret
APPIDS=(2623190)                        # Oblivion GOTY

### 1 · fix Vast’s “[arch=amd64] only” sources ###############################
log "Enabling i386 packages in APT"
sed -Ei 's/\[arch=amd64\]//g' /etc/apt/sources.list
dpkg --add-architecture i386
apt-get update -qq

### 2 · base runtime deps #####################################################
export DEBIAN_FRONTEND=noninteractive
apt-get install -yqq --no-install-recommends \
        curl ca-certificates software-properties-common gnupg \
        xserver-xorg-video-dummy xinit xrandr pulseaudio dbus-user-session \
        libgl1:i386 libgl1-mesa-dri:i386 libc6:i386 libstdc++6:i386 \
        libssl3:i386 libudev1:i386 libgssapi-krb5-2:i386 steamcmd

### 3 · unprivileged user #####################################################
useradd -m -s /bin/bash gamer 2>/dev/null || true
echo 'gamer ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-gamer

### 4 · Steam client ##########################################################
if ! command -v steam &>/dev/null; then
  log "Installing full Steam client"
  curl -fsSL -o /tmp/steam.deb \
       https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y /tmp/steam.deb && rm /tmp/steam.deb
fi

### 5 · dummy-monitor Xorg ####################################################
mkdir -p /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/10-headless.conf <<EOF
Section "Device"
  Identifier  "GPU0"
  Driver      "nvidia"
  Option      "AllowEmptyInitialConfiguration" "True"
EndSection
Section "Monitor"
  Identifier "Monitor0"
  Option     "Ignore" "false"
EndSection
Section "Screen"
  Identifier "Screen0"
  Device     "GPU0"
  Monitor    "Monitor0"
  DefaultDepth 24
  SubSection "Display"
    Depth 24
    Modes "${RES_W}x${RES_H}"
  EndSubSection
EndSection
EOF

### 6 · pre-download game(s) ##################################################
install_dir="/home/gamer/SteamLibrary"
mkdir -p "$install_dir"
if [[ -n "$STEAM_USER" && -n "$STEAM_PASS" ]]; then
  log "Downloading games with SteamCMD (this may take a while)…"
  for id in "${APPIDS[@]}"; do
    sudo -u gamer steamcmd +@sSteamCmdForcePlatformType windows \
          +login "$STEAM_USER" "$STEAM_PASS" \
          +force_install_dir "$install_dir/$id" \
          +app_update "$id" validate +quit
  done
else
  log "⚠️  STEAM_USER & STEAM_PASS not set – skipping auto-download"
fi

### 7 · runtime launcher ######################################################
cat >/usr/local/bin/start-steam-host <<"EOF"
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=:0
export HOME=/home/gamer

# start X once
pgrep -fx "X .*:0" >/dev/null || \
  /usr/bin/X :0 -config /etc/X11/xorg.conf.d/10-headless.conf -nocursor \
               &>/var/log/Xorg.0.log &

# PulseAudio (system mode)
pgrep -x pulseaudio >/dev/null || \
  pulseaudio --system --disallow-exit --disable-shm &

# Steam Big-Picture
if ! pgrep -x steam >/dev/null; then
  if [[ -n "$STEAM_USER" && -n "$STEAM_PASS" ]]; then
    sudo -u gamer steam -silent -tenfoot -login "$STEAM_USER" "$STEAM_PASS" &
  else
    sudo -u gamer steam -silent -tenfoot &
  fi
fi

wait -n
EOF
chmod +x /usr/local/bin/start-steam-host

### 8 · launch & done #########################################################
log "Launching Steam host…"
/usr/local/bin/start-steam-host > /var/log/steam-host.log 2>&1 &

log "All set!  Open ports:"
log " • TCP $(printenv VAST_TCP_PORT_27036:-27036)  (control)"
log " • UDP $(printenv VAST_UDP_PORT_27037:-27037)  (video)"
log "Add the computer manually in Steam Link with the *host-side* ports if auto-discover does not pick it up."
exit 0
