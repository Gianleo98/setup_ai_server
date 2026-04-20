#!/bin/bash
set -e

log() { echo -e "\033[1;32m$1\033[0m"; }

# -------------------------------------------------------------------------
# VARIABILI
# -------------------------------------------------------------------------
STATIC_IP="192.168.1.70"
GATEWAY="192.168.1.1"
DNS="8.8.8.8 1.1.1.1"
INTERFACE="ens160"                    # ← Cambia se necessario (controlla con: ip -brief link)

# Porte
PORT_COMFYUI=8188
PORT_KOKORO=8880

# -------------------------------------------------------------------------
# IP STATICO
# -------------------------------------------------------------------------
log "🌐 Configurazione IP statico $STATIC_IP..."

sudo bash -c "cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: false
      addresses: [$STATIC_IP/24]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS]
EOF"

sudo netplan generate && sudo netplan apply
log "✅ IP statico configurato"

# -------------------------------------------------------------------------
# AGGIORNAMENTO SISTEMA + DIPENDENZE
# -------------------------------------------------------------------------
log "🚀 Aggiornamento sistema..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl git net-tools

# -------------------------------------------------------------------------
# NVIDIA + CUDA + SSH + NO SLEEP
# -------------------------------------------------------------------------
log "🧠 Driver NVIDIA e CUDA..."
if ! command -v nvidia-smi &>/dev/null; then
  sudo ubuntu-drivers autoinstall
fi
sudo apt install -y nvidia-cuda-toolkit

log "💤 Disattivazione sospensione..."
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

log "🔐 SSH..."
sudo apt install -y openssh-server
sudo systemctl enable --now ssh

# -------------------------------------------------------------------------
# OLLAMA + MODELLO
# -------------------------------------------------------------------------
log "🧠 Ollama + Qwen3.5 9B..."
if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
ExecStart=/usr/local/bin/ollama serve
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_DEVICE=gpu"
Environment="OLLAMA_USE_CUDA=1"
EOF'

sudo systemctl daemon-reload
sudo systemctl restart ollama
sleep 5

ollama pull qwen3.5:9b-q4_K_M

# -------------------------------------------------------------------------
# DOCKER
# -------------------------------------------------------------------------
log "🐋 Docker..."
if ! command -v docker &>/dev/null; then
  sudo apt install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  sudo usermod -aG docker ${SUDO_USER:-$USER}
fi

# -------------------------------------------------------------------------
# CONTAINER: ComfyUI (volatile) + Kokoro TTS (volatile)
# -------------------------------------------------------------------------

# ComfyUI - senza volumi persistenti per output (solo modelli se vuoi, ma qui li rendiamo temporanei)
sudo docker rm -f comfyui-gpu 2>/dev/null || true
log "🚀 Avvio ComfyUI (output volatile)..."
sudo docker run -d \
  --gpus all \
  --name comfyui-gpu \
  --restart always \
  -p $PORT_COMFYUI:8188 \
  ghcr.io/ai-dock/comfyui:latest-cuda

# Kokoro TTS - volatile (nessun volume)
sudo docker rm -f kokoro-fastapi-gpu 2>/dev/null || true
log "🚀 Avvio Kokoro TTS (output volatile)..."
sudo docker run -d \
  --gpus all \
  --name kokoro-fastapi-gpu \
  --restart always \
  -p $PORT_KOKORO:8880 \
  ghcr.io/remsky/kokoro-fastapi-gpu:latest

# -------------------------------------------------------------------------
# OPENCLAW + CONFIGURAZIONE
# -------------------------------------------------------------------------
log "🦾 Installazione e configurazione OpenClaw..."
if ! command -v openclaw &>/dev/null; then
  ollama launch openclaw --model qwen3.5:9b-q4_K_M --non-interactive --accept-risk
fi

log "🔗 Collegamento tool a OpenClaw..."
openclaw skills install comfyui
openclaw config set tools.image.provider comfyui
openclaw config set tools.image.comfyui.baseUrl "http://127.0.0.1:8188"

openclaw skills install kokoro-tts
openclaw config set tools.tts.provider kokoro
openclaw config set tools.tts.kokoro.baseUrl "http://127.0.0.1:8880"

log "🎉 Setup completato!"

# -------------------------------------------------------------------------
# INFO FINALI
# -------------------------------------------------------------------------
echo "-----------------------------------------------------"
echo "IP del server:          $STATIC_IP"
echo "ComfyUI (Immagini)  →  http://$STATIC_IP:$PORT_COMFYUI"
echo "Kokoro TTS          →  http://$STATIC_IP:$PORT_KOKORO"
echo "OpenClaw            →  http://$STATIC_IP:3000"
echo "-----------------------------------------------------"
echo "Nota importante:"
echo "- Solo la workspace di OpenClaw è persistente"
echo "- Immagini e audio generati sono volatili (si perdono al riavvio del container)"
echo "-----------------------------------------------------"