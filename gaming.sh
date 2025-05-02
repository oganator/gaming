#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# gaming.sh  –  Headless gamer image for Vast.ai
# Installs:  • Sunshine  • Steam  • dummy X screen  • PulseAudio
# Adds:      • JupyterLab on port 8080
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
shopt -s nocasematch
log(){ printf '\e[1;32m==> %s\e[0m\n' "$*"; }

######################## 0 · constants ########################################
RES="2560x1600x24"          # Xvfb resolution
STEAM_AUTO="no"             # yes → Steam auto‑starts after boot

SUN_TAG=$(curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest |
          jq -r .tag_name)
SUN_DEB="sunshine_${SUN_TAG#v}_ubuntu-22.04_amd64.deb"
SUN_URL="https://github.com/LizardByte/Sunshine/releases/download/${SUN_TAG}/${SUN_DEB}"
SUN_FALLBACK="https://github.com/LizardByte/Sunshine/releases/download/v0.23.0/sunshine_0.23.0_amd64.deb"

######################## 1 · base packages & user #############################
dpkg --add‑architecture i386
apt-get update -qq
apt-get install -yqq --no-install-recommends \
    curl wget ca-certificates jq gnupg iproute2 \
    xvfb pulseaudio dbus-user-session \
    libgl1-mesa-dri:i386 libgl1:i386 libc6:i386 libstdc++6:i386

if ! id gamer &>/dev/null; then
  log "Creating user <gamer>"
  useradd -m -s /bin/bash gamer
  echo 'gamer ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-gamer
fi

######################## 2 · Steam ############################################
if ! command -v steam &>/dev/null; then
  log "Installing Steam"
  curl -fsSL -o /tmp/steam.deb \
       https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y /tmp/steam.deb
  rm /tmp/steam.deb
fi

######################## 3 · Sunshine #########################################
if ! dpkg -s sunshine &>/dev/null; then
  log "Installing Sunshine $SUN_TAG"
  curl -fsSL -o /tmp/sunshine.deb "$SUN_URL" || {
      log "latest Sunshine failed, using fallback build"
      curl -fsSL -o /tmp/sunshine.deb "$SUN_FALLBACK"
  }
  apt-get install -y /tmp/sunshine.deb
  rm /tmp/sunshine.deb
fi

######################## 4 · JupyterLab #######################################
log "Installing JupyterLab"
python3 -m pip install --no-cache --upgrade \
        notebook jupyterlab jupyter_server

log "Starting JupyterLab (port 8080)"
nohup jupyter lab --ip=0.0.0.0 --port=8080 \
      --NotebookApp.token="${JUPYTER_TOKEN:-vast}" --no-browser \
      > /var/log/jupyter.log 2>&1 &

######################## 5 · dummy X for real NVIDIA ##########################
if command -v nvidia-xconfig &>/dev/null && [ ! -f /etc/X11/xorg.conf ]; then
  nvidia-xconfig --allow-empty-initial-configuration --virtual="${RES%x24}"
fi

######################## 6 · start‑gaming helper ##############################
cat >/usr/local/bin/start-gaming <<"EOF"
#!/usr/bin/env bash
set -euo pipefail
export HOME=/home/gamer
export DISPLAY=:0
rm -f /tmp/.X*-lock || true                       # stale locks

# ① Xvfb
pgrep -f "Xvfb :0" >/dev/null || \
  Xvfb :0 -screen 0 __RES__ &

# ② PulseAudio (user session)
pgrep -u gamer pulseaudio >/dev/null || \
  sudo -H -u gamer dbus-run-session -- \
       pulseaudio --start --exit-idle-time=-1

# ③ Sunshine
pgrep -u gamer sunshine >/dev/null || \
  sudo -H -u gamer sunshine >>/var/log/sunshine.log 2>&1 &

# ④ (optional) Steam
if [[ "__STEAM_AUTO__" == "yes" ]]; then
  sudo -H -u gamer steam -silent &
fi

wait -n        # keep container running
EOF
sed -i "s/__RES__/${RES}/"           /usr/local/bin/start-gaming
sed -i "s/__STEAM_AUTO__/${STEAM_AUTO}/" /usr/local/bin/start-gaming
chmod +x /usr/local/bin/start-gaming

######################## 7 · launch services ##################################
log "Launching Xvfb + PulseAudio + Sunshine"
nohup /usr/local/bin/start-gaming >/var/log/start-gaming.log 2>&1 &

log "Setup complete – Sunshine UI :47990, Jupyter :8080"
exit 0
