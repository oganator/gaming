#!/usr/bin/env bash
# vast‑gaming‑setup.sh  –  headless Steam + Sunshine auto‑provisioning
# works on Vast.ai linux‑desktop template  (Ubuntu 22.04)

set -euo pipefail
log(){ printf "\e[1;32m==> %s\e[0m\n" "$*"; }

###############################################################################
# 0 · constants (edit RES and STEAM_AUTO if you like)
###############################################################################
RES="2560x1600x24"           # Xvfb resolution
STEAM_AUTO="no"              # "yes" = auto‑launch Steam after boot
SUNSHINE_DEB_FALLBACK="https://github.com/LizardByte/Sunshine/releases/download/v0.23.0/sunshine_0.23.0_amd64.deb"

###############################################################################
# 1 · user & basic packages
###############################################################################
if ! id gamer &>/dev/null; then
  log "Adding user gamer"
  useradd -m -s /bin/bash gamer
  echo "gamer ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-gamer
fi

dpkg --add-architecture i386
apt-get update -yq
apt-get install -yq --no-install-recommends \
  wget curl ca-certificates gnupg jq iproute2 \
  xvfb pulseaudio dbus-user-session \
  libgl1:i386 libgl1-mesa-dri:i386 libc6:i386 libstdc++6:i386

###############################################################################
# 2 · Steam (official .deb pulls all i386 deps)
###############################################################################
if ! command -v steam &>/dev/null; then
  log "Installing Steam"
  curl -fsSL -o /tmp/steam.deb https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y /tmp/steam.deb && rm /tmp/steam.deb
fi

###############################################################################
# 3 · Sunshine – fetch latest .deb safely
###############################################################################
if ! dpkg -s sunshine &>/dev/null; then
  log "Installing Sunshine (latest release)"
  DL_URL=$(curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest |
           jq -r '.assets[] | select(.name|test("amd64.deb$")) | .browser_download_url' |
           head -n1 || true)

  [[ -z "$DL_URL" ]] && DL_URL="$SUNSHINE_DEB_FALLBACK"
  curl -fsSL -o /tmp/sunshine.deb "$DL_URL"
  apt-get install -y /tmp/sunshine.deb && rm /tmp/sunshine.deb
fi

###############################################################################
# 4 · one‑time Xorg dummy config for real NVIDIA cards (harmless on Xvfb)
###############################################################################
if command -v nvidia-xconfig &>/dev/null && [ ! -f /etc/X11/xorg.conf ]; then
  log "Generating nvidia‑xconfig dummy head"
  nvidia-xconfig --allow-empty-initial-configuration --virtual="${RES%x24}"
fi

###############################################################################
# 5 · startup wrapper
###############################################################################
cat >/usr/local/bin/start-gaming <<EOS
#!/usr/bin/env bash
set -euo pipefail
export HOME=/home/gamer
export DISPLAY=:0

# --- Xvfb ---------------------------------------------------------
pgrep -f "Xvfb :0" >/dev/null || Xvfb :0 -screen 0 ${RES} &

# --- PulseAudio ---------------------------------------------------
pgrep -u gamer pulseaudio >/dev/null || \
  sudo -H -u gamer dbus-run-session -- bash -c \
    "pulseaudio --start --exit-idle-time=-1"

# --- Sunshine -----------------------------------------------------
pgrep -u gamer sunshine >/dev/null || \
  sudo -H -u gamer sunshine >/var/log/sunshine.log 2>&1 &

# --- optional Steam ----------------------------------------------
if [[ "${STEAM_AUTO}" == "yes" ]]; then
  sudo -H -u gamer steam -silent &
fi

wait -n
EOS
chmod +x /usr/local/bin/start-gaming

###############################################################################
# 6 · launch it now (so ports are ready before Vast declares “running”)
###############################################################################
log "Starting headless desktop + Sunshine @ ${RES%*x*}"
nohup /usr/local/bin/start-gaming >/var/log/start-gaming.log 2>&1 &

log "Provisioning finished — Sunshine UI will be on port 47990"
###############################################################################
exit 0
