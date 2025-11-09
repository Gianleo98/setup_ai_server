#!/bin/bash
# sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Gianleo98/setup_ai_server/refs/heads/master/setup_ai.sh)"
# sudo bash -c "$(curl -fsSL https://bit.ly/janraion_omen_ai)"
set -e  # Ferma lo script in caso di errore

log() { echo -e "\033[1;32m$1\033[0m"; }

# -------------------------------------------------------------------------
# 🚀 AGGIORNAMENTO SISTEMA
# -------------------------------------------------------------------------
log "🚀 Aggiornamento pacchetti..."
sudo apt update -y && sudo apt upgrade -y

# -------------------------------------------------------------------------
# 🔐 CONFIGURAZIONE SSH (senza firewall)
# -------------------------------------------------------------------------
log "🔐 Verifica e configurazione SSH..."

# Installa OpenSSH Server se non presente
if dpkg -l | grep -q openssh-server; then
  log "✅ OpenSSH Server già installato."
else
  log "🛠️ Installazione OpenSSH Server..."
  sudo apt install -y openssh-server
fi

# Abilita e avvia il servizio SSH
sudo systemctl enable ssh
sudo systemctl start ssh

# Controlla che SSH sia effettivamente in ascolto
if sudo ss -tlnp | grep -q ":22"; then
  log "✅ SSH attivo e in ascolto sulla porta 22."
else
  log "⚠️ SSH non sembra attivo. Riavvio del servizio..."
  sudo systemctl restart ssh
  sleep 2
  if sudo ss -tlnp | grep -q ":22"; then
    log "✅ SSH attivo dopo riavvio."
  else
    log "❌ Errore: SSH non è in ascolto sulla porta 22."
  fi
fi

# -------------------------------------------------------------------------
# 🧠 DRIVER NVIDIA + CUDA
# -------------------------------------------------------------------------
log "🧠 Verifica driver NVIDIA..."
if command -v nvidia-smi &>/dev/null; then
  log "✅ Driver NVIDIA già installato."
else
  log "🛠️ Installazione driver NVIDIA..."
  sudo ubuntu-drivers autoinstall
fi

log "🎯 Verifica toolkit CUDA..."
if dpkg -l | grep -q nvidia-cuda-toolkit; then
  log "✅ CUDA Toolkit già installato."
else
  log "🛠️ Installazione CUDA Toolkit..."
  sudo apt install -y nvidia-cuda-toolkit
fi

# -------------------------------------------------------------------------
# 🌐 CONFIGURAZIONE RETE WI-FI (sicura per SSH)
# -------------------------------------------------------------------------
# if [ -n "$SSH_CONNECTION" ]; then
#   log "⚠️ Connessione SSH attiva — salto configurazione rete per evitare disconnessione."
# else
#   if ! grep -q "192.168.1.70" /etc/netplan/50-cloud-init.yaml 2>/dev/null; then
#     log "🌐 Configurazione rete Wi-Fi..."
#     sudo bash -c 'cat > /etc/netplan/50-cloud-init.yaml <<EOF
# network:
#   version: 2
#   wifis:
#     wlo1:
#       dhcp4: false
#       addresses:
#         - 192.168.1.70/24
#       nameservers:
#         addresses:
#           - 8.8.8.8
#           - 8.8.4.4
#       routes:
#         - to: 0.0.0.0/0
#           via: 192.168.1.1
#       access-points:
#         "TP-Link_FC88":
#           auth:
#             key-management: "psk"
#             password: "41954959"
# EOF'
#     sudo netplan apply
#   else
#     log "✅ Configurazione rete già presente."
#   fi
# fi

# -------------------------------------------------------------------------
# 💤 NO SLEEP
# -------------------------------------------------------------------------
log "💤 Disattivazione sospensione automatica..."
sudo sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# -------------------------------------------------------------------------
# 💾 ESPANSIONE LVM
# -------------------------------------------------------------------------
log "💾 Espansione partizione LVM..."
sudo partprobe || true
sudo pvresize /dev/sda3 || true
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv || true
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv || true

# -------------------------------------------------------------------------
# 🔄 VERIFICA E CARICAMENTO MODULI NVIDIA (con attesa)
# -------------------------------------------------------------------------
log "🔄 Verifica moduli NVIDIA..."
MODULES="nvidia nvidia_uvm nvidia_modeset"

for mod in $MODULES; do
  if lsmod | grep -wq "$mod"; then
    log "✅ Modulo $mod già caricato."
  else
    log "📦 Carico modulo $mod..."
    sudo modprobe $mod || true
  fi
done

# Attendi che i moduli siano completamente inizializzati
log "⏳ Attesa inizializzazione driver NVIDIA..."
sleep 5

# Tenta di verificare il driver più volte prima di forzare il riavvio
MAX_RETRIES=5
for i in $(seq 1 $MAX_RETRIES); do
  if nvidia-smi &>/dev/null; then
    log "✅ Driver NVIDIA attivo."
    DRIVER_OK=true
    break
  else
    log "⏳ Tentativo $i/$MAX_RETRIES: driver non ancora pronto..."
    sleep 3
  fi
