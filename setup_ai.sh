# HP Omen 15-ek0013nl: Intel Core i7-10750H, 16 GB RAM, 512 GB SSD, RTX 2060 6 GB, display 15,6" FHD 144 Hz.

#!/bin/bash
set -e  # Ferma lo script in caso di errore

log() { echo -e "\033[1;32m$1\033[0m"; }

# -------------------------------------------------------------------------
# 🚀 VARIABILI GENERALI
# -------------------------------------------------------------------------
# Container Fooocus
CONTAINER_NAME_FOOOCUS="fooocus-gpu"
IMAGE_NAME_FOOOCUS="ghcr.io/lllyasviel/fooocus:latest"
HOST_PORT_FOOOCUS=7865
CONTAINER_PORT_FOOOCUS=7865

# Container Kokoro FastAPI
CONTAINER_NAME_KOKORO="kokoro-fastapi-gpu"
IMAGE_NAME_KOKORO="ghcr.io/remsky/kokoro-fastapi-gpu:latest"
HOST_PORT_KOKORO=8880
CONTAINER_PORT_KOKORO=8880

# Container MusicGPT
CONTAINER_NAME_MUSIC_GPT="musicgpt-ui"
IMAGE_NAME_MUSIC_GPT="gabotechs/musicgpt"
HOST_PORT_MUSIC_GPT=7860
CONTAINER_PORT_MUSIC_GPT=8642

# -------------------------------------------------------------------------
# 🚀 AGGIORNAMENTO SISTEMA
# -------------------------------------------------------------------------
log "🚀 Aggiornamento pacchetti..."
sudo apt update -y && sudo apt upgrade -y

# -------------------------------------------------------------------------
# 🏠 HOME UTENTE
# -------------------------------------------------------------------------
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  USER_HOME=$(eval echo ~"$SUDO_USER")
else
  USER_HOME="$HOME"
fi
log "🏠 Home utente rilevata: $USER_HOME"

# -------------------------------------------------------------------------
# 🔐 SSH
# -------------------------------------------------------------------------
log "🔐 Configurazione SSH..."
if ! dpkg -l | grep -q openssh-server; then
  sudo apt install -y openssh-server
fi
sudo systemctl enable ssh
sudo systemctl start ssh

# -------------------------------------------------------------------------
# 🧠 DRIVER NVIDIA + CUDA
# -------------------------------------------------------------------------
log "🧠 Verifica driver NVIDIA..."
if ! command -v nvidia-smi &>/dev/null; then
  sudo ubuntu-drivers autoinstall
fi

log "🎯 Verifica toolkit CUDA..."
if ! dpkg -l | grep -q nvidia-cuda-toolkit; then
  sudo apt install -y nvidia-cuda-toolkit
fi

# -------------------------------------------------------------------------
# 💤 NO SLEEP
# -------------------------------------------------------------------------
log "💤 Disattivazione sospensione automatica..."
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# -------------------------------------------------------------------------
# 🔄 MODULI NVIDIA
# -------------------------------------------------------------------------
log "🔄 Caricamento moduli NVIDIA..."
for mod in nvidia nvidia_uvm nvidia_modeset; do
  if ! lsmod | grep -wq "$mod"; then
    sudo modprobe $mod || true
  fi
done
sleep 5

# -------------------------------------------------------------------------
# 🧠 INSTALLAZIONE OLLAMA
# -------------------------------------------------------------------------
log "🧠 Verifica Ollama..."
if ! command -v ollama &>/dev/null || ! curl -fs http://127.0.0.1:11434/api/version &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

log "⚙️ Configurazione Ollama GPU..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/ollama serve
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_DEVICE=gpu"
Environment="OLLAMA_USE_CUDA=1"
EOF'
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart ollama

# Attesa Ollama
for i in {1..5}; do
  if curl -fs http://127.0.0.1:11434/api/version &>/dev/null; then break; fi
  sleep 3
done

