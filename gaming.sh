#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# gaming.sh · headless Steam-Link host for Vast.ai
# ─────────────────────────────────────────────────────────────
set -euo pipefail
log(){ printf '\e[1;36m==> %s\n' "$*"; }

RES="2560x1600x24"                # Xvfb virtual monitor
STEAM_AUTO="yes"                  # always start Steam
STEAM_USER="${STEAM_USER:-}"      # injected via template secret
STEAM_PASS="${STEAM_PASS:-}"      # injected via template secret

export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update -qq
apt-get install -yqq --no-install-recommends \
  curl wget jq ca-certificates xvfb x11vnc pulseaudio dbus-user-session \
  libgl1-mesa-dri:i386 libgl1:i386 libc6:i386 libstdc++6:i386 \
  python3-pip

# -------- user --------------------------------------------------------------
if ! id gamer &>/dev/null; then
  log "Creating user 'gamer'"
  useradd -m -s /bin/bash gamer
  echo 'gamer ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-gamer
fi

# -------- Steam -------------------------------------------------------------
if ! command -v steam &>/dev/null; then
  log "Installing Steam"
  curl -fsSL -o /tmp/steam.deb \
       https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y /tmp/steam.deb && rm /tmp/steam.deb
fi

# -------- Jupyter (optional admin shell) ------------------------------------
python3 -m pip install --no-cache --upgrade \
        jupyterlab notebook jupyterlab_server jupyter_server

# -------- one-shot launcher --------------------------------------------------
cat >/usr/local/bin/start-gaming <<"EOF"
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=:0
export HOME=/home/gamer

# ① virtual X
pgrep -f "Xvfb :0" || Xvfb :0 -screen 0 __RES__ &

# ② PulseAudio (system mode = fine in container)
pgrep -x pulseaudio || pulseaudio --system --disallow-exit --disable-shm &

# ③ x11vnc (read-only view, no password)
pgrep -f "x11vnc.*5900" || \
  x11vnc -display :0 -ncache 10 -forever -shared -nopw -rfbport 5900 &

# ④ Steam in BP mode
if [[ "__STEAM_AUTO__" == "yes" ]]; then
  sudo -u gamer bash -c '
    if ! pgrep -x steam; then
      if [[ -n "$STEAM_USER" && -n "$STEAM_PASS" ]]; then
        echo "auto-login credentials present"
        steam -silent -tenfoot -login "$STEAM_USER" "$STEAM_PASS" &
      else
        steam -silent -tenfoot &
      fi
    fi'
fi

# ⑤ Jupyter (admin only)
pgrep -f "jupyter.*--port=8080" || \
  nohup jupyter lab --ip=0.0.0.0 --port=8080 \
        --no-browser --LabApp.token="$JUPYTER_TOKEN" \
        >/var/log/jupyter.log 2>&1 &

wait -n
EOF

# substitute vars
sed -i "s/__RES__/${RES}/" /usr/local/bin/start-gaming
sed -i "s/__STEAM_AUTO__/${STEAM_AUTO}/" /usr/local/bin/start-gaming
chmod +x /usr/local/bin/start-gaming

# -------- launch now --------------------------------------------------------
log "Launching gaming stack"
/usr/local/bin/start-gaming >/var/log/start-gaming.log 2>&1 &

log "Steam-Link host ready:"
log "  • Jupyter  : http://<IP>:8080 (token in /var/log/jupyter.log)"
log "  • VNC peek : <VNC-client> → <IP>:5900"
log "Ports 27036/TCP + 27037/UDP are already exposed for Steam Link."
exit 0