done

if [ "$DRIVER_OK" != true ]; then
  log "⚠️ Driver NVIDIA non attivo dopo vari tentativi, riavvio necessario."
  sudo reboot
  exit 0
fi


# -------------------------------------------------------------------------
# 🧠 INSTALLAZIONE OLLAMA
# -------------------------------------------------------------------------
log "🧠 Verifica installazione Ollama..."

INSTALL_OLLAMA=false

# 1️⃣ Verifica se il binario esiste
if ! command -v ollama &>/dev/null; then
  INSTALL_OLLAMA=true
else
  # 2️⃣ Verifica che il servizio Ollama risponda
  if ! curl -fs http://127.0.0.1:11434/api/version &>/dev/null; then
    log "⚠️ Ollama installato ma non attivo. Reinstallazione..."
    INSTALL_OLLAMA=true
  fi
fi

# 3️⃣ Se necessario, installa Ollama
if [ "$INSTALL_OLLAMA" = true ]; then
  log "🛠️ Installazione Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

# -------------------------------------------------------------------------
# ⚙️ CONFIGURAZIONE OLLAMA GPU
# -------------------------------------------------------------------------
log "⚙️ Configurazione Ollama per GPU..."
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

# 4️⃣ Attesa avvio Ollama
log "⏳ Attesa avvio servizio Ollama..."
for i in {1..10}; do
  if curl -fs http://127.0.0.1:11434/api/version &>/dev/null; then
    log "✅ Ollama attivo e funzionante."
    break
  else
    log "⏳ Tentativo $i/10: Ollama non ancora pronto..."
    sleep 3
  fi
done

if ! curl -fs http://127.0.0.1:11434/api/version &>/dev/null; then
  log "❌ Errore: Ollama non è riuscito ad avviarsi correttamente."
  exit 1
fi

# -------------------------------------------------------------------------
# ⬇️ MODELLO
# -------------------------------------------------------------------------
if ! ollama list | grep -q llama3.2; then
  log "⬇️ Download modello Ollama llama3.2..."
  ollama pull llama3.2:latest
else
  log "✅ Modello llama3.2 già scaricato."
fi

# -------------------------------------------------------------------------
# 🐋 DOCKER + OPEN WEBUI
# -------------------------------------------------------------------------
log "🐋 Verifica Docker..."
if command -v docker &>/dev/null; then
  log "✅ Docker già installato."
else
  log "🛠️ Installazione Docker..."
  sudo apt install -y ca-certificates curl gnupg lsb-release
  sudo mkdir -p /etc/apt/keyrings

  # Rimuovi la chiave se già esiste per evitare prompt
  sudo rm -f /etc/apt/keyrings/docker.gpg

  # Scarica e installa la chiave in modo silenzioso
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

  # Aggiungi il repository Docker
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Aggiorna pacchetti e installa Docker
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
fi

if sudo docker ps -a --format '{{.Names}}' | grep -q open-webui; then
  log "✅ Contenitore Open WebUI già presente."
else
  log "🌐 Avvio Open WebUI collegato a Ollama..."
  sudo docker run -d --network=host -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
    --name open-webui --restart always \
    ghcr.io/open-webui/open-webui:main
fi


# -------------------------------------------------------------------------
# 🐍 PYENV
# -------------------------------------------------------------------------
log "🐍 Verifica Pyenv..."
if [ -d "$HOME/.pyenv" ]; then
  log "✅ Pyenv già installato."
else
  log "🛠️ Installazione Pyenv..."
  sudo apt install -y make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev git
  curl https://pyenv.run | bash
  echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
  echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
  echo 'eval "$(pyenv init - bash)"' >> ~/.bashrc
fi

# -------------------------------------------------------------------------
# 🖼️ STABLE DIFFUSION
# -------------------------------------------------------------------------
log "🖼️ Verifica Stable Diffusion..."
if [ -d "/home/ubuntu/stable-diffusion-webui" ]; then
  log "✅ Stable Diffusion già presente."
else
  log "🛠️ Installazione Stable Diffusion..."
  cd /home/ubu
  git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
  cd stable-diffusion-webui
  ./webui.sh --exit
fi

if ! crontab -l | grep -q "stable-diffusion-webui"; then
  log "⚙️ Configurazione avvio automatico Stable Diffusion..."
  (crontab -l 2>/dev/null; echo '@reboot cd /home/ubuntu/stable-diffusion-webui && ./webui.sh --listen --api --port 7860 >> /home/ubuntu/webui.log 2>&1') | crontab -
else
  log "✅ Avvio automatico Stable Diffusion già configurato."
fi

# -------------------------------------------------------------------------
# 🎬 INSTALLAZIONE WAN 2.2 + SERVER REST API
# -------------------------------------------------------------------------
log "🎬 Verifica installazione Wan 2.2..."

WAN_DIR="/opt/wan2.2"
WAN_MODEL_DIR="$WAN_DIR/Wan2.2-T2V-A14B"
WAN_SERVICE="/etc/systemd/system/wan-api.service"