# -------------------------------------------------------------------------
# ⬇️ MODELLO OLLAMA
# -------------------------------------------------------------------------
if ! ollama list | grep -q llama3.2; then
  log "⬇️ Download modello Ollama llama3.2..."
  ollama pull llama3.2:latest
fi

# -------------------------------------------------------------------------
# 🐋 INSTALLAZIONE DOCKER
# -------------------------------------------------------------------------
log "🐋 Verifica Docker..."
if ! command -v docker &>/dev/null; then
  sudo apt install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
fi

# -------------------------------------------------------------------------
# 🚀 AVVIO CONTAINER
# -------------------------------------------------------------------------

# Fooocus (GPU)
if sudo docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME_FOOOCUS\$"; then
  sudo docker rm -f $CONTAINER_NAME_FOOOCUS
fi
log "🚀 Avvio container $CONTAINER_NAME_FOOOCUS..."
sudo docker run -d \
  --gpus all \
  --name $CONTAINER_NAME_FOOOCUS \
  --restart always \
  -p $HOST_PORT_FOOOCUS:$CONTAINER_PORT_FOOOCUS \
  -e CMDARGS="--listen" \
  -e DATADIR=/content/data \
  -e config_path=/content/data/config.txt \
  -e config_example_path=/content/data/config_modification_tutorial.txt \
  -e path_checkpoints=/content/data/models/checkpoints/ \
  -e path_loras=/content/data/models/loras/ \
  -e path_embeddings=/content/data/models/embeddings/ \
  -e path_vae_approx=/content/data/models/vae_approx/ \
  -e path_upscale_models=/content/data/models/upscale_models/ \
  -e path_inpaint=/content/data/models/inpaint/ \
  -e path_controlnet=/content/data/models/controlnet/ \
  -e path_clip_vision=/content/data/models/clip_vision/ \
  -e path_fooocus_expansion=/content/data/models/prompt_expansion/fooocus_expansion/ \
  -e path_outputs=/content/app/outputs/ \
  $IMAGE_NAME_FOOOCUS

# Kokoro FastAPI (GPU)
if sudo docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME_KOKORO\$"; then
  sudo docker rm -f $CONTAINER_NAME_KOKORO
fi
log "🚀 Avvio container $CONTAINER_NAME_KOKORO..."
sudo docker run -d \
  --gpus all \
  --name $CONTAINER_NAME_KOKORO \
  --restart always \
  -p $HOST_PORT_KOKORO:$CONTAINER_PORT_KOKORO \
  $IMAGE_NAME_KOKORO

# MusicGPT (CPU)
if sudo docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME_MUSIC_GPT\$"; then
  sudo docker rm -f $CONTAINER_NAME_MUSIC_GPT
fi
log "🚀 Avvio container $CONTAINER_NAME_MUSIC_GPT..."
sudo docker run -d \
  --name $CONTAINER_NAME_MUSIC_GPT \
  --restart always \
  -p $HOST_PORT_MUSIC_GPT:$CONTAINER_PORT_MUSIC_GPT \
  $IMAGE_NAME_MUSIC_GPT \
  --ui-expose

# -------------------------------------------------------------------------
# 🌐 INFO ACCESSO
# -------------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')
log "🎉 Tutti i container avviati!"

echo "-----------------------------------------------------"
echo "Fooocus UI: http://$IP:$HOST_PORT_FOOOCUS"       # 7865
echo "Fooocus API: http://$IP:$HOST_PORT_FOOOCUS_API" # 8888
echo "Kokoro FastAPI UI (/web): http://$IP:$HOST_PORT_KOKORO/web"   # 8880
echo "Kokoro FastAPI API (/docs): http://$IP:$HOST_PORT_KOKORO_API/docs" # 8880
echo "MusicGPT UI: http://$IP:$HOST_PORT_MUSIC_GPT"  # 7860
echo "Ollama Web UI: http://$IP:$HOST_PORT_OLLAMA_UI" # 8080
echo "Ollama API: http://$IP:$HOST_PORT_OLLAMA_API"   # 11434
echo "-----------------------------------------------------"