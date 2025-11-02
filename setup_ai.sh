#!/bin/bash
set -e  # Ferma lo script in caso di errore

STATE_FILE="/var/tmp/setup_state"

# Funzione per aggiornare lo stato
set_state() {
  echo "$1" > "$STATE_FILE"
}

# Funzione per aggiungere l'auto-esecuzione dopo reboot
enable_autorun() {
  (crontab -l 2>/dev/null; echo "@reboot bash $(realpath $0)") | crontab -
}

# Funzione per rimuovere l'auto-esecuzione dopo completamento
disable_autorun() {
  crontab -l | grep -v "$(realpath $0)" | crontab -
  rm -f "$STATE_FILE"
}

# Controlla in che stato si trova
STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "start")

if [ "$STATE" = "start" ]; then
  echo "🚀 [FASE 1] Aggiornamento pacchetti..."
  sudo apt update && sudo apt upgrade -y

  echo "🧠 [FASE 1] Installazione driver Nvidia e CUDA..."
  sudo ubuntu-drivers autoinstall
  sudo apt install nvidia-cuda-toolkit -y

  echo "📡 [FASE 1] Installazione Speedtest CLI..."
  sudo apt install speedtest-cli -y

  echo "🌐 [FASE 1] Configurazione rete Wi-Fi..."
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

  echo "💤 [FASE 1] Disattivazione sospensione automatica..."
  sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
  sudo sed -i 's/^#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
  sudo systemctl restart systemd-logind

  echo "💾 [FASE 1] Espansione partizione LVM..."
  sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv || true
  sudo resize2fs /dev/ubuntu-vg/ubuntu-lv || true

  echo "🔁 Riavvio necessario per completare l'installazione NVIDIA..."
  set_state "post_reboot"
  enable_autorun
  sudo reboot
  exit 0
fi

if [ "$STATE" = "post_reboot" ]; then
  echo "🔁 [FASE 2] Sistema riavviato, continuo da qui..."

  echo "🧠 [FASE 2] Installazione Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh

  echo "⚙️ [FASE 2] Configurazione Ollama per GPU..."
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/ollama serve
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_DEVICE=gpu"
Environment="OLLAMA_USE_CUDA=1"
Environment="CUDA_VISIBLE_DEVICES=0"
EOF'

  sudo systemctl daemon-reexec
  sudo systemctl daemon-reload
  sudo systemctl restart ollama

  echo "⬇️ [FASE 2] Download modelli Ollama..."
  ollama pull llama3.2:latest

  echo "🐋 [FASE 2] Installazione Docker..."
  sudo apt install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io

  echo "🌐 [FASE 2] Avvio Open WebUI collegato a Ollama..."
  sudo docker run -d --network=host -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
    --name open-webui --restart always \
    ghcr.io/open-webui/open-webui:main

  echo "🐍 [FASE 2] Installazione Pyenv..."
  sudo apt install -y make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev git
  curl https://pyenv.run | bash
  echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
  echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
  echo 'eval "$(pyenv init - bash)"' >> ~/.bashrc

  echo "🖼️ [FASE 2] Installazione Stable Diffusion AUTOMATIC1111..."
  cd /home/ubuntu
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
  cd stable-diffusion-webui
  ./webui.sh --exit

  echo "⚙️ [FASE 2] Configurazione avvio automatico Stable Diffusion..."
  (crontab -l 2>/dev/null; echo '@reboot cd /home/ubuntu/stable-diffusion-webui && ./webui.sh --listen --api --port 7860 >> /home/ubuntu/webui.log 2>&1') | crontab -

  disable_autorun
  echo "✅ Installazione completata. Tutto pronto!"
fi
