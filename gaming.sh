#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# vast‑auto‑gaming.sh  ·  Sunshine + Steam headless setup for Vast.ai
# Works on any Ubuntu‑22.04 base (linux‑desktop or CUDA images)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail
shopt -s nocasematch
log(){ printf '\e[1;32m==> %s\e[0m\n' "$*"; }

### 0 · constants ##############################################################
RES="2560x1600x24"                 # virtual monitor resolution
STEAM_AUTO="no"                    # yes ⇒ auto‑launch Steam on boot
SUN_TAG=$(curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest | jq -r .tag_name)
SUN_DEB="sunshine_${SUN_TAG#v}_ubuntu-22.04_amd64.deb"
SUN_URL="https://github.com/LizardByte/Sunshine/releases/download/${SUN_TAG}/${SUN_DEB}"
SUN_FALLBACK="https://github.com/LizardByte/Sunshine/releases/download/v0.23.0/sunshine_0.23.0_amd64.deb"

### 1 · user + basic packages ##################################################
if ! id gamer &>/dev/null; then
  log "Creating user gamer"
  useradd -m -s /bin/bash gamer
  echo 'gamer ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-gamer
fi

dpkg --add-architecture i386
apt-get update -qq
apt-get install -yqq --no-install-recommends \
  curl wget ca-certificates jq iproute2 gnupg \
  xvfb pulseaudio dbus-user-session \
  libgl1-mesa-dri:i386 libgl1:i386 libc6:i386 libstdc++6:i386

### 2 · Steam ##################################################################
if ! command -v steam &>/dev/null; then
  log "Installing Steam"
  curl -fsSL -o /tmp/steam.deb \
    https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y /tmp/steam.deb && rm /tmp/steam.deb
fi

### 3 · Sunshine ###############################################################
if ! dpkg -s sunshine &>/dev/null; then
  log "Installing Sunshine ${SUN_TAG}"
  curl -fsSL -o /tmp/sunshine.deb "$SUN_URL" || {
     log "latest download failed, using fallback"
     curl -fsSL -o /tmp/sunshine.deb "$SUN_FALLBACK"
  }
  apt-get install -y /tmp/sunshine.deb && rm /tmp/sunshine.deb
fi

### 4 · dummy Xorg for real NVIDIA (harmless on Xvfb) ##########################
if command -v nvidia-xconfig &>/dev/null && [ ! -f /etc/X11/xorg.conf ]; then
  nvidia-xconfig --allow-empty-initial-configuration --virtual="${RES%x24}"
fi

### 5 · start‑gaming wrapper ###################################################
cat >/usr/local/bin/start-gaming <<"EOS"
#!/usr/bin/env bash
set -euo pipefail
export HOME=/home/gamer
export DISPLAY=:0
# wipe stale locks, ignore errors
rm -f /tmp/.X*-lock || true

# ① Xvfb virtual display
pgrep -f "Xvfb :0" >/dev/null || \
  Xvfb :0 -screen 0 __RES__ &

# ② PulseAudio (per‑user dbus session)
pgrep -u gamer pulseaudio >/dev/null || \
  sudo -H -u gamer dbus-run-session -- bash -c \
    "pulseaudio --start --exit-idle-time=-1"

# ③ Sunshine
pgrep -u gamer sunshine >/dev/null || \
  sudo -H -u gamer sunshine >/var/log/sunshine.log 2>&1 &

# ④ Optional Steam
if [[ "__STEAM_AUTO__" == "yes" ]]; then
  sudo -H -u gamer steam -silent &
fi

wait -n                   # keep foreground so container stays “running”
EOS
sed -i "s/__RES__/${RES}/"           /usr/local/bin/start-gaming
sed -i "s/__STEAM_AUTO__/${STEAM_AUTO}/" /usr/local/bin/start-gaming
chmod +x /usr/local/bin/start-gaming

### 6 · launch it now ##########################################################
log "Launching Xvfb+Pulse+Sunshine @ ${RES}"
nohup /usr/local/bin/start-gaming >/var/log/start-gaming.log 2>&1 &

log "Done – Sunshine UI on port 47990, control on 47984."
exit 0