# 1️⃣ Verifica se Wan 2.2 è già installato
if [ -d "$WAN_DIR" ]; then
  log "✅ Wan 2.2 già installato in $WAN_DIR."
else
  log "🛠️ Installazione Wan 2.2..."
  sudo git clone https://github.com/Wan-Video/Wan2.2.git "$WAN_DIR"
fi

# 2️⃣ Installazione dipendenze Python se necessario
log "🧠 Verifica dipendenze Python per Wan 2.2..."
REQUIRED_PKGS=("python3" "python3-pip" "git")
for pkg in "${REQUIRED_PKGS[@]}"; do
  if dpkg -l | grep -qw "$pkg"; then
    log "✅ Pacchetto $pkg già installato."
  else
    log "🛠️ Installazione $pkg..."
    sudo apt install -y "$pkg"
  fi
done

# 3️⃣ Verifica librerie Python (torch, fastapi, ecc.)
log "📦 Verifica librerie Python..."
PY_LIBS=(torch torchvision torchaudio xformers fastapi uvicorn pydantic huggingface_hub)
for lib in "${PY_LIBS[@]}"; do
  if python3 -m pip show "$lib" &>/dev/null; then
    log "✅ Libreria Python $lib già installata."
  else
    log "🛠️ Installazione libreria $lib..."
    pip install "$lib" --extra-index-url https://download.pytorch.org/whl/cu121 || true
  fi
done

# Installa le requirements del progetto
if [ -f "$WAN_DIR/requirements.txt" ]; then
  log "📘 Installazione requirements Wan 2.2..."
  pip install -r "$WAN_DIR/requirements.txt"
else
  log "⚠️ File requirements.txt non trovato, salto."
fi

# 4️⃣ Scarica il modello se non presente
if [ -d "$WAN_MODEL_DIR" ]; then
  log "✅ Modello Wan 2.2 già scaricato."
else
  log "⬇️ Download modello Wan 2.2 T2V-A14B..."
  pip install "huggingface_hub[cli]" || true
  huggingface-cli download Wan-Video/Wan2.2-T2V-A14B --local-dir "$WAN_MODEL_DIR" || log "⚠️ Download fallito, verifica token HuggingFace."
fi

# 5️⃣ Creazione server REST API se non già presente
WAN_API_FILE="$WAN_DIR/wan_api.py"
if [ -f "$WAN_API_FILE" ]; then
  log "✅ Script API Wan già presente."
else
  log "🧩 Creazione script REST API Wan..."
  sudo bash -c "cat > $WAN_API_FILE <<'EOF'
from fastapi import FastAPI
from pydantic import BaseModel
import subprocess, uuid, os

app = FastAPI()

class GenerateRequest(BaseModel):
    prompt: str
    size: str = "480*270"
    task: str = "t2v-A14B"
    offload_model: bool = True

@app.post("/generate")
def generate_video(req: GenerateRequest):
    output_id = str(uuid.uuid4())[:8]
    output_path = f"output_{output_id}.mp4"
    cmd = [
        "python3", "generate.py",
        "--task", req.task,
        "--ckpt_dir", "./Wan2.2-T2V-A14B",
        "--prompt", req.prompt,
        "--size", req.size,
        "--offload_model", str(req.offload_model),
        "--convert_model_dtype",
        "--output", output_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if os.path.exists(output_path):
        return {"status": "success", "output": output_path}
    else:
        return {"status": "error", "details": result.stderr}
EOF"
fi

# 6️⃣ Creazione servizio systemd (solo se non esiste)
if [ -f "$WAN_SERVICE" ]; then
  log "✅ Servizio wan-api già configurato."
else
  log "🧩 Creazione servizio systemd wan-api..."
  sudo bash -c "cat > $WAN_SERVICE <<EOF
[Unit]
Description=WAN 2.2 REST API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WAN_DIR
ExecStart=/usr/bin/python3 -m uvicorn wan_api:app --host 0.0.0.0 --port 8500
Restart=always
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF"
  sudo systemctl daemon-reload
  sudo systemctl enable wan-api.service
  log "✅ Servizio wan-api abilitato all'avvio."
fi

# 7️⃣ Avvio (o riavvio) del servizio
if systemctl is-active --quiet wan-api.service; then
  log "🔄 Riavvio servizio wan-api..."
  sudo systemctl restart wan-api.service
else
  log "▶️ Avvio servizio wan-api..."
  sudo systemctl start wan-api.service
fi

# 8️⃣ Verifica
sleep 5
if curl -fs http://127.0.0.1:8500/docs &>/dev/null; then
  log "✅ Servizio Wan API attivo su http://<server>:8500"
else
  log "⚠️ Wan API non risponde, controlla con: journalctl -u wan-api -f"
fi


# -------------------------------------------------------------------------
# 🔁 REBOOT FINALE
# -------------------------------------------------------------------------
log "✅ Setup completato. Riavvio per applicare le modifiche..."
sudo reboot
