#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# gaming.sh  ·  zero‑touch Sunshine + Steam + Jupyter for Vast
# tested on vastai/linux‑desktop:cuda‑12.4‑ubuntu‑22.04
# ─────────────────────────────────────────────────────────────
set -euo pipefail
shopt -s nocasematch
log(){ printf '\e[1;36m%s\e[0m\n' "==> $*"; }

# ---------- 0 · constants -----------------------------------
RES="2560x1600x24"                       # virtual monitor (Xvfb)
STEAM_AUTO="no"                          # auto‑launch Steam? yes|no
SUN_TAG=$(curl -fsSL https://api.github.com/repos/LizardByte/Sunshine/releases/latest | jq -r .tag_name)
SUN_DEB="sunshine_${SUN_TAG#v}_ubuntu-22.04_amd64.deb"
SUN_URL="https://github.com/LizardByte/Sunshine/releases/download/${SUN_TAG}/${SUN_DEB}"
SUN_FALLBACK="https://github.com/LizardByte/Sunshine/releases/download/v0.23.0/sunshine_0.23.0_amd64.deb"

# ---------- 1 · basic packages ------------------------------
log "Updating apt & installing base packages"
dpkg --add-architecture i386
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -yqq --no-install-recommends \
        curl wget jq ca-certificates xvfb pulseaudio \
        dbus-user-session libgl1-mesa-dri:i386 libgl1:i386 \
        libc6:i386 libstdc++6:i386                         \
        python3-pip

# ---------- 2 · user account --------------------------------
if ! id gamer &>/dev/null; then
  log "Creating user 'gamer'"
  useradd -m -s /bin/bash gamer
  echo 'gamer ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-gamer
fi

# ---------- 3 · Steam client --------------------------------
if ! command -v steam &>/dev/null; then
  log "Installing Steam"
  curl -fsSL -o /tmp/steam.deb \
       https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y /tmp/steam.deb
  rm /tmp/steam.deb
fi

# ---------- 4 · Sunshine ------------------------------------
if ! dpkg -s sunshine &>/dev/null; then
  log "Installing Sunshine ${SUN_TAG}"
  curl -fsSL -o /tmp/sunshine.deb "$SUN_URL" || {
        log "latest Sunshine failed, using fallback"
        curl -fsSL -o /tmp/sunshine.deb "$SUN_FALLBACK"
  }
  apt-get install -y /tmp/sunshine.deb
  rm /tmp/sunshine.deb
fi

# make an empty config so Sunshine stops complaining
install -o gamer -g gamer -d /home/gamer/.config/sunshine

# ---------- 5 · Jupyter stack -------------------------------
log "Installing JupyterLab"
python3 -m pip install --no-cache --upgrade \
        jupyterlab notebook jupyterlab_server jupyter_server

# ---------- 6 · one‑shot launcher script --------------------
cat >/usr/local/bin/start-gaming <<"EOF"
#!/usr/bin/env bash
set -euo pipefail
export HOME=/home/gamer
export DISPLAY=:0

# ① virtual X
pgrep -f "Xvfb :0" >/dev/null || \
  Xvfb :0 -screen 0 __RES__ &

# ② PulseAudio (system mode is fine inside container)
pgrep -x pulseaudio >/dev/null || \
  pulseaudio --system --disallow-exit --disable-shm &

# ③ Sunshine headless
sudo -u gamer pgrep -x sunshine >/dev/null || \
  sudo -u gamer sunshine >/var/log/sunshine.log 2>&1 &

# ④ Jupyter
pgrep -f "jupyter.*--port=8080" >/dev/null || \
  nohup jupyter lab --ip=0.0.0.0 --port=8080 \
        --no-browser --LabApp.token="$JUPYTER_TOKEN" \
        >/var/log/jupyter.log 2>&1 &

# ⑤ optional Steam
if [[ "__STEAM_AUTO__" == "yes" ]]; then
  sudo -u gamer steam -silent &
fi

wait -n
EOF
chmod +x /usr/local/bin/start-gaming
sed -i "s/__RES__/${RES}/"            /usr/local/bin/start-gaming
sed -i "s/__STEAM_AUTO__/${STEAM_AUTO}/" /usr/local/bin/start-gaming

# ---------- 7 · launch immediately --------------------------
log "Launching gaming stack"
nohup /usr/local/bin/start-gaming >/var/log/start-gaming.log 2>&1 &

log "Sunshine UI  : http://<public‑ip>:47990"
log "Jupyter Lab  : http://<public‑ip>:8080  (token=$JUPYTER_TOKEN)"
log "Setup done!"
exit 0
