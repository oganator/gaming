#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

### 0  helper
log(){ printf "\e[1;32m==> %s\e[0m\n" "$*"; }

### 1  create a normal user so Sunshine shows all features
if ! id gamer &>/dev/null; then
  log "Creating user: gamer"
  useradd -m -s /bin/bash gamer
  echo "gamer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-gamer
fi

### 2  system packages
log "Updating & installing packages"
dpkg --add-architecture i386
apt-get update
apt-get install -y \
  wget curl gnupg ca-certificates jq lsof \
  xvfb pulseaudio dbus-user-session \
  libgl1:i386 libgl1-mesa-dri:i386 libc6:i386 libstdc++6:i386

### 3  Steam (Valve’s official .deb pulls all i386 deps)
if ! command -v steam &>/dev/null; then
  log "Installing Steam"
  wget -qO steam.deb https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
  apt-get install -y ./steam.deb
  rm steam.deb
fi

### 4  Sunshine (latest stable .deb)
SUN_VER="0.23.0"
if ! dpkg -s sunshine &>/dev/null; then
  log "Installing Sunshine $SUN_VER"
  wget -qO sunshine.deb "https://github.com/LizardByte/Sunshine/releases/download/v${SUN_VER}/sunshine_${SUN_VER}_amd64.deb"
  apt-get install -y ./sunshine.deb
  rm sunshine.deb
fi

### 5  one‑time X config for headless NVIDIA
if command -v nvidia-xconfig &>/dev/null && \
   [ ! -f /etc/X11/xorg.conf ]; then
  log "Generating Xorg dummy config"
  nvidia-xconfig --allow-empty-initial-configuration --virtual=1920x1080
fi

### 6  startup wrapper written to /usr/local/bin/start-gaming
cat >/usr/local/bin/start-gaming <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
export HOME=/home/gamer
export DISPLAY=:0

# ① virtual display
if ! pgrep -f "Xvfb :0" >/dev/null; then
  Xvfb :0 -screen 0 1920x1080x24 &
fi

# ② user‑session bus & PulseAudio
if ! pgrep -u gamer pulseaudio >/dev/null; then
  sudo -H -u gamer dbus-run-session -- bash -c \
    "pulseaudio --start --exit-idle-time=-1"
fi

# ③ Sunshine (runs as gamer so Reverse‑Connections etc. appear)
if ! pgrep -u gamer sunshine >/dev/null; then
  sudo -H -u gamer sunshine >/var/log/sunshine.log 2>&1 &
fi

# ④ Steam optional autostart (comment if you don’t want it)
# sudo -H -u gamer steam -silent &

wait -n   # keep container alive
EOS
chmod +x /usr/local/bin/start-gaming

### 7  launch the wrapper in background
log "Starting headless desktop + Sunshine"
nohup /usr/local/bin/start-gaming >/var/log/start-gaming.log 2>&1 &

log "Finished on‑start.  Sunshine UI ⇒ https://<instance-ip>:<mapped-port-47990>"
