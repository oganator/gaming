#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# gaming.sh  ·  zero‑touch Steam Link + Steam + Jupyter for Vast
# tested on vastai/linux‑desktop:cuda‑12.4‑ubuntu‑22.04
# ─────────────────────────────────────────────────────────────
set -euo pipefail
shopt -s nocasematch
log(){ printf '\e[1;36m%s\e[0m\n' "==> $*"; }

# ---------- 0 · constants -----------------------------------
RES="3840x2160x32"                       # virtual monitor (Xvfb)
STEAM_AUTO="yes"                         # auto‑launch Steam? yes|no
STEAM_USERNAME="${STEAM_USER:-}"
STEAM_PASSWORD="${STEAM_PASS:-}"
STEAM_GAMES=("2623190")          # <<-- Steam IDs (TF2, Dota 2, CSGO) 
                                         # Find more here: https://steamdb.info/apps/
if [[ -z "$STEAM_USERNAME" || -z "$STEAM_PASSWORD" ]]; then
  log "ERROR: STEAM_USER / STEAM_PASS not set.  Pass them in --env."
  exit 1
fi

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

# ---------- 4 · Auto-login & Game Download -------------------
log "Configuring Steam auto-login and game downloads"

# Create autostart script
cat > /home/gamer/.xinitrc <<"EOF"
#!/bin/bash
steam -login __STEAM_USER__ __STEAM_PASS__ \
  -silent -nobootstrapupdate -norepairfiles -noverifyfiles
EOF

# Replace credentials in autostart script
sed -i "s/__STEAM_USER__/${STEAM_USERNAME}/" /home/gamer/.xinitrc
sed -i "s/__STEAM_PASS__/${STEAM_PASSWORD}/" /home/gamer/.xinitrc

chmod +x /home/gamer/.xinitrc
chown gamer:gamer /home/gamer/.xinitrc

# Pre-download specified games
log "Downloading games: ${STEAM_GAMES[*]}"
for GAME_ID in "${STEAM_GAMES[@]}"; do
  sudo -u gamer steamcmd +login "${STEAM_USERNAME}" "${STEAM_PASSWORD}" +force_install_dir ~/SteamLibrary +app_update "${GAME_ID}" validate +quit
done

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

# ③ Start X for Steam Link
sudo -u gamer pgrep -x steam >/dev/null || \
  sudo -u gamer startx >/var/log/steam.log 2>&1 &

# ④ Jupyter
pgrep -f "jupyter.*--port=8080" >/dev/null || \
  nohup jupyter lab --ip=0.0.0.0 --port=8080 \
        --no-browser --LabApp.token="$JUPYTER_TOKEN" \
        >/var/log/jupyter.log 2>&1 &

wait -n
EOF
chmod +x /usr/local/bin/start-gaming
sed -i "s/__RES__/${RES}/"            /usr/local/bin/start-gaming
sed -i "s/__STEAM_AUTO__/${STEAM_AUTO}/" /usr/local/bin/start-gaming

# ---------- 7 · launch immediately --------------------------
log "Launching gaming stack"
nohup /usr/local/bin/start-gaming >/var/log/start-gaming.log 2>&1 &

log "Steam Link   : Add PC in Steam Link app with IP <public-ip>"
log "Jupyter Lab  : http://<public‑ip>:8080  (token=$JUPYTER_TOKEN)"
log "Setup done!"
exit 0
