#!/bin/bash
set -e

log() { echo -e "\033[1;32m$1\033[0m"; }

# -------------------------------------------------------------------------
# VARIABILI PRINCIPALI
# -------------------------------------------------------------------------
STATIC_IP="192.168.1.70"
GATEWAY="192.168.1.1"
DNS="8.8.8.8 1.1.1.1"
INTERFACE="ens160"                    # ← Controlla con: ip -brief link

# Container
CONTAINER_COMFYUI="comfyui-gpu"
CONTAINER_KOKORO="kokoro-fastapi-gpu"

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
log "✅ IP statico configurato su $STATIC_IP"

# -------------------------------------------------------------------------
# AGGIORNAMENTO SISTEMA
# -------------------------------------------------------------------------
log "🚀 Aggiornamento sistema..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl git net-tools

# -------------------------------------------------------------------------
# NVIDIA + CUDA + SSH + NO SLEEP
# -------------------------------------------------------------------------
log "🧠 Installazione driver NVIDIA e CUDA..."
if ! command -v nvidia-smi &>/dev/null; then
  sudo ubuntu-drivers autoinstall
fi
sudo apt install -y nvidia-cuda-toolkit

log "💤 Disattivazione sospensione automatica..."
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

log "🔐 Abilitazione SSH..."
sudo apt install -y openssh-server
sudo systemctl enable --now ssh

# -------------------------------------------------------------------------
# OLLAMA + MODELLO CONSIGLIATO
# -------------------------------------------------------------------------
log "🧠 Installazione Ollama..."
if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

log "⚙️ Configurazione Ollama per GPU..."
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

log "⬇️ Download modello Qwen3.5 9B (ottimizzato per RTX 2060 6GB)..."
ollama pull qwen3.5:9b-q4_K_M

# -------------------------------------------------------------------------
# DOCKER
# -------------------------------------------------------------------------
log "🐋 Installazione Docker..."
if ! command -v docker &>/dev/null; then
  sudo apt install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
  sudo usermod -aG docker ${SUDO_USER:-$USER}
fi

# -------------------------------------------------------------------------
# CONTAINER: ComfyUI + Kokoro TTS
# -------------------------------------------------------------------------

# ComfyUI
sudo docker rm -f $CONTAINER_COMFYUI 2>/dev/null || true
log "🚀 Avvio ComfyUI (generazione immagini)..."
sudo docker run -d \
  --gpus all \
  --name $CONTAINER_COMFYUI \
  --restart always \
  -p $PORT_COMFYUI:8188 \
  -v comfyui-models:/opt/ComfyUI/models \
  -v comfyui-output:/opt/ComfyUI/output \
  -v comfyui-input:/opt/ComfyUI/input \
  ghcr.io/ai-dock/comfyui:latest-cuda

# Kokoro TTS
sudo docker rm -f $CONTAINER_KOKORO 2>/dev/null || true
log "🚀 Avvio Kokoro TTS (voice-over)..."
sudo docker run -d \
  --gpus all \
  --name $CONTAINER_KOKORO \
  --restart always \
  -p $PORT_KOKORO:8880 \
  ghcr.io/remsky/kokoro-fastapi-gpu:latest

# -------------------------------------------------------------------------
# OPENCLAW + CONFIGURAZIONE
# -------------------------------------------------------------------------
log "🦾 Installazione OpenClaw..."
if ! command -v openclaw &>/dev/null; then
  ollama launch openclaw --model qwen3.5:9b-q4_K_M --non-interactive --accept-risk
fi

log "🔗 Collegamento ComfyUI a OpenClaw..."
openclaw skills install comfyui
openclaw config set tools.image.provider comfyui
openclaw config set tools.image.comfyui.baseUrl "http://127.0.0.1:8188"

log "🔊 Collegamento Kokoro TTS a OpenClaw..."
openclaw skills install kokoro-tts
openclaw config set tools.tts.provider kokoro
openclaw config set tools.tts.kokoro.baseUrl "http://127.0.0.1:8880"

log "🎉 Setup completato con successo!"

# -------------------------------------------------------------------------
# INFORMAZIONI FINALI
# -------------------------------------------------------------------------
echo "-----------------------------------------------------"
echo "IP del server:          $STATIC_IP"
echo "ComfyUI (Immagini)  →  http://$STATIC_IP:$PORT_COMFYUI"
echo "Kokoro TTS          →  http://$STATIC_IP:$PORT_KOKORO"
echo "Ollama              →  http://$STATIC_IP:11434"
echo "OpenClaw            →  http://$STATIC_IP:3000   (o la porta configurata)"
echo "Modello LLM         →  qwen3.5:9b-q4_K_M"
echo "-----------------------------------------------------"
echo "Per avviare OpenClaw:   openclaw gateway start"
echo "Per testare immagini:   openclaw test image \"un gatto che balla su TikTok\""