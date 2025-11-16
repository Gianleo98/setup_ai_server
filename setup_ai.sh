#!/bin/bash
# sudo bash -c "$(curl -fsSL https://bit.ly/janraion_omen_ai)"
# curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/Gianleo98/setup_ai_server/refs/heads/master/setup_ai.sh?$(date +%s)" | sudo bash
set -e  # Ferma lo script in caso di errore

log() { echo -e "\033[1;32m$1\033[0m"; }

# -------------------------------------------------------------------------
# 🚀 AGGIORNAMENTO SISTEMA
# -------------------------------------------------------------------------
log "🚀 Aggiornamento pacchetti..."
sudo apt update -y && sudo apt upgrade -y

# -------------------------------------------------------------------------
# 🏠 RILEVAZIONE HOME UTENTE REALE
# -------------------------------------------------------------------------
# Se eseguito con sudo, ricava la home dell'utente originale
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
  USER_HOME=$(eval echo ~"$SUDO_USER")
else
  USER_HOME="$HOME"
fi

log "🏠 Home utente rilevata: $USER_HOME"


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
log "💾 Verifica e espansione partizione LVM..."

# Verifica se il device esiste
if [ -b /dev/sda3 ]; then
    log "💾 Device /dev/sda3 trovato, procedo con ridimensionamento..."
    sudo partprobe || true
    sudo pvresize /dev/sda3 || true
    sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv || true
    sudo resize2fs /dev/ubuntu-vg/ubuntu-lv || true
    log "✅ Espansione LVM completata."
else
    log "⚠️ Device /dev/sda3 non trovato. Salto ridimensionamento LVM."
fi


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
for i in {1..5}; do
  if curl -fs http://127.0.0.1:11434/api/version &>/dev/null; then
    log "✅ Ollama attivo e funzionante."
    break
  else
    log "⏳ Tentativo $i/5: Ollama non ancora pronto..."
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


# ----------------------------
# Installa Miniconda se non presente
# ----------------------------
if ! command -v conda &>/dev/null; then
    log "🔽 Scarico e installo Miniconda..."
    wget -O ~/miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash ~/miniconda.sh -b -p $HOME/miniconda3

    # Aggiungi Miniconda al PATH nel profilo shell
    echo 'export PATH="$HOME/miniconda3/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/miniconda3/bin:$PATH"

    log "✅ Miniconda installata"
else
    log "✅ Miniconda già installata"
fi

# ----------------------------
# Clona repository Fooocus
# ----------------------------
cd ~
if [ ! -d "Fooocus" ]; then
    log "🔽 Clono repository Fooocus..."
    git clone https://github.com/lllyasviel/Fooocus.git
else
    log "🔄 Repository Fooocus già presente, faccio pull..."
    cd Fooocus
    git pull
fi
cd ~/Fooocus

# ----------------------------
# Crea ambiente Conda fooocus
# ----------------------------
if ! conda env list | grep -q "fooocus"; then
    log "📦 Creo ambiente Conda fooocus e accetto Terms of Service automaticamente..."
    yes | conda env create -f environment.yaml
else
    log "✅ Ambiente Conda fooocus già presente"
fi

# ----------------------------
# Attiva ambiente e installa dipendenze aggiuntive
# ----------------------------
eval "$(conda shell.bash hook)"
conda activate fooocus

log "⬆️ Aggiorno pip, setuptools e wheel dentro ambiente..."
pip install --upgrade pip setuptools wheel

if [ -f "requirements_versions.txt" ]; then
    log "⬇️ Installazione requirements_versions.txt..."
    pip install -r requirements_versions.txt
fi

# ----------------------------
# Avvio Fooocus con porta in ascolto sulla rete locale
# ----------------------------
log "🚀 Avvio Fooocus in ascolto sulla rete locale..."
nohup python entry_with_update.py --listen > ~/Fooocus/fooocus.log 2>&1 &

log "✅ Fooocus avviato. Accessibile su http://<IP_SERVER>:7860"


# -------------------------------------------------------------------------
# 🔁 REBOOT FINALE
# -------------------------------------------------------------------------
# log "✅ Setup completato. Riavvio per applicare le modifiche..."
# sudo reboot
