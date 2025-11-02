#!/bin/bash
set -e  # Ferma lo script in caso di errore

echo "🚀 Aggiornamento pacchetti..."
sudo apt update && sudo apt upgrade -y

echo "🧠 Installazione driver Nvidia e CUDA..."
sudo ubuntu-drivers autoinstall
sudo apt install -y nvidia-cuda-toolkit

echo "📡 Installazione Speedtest CLI..."
sudo apt install -y speedtest-cli

echo "🌐 Configurazione rete Wi-Fi..."
sudo bash -c 'cat > /etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  wifis:
    wlo1:
      dhcp4: false
      addresses:
        - 192.168.1.70/24
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
      routes:
        - to: 0.0.0.0/0
          via: 192.168.1.1
      access-points:
        "TP-Link_FC88":
          auth:
            key-management: "psk"
            password: "41954959"
EOF'
sudo netplan apply

echo "💤 Disattivazione sospensione automatica..."
sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

echo "💾 Espansione partizione LVM..."
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv || true
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv || true

# -------------------------------------------------------------------------
# 🔄 Ricarico moduli NVIDIA senza reboot (fallback a reboot se necessario)
# -------------------------------------------------------------------------
echo "🔄 Ricarico moduli NVIDIA senza riavvio..."
sudo modprobe -r nouveau || true
sudo modprobe nvidia || true
sudo modprobe nvidia_uvm || true
sudo modprobe nvidia_modeset || true

if nvidia-smi &>/dev/null; then
  echo "✅ Driver NVIDIA attivo senza riavvio."
else
  echo "⚠️ Driver NVIDIA non attivo, riavvio necessario..."
  sudo reboot
  exit 0
fi

# -------------------------------------------------------------------------
# 🧠 Installazione e configurazione Ollama
# -------------------------------------------------------------------------
echo "🧠 Installazione Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

echo "⚙️ Configurazione Ollama per GPU..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Unit]
After=network-online.target nvidia-persistenced.service
Wants=network-online.target nvidia-persistenced.service

[Service]
ExecStart=
ExecStart=/usr/local/bin/ollama serve
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_DEVICE=gpu"
Environment="OLLAMA_USE_CUDA=1"
Environment="CUDA_VISIBLE_DEVICES=0"
Environment="OLLAMA_LLM_LIBRARY=cuda_v11"
Environment="OLLAMA_FLASH_ATTENTION=1"
EOF'

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl restart ollama

echo "⬇️ Download modelli Ollama..."
ollama pull llama3.2:latest

# -------------------------------------------------------------------------
# 🐋 Installazione Docker + Open WebUI
# -------------------------------------------------------------------------
echo "🐋 Installazione Docker..."
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

echo "🌐 Avvio Open WebUI collegato a Ollama..."
sudo docker run -d --network=host -v open-webui:/app/backend/data \
  -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
  --name open-webui --restart always \
  ghcr.io/open-webui/open-webui:main

# -------------------------------------------------------------------------
# 🐍 Installazione Pyenv
# -------------------------------------------------------------------------
echo "🐍 Installazione Pyenv..."
sudo apt install -y make build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
  libffi-dev liblzma-dev git

curl https://pyenv.run | bash

echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init - bash)"' >> ~/.bashrc

# -------------------------------------------------------------------------
# 🖼️ Installazione Stable Diffusion AUTOMATIC1111
# -------------------------------------------------------------------------
echo "🖼️ Installazione Stable Diffusion AUTOMATIC1111..."
cd /home/ubuntu
git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
cd stable-diffusion-webui
./webui.sh --exit

echo "⚙️ Configurazione avvio automatico Stable Diffusion..."
(crontab -l 2>/dev/null; echo '@reboot cd /home/ubuntu/stable-diffusion-webui && ./webui.sh --listen --api --port 7860 >> /home/ubuntu/webui.log 2>&1') | crontab -

# -------------------------------------------------------------------------
# 🔁 Riavvio finale
# -------------------------------------------------------------------------
echo "✅ Installazione completata. Riavvio del sistema per applicare tutto."
sudo reboot
