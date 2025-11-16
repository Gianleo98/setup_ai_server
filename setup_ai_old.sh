# # -----------------------------
# # 🎯 CONFIGURAZIONE COMFYUI + WAN 2.2
# # -----------------------------
# COMFY_REPO="$USER_HOME/ComfyUI"  # percorso repository ComfyUI
# VENV_DIR="$COMFY_REPO/venv"
# WAN_DIR="$COMFY_REPO/WAN2.2"

# log "🖼️ Configurazione ComfyUI + WAN 2.2"

# # 1️⃣ Clonazione ComfyUI se non presente
# if [ ! -d "$COMFY_REPO/.git" ]; then
#     echo "📥 Clonazione ComfyUI..."
#     git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_REPO"
# else
#     echo "🔄 Repository ComfyUI già presente, aggiorno..."
#     cd "$COMFY_REPO"
#     git pull
# fi

# # 2️⃣ Creazione e attivazione virtualenv
# python3 -m venv "$VENV_DIR"
# source "$VENV_DIR/bin/activate"
# echo "🔹 Virtualenv attivato"

# # 3️⃣ Installazione PyTorch + CUDA
# pip install --upgrade pip
# pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# # 4️⃣ Installazione dipendenze ComfyUI
# pip install -r requirements.txt

# # 5️⃣ Clona WAN 2.2 usando il token (se necessario)
# GITHUB_TOKEN=$(cat "$USER_HOME/.github_token")
# if [ ! -d "$WAN_DIR" ]; then
#     git clone https://$GITHUB_TOKEN@github.com/Wan-Video/Wan2.2.git "$WAN_DIR"
# else
#     echo "🔄 WAN 2.2 già presente, aggiorno..."
#     cd "$WAN_DIR"
#     git pull
# fi

# # 6️⃣ Copia cartella 'wan' in ComfyUI
# if [ -d "$WAN_DIR/wan" ]; then
#     mkdir -p "$COMFY_REPO/wan"
#     cp -r "$WAN_DIR/wan/." "$COMFY_REPO/wan/"
#     echo "✅ Cartella WAN copiata in ComfyUI"
# else
#     echo "⚠️ Nessuna cartella 'wan' trovata in WAN2.2"
# fi

# # 7️⃣ Copia esempi (opzionale)
# if [ -d "$WAN_DIR/examples" ]; then
#     mkdir -p "$COMFY_REPO/examples"
#     cp -r "$WAN_DIR/examples/." "$COMFY_REPO/examples/"
#     echo "✅ Esempi WAN copiati in ComfyUI"
# fi

# # 8️⃣ Avvio ComfyUI
# cd "$COMFY_REPO"
# nohup python main.py --listen --port 8188 > "$COMFY_REPO/comfyui_wan.log" 2>&1 &
# log "✅ ComfyUI + WAN 2.2 avviato su http://<server>:8188"

# # -------------------------------------------------------------------------
# # 🔧 SERVIZIO SYSTEMD PER AVVIO AUTOMATICO COMFYUI
# # -------------------------------------------------------------------------

# log "🔧 Creazione servizio systemd per ComfyUI..."

# # Determina l'utente reale
# if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
#   REAL_USER="$SUDO_USER"
# else
#   REAL_USER="$USER"
# fi

# REAL_HOME=$(eval echo ~"$REAL_USER")

# SERVICE_PATH="/etc/systemd/system/comfyui.service"

# sudo bash -c "cat > $SERVICE_PATH" <<EOF
# [Unit]
# Description=ComfyUI Service
# After=network.target

# [Service]
# Type=simple
# User=$REAL_USER
# WorkingDirectory=$REAL_HOME/ComfyUI
# ExecStart=$REAL_HOME/ComfyUI/venv/bin/python main.py --listen --port 8188
# Restart=always
# RestartSec=5

# [Install]
# WantedBy=multi-user.target
# EOF

# log "📦 Servizio comfyui.service creato."

# # Abilita il linger per permettere all'utente di eseguire servizi al boot
# sudo loginctl enable-linger "$REAL_USER"

# # Ricarica systemd + abilita + avvia
# sudo systemctl daemon-reload
# sudo systemctl enable comfyui.service
# sudo systemctl restart comfyui.service

# log "✅ Servizio ComfyUI installato e attivo."
# log "🌐 ComfyUI partirà automaticamente al prossimo riavvio su http://<server>:8188"


# # ----------------------------
# # 1️⃣ Installa Python 3.10 se non presente
# # ----------------------------
# if ! command -v python3.10 &>/dev/null; then
#     log "🔹 Aggiungo PPA deadsnakes e installo Python 3.10..."
#     sudo apt update
#     sudo apt install -y software-properties-common
#     sudo add-apt-repository -y ppa:deadsnakes/ppa
#     sudo apt update
#     sudo apt install -y python3.10 python3.10-dev python3.10-distutils python3.10-venv python3-pip build-essential
# else
#     log "✅ Python 3.10 già installato"
# fi

# # ----------------------------
# # 2️⃣ Clona o aggiorna repository Wan2GP
# # ----------------------------
# cd ~
# if [ ! -d "Wan2GP" ]; then
#     log "🔽 Clono repository Wan2GP..."
#     git clone https://github.com/deepbeepmeep/Wan2GP.git
# else
#     log "🔄 Repository Wan2GP già presente, faccio pull..."
#     cd Wan2GP
#     git pull
# fi
# cd ~/Wan2GP

# # ----------------------------
# # 3️⃣ Crea ambiente virtuale solo se non esiste
# # ----------------------------
# if [ ! -d "venv" ]; then
#     log "📦 Creo ambiente virtuale..."
#     python3.10 -m venv venv
# else
#     log "✅ Ambiente virtuale già presente"
# fi

# # Attiva virtualenv con check
# if [ -f "venv/bin/activate" ]; then
#     source venv/bin/activate
# else
#     log "❌ Ambiente virtuale non trovato"
#     exit 1
# fi

# # ----------------------------
# # 4️⃣ Aggiorna pip/setuptools/wheel
# # ----------------------------
# log "⬆️ Aggiorno pip, setuptools e wheel..."
# pip install --upgrade pip setuptools wheel

# # ----------------------------
# # 5️⃣ Installa PyTorch solo se non presente
# # ----------------------------
# if ! python -c "import torch" &>/dev/null; then
#     log "⬇️ Installazione PyTorch compatibile con RTX 2060 e CUDA 11.7..."
#     pip install torch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 --index-url https://download.pytorch.org/whl/cu117
# else
#     log "✅ PyTorch già installato"
# fi

# # ----------------------------
# # 6️⃣ Installa dipendenze Wan2GP solo se non presenti
# # ----------------------------
# REQ_FILE="requirements.txt"
# if ! python -c "import rembg, pymatting" &>/dev/null; then
#     log "⬇️ Installazione dipendenze di Wan2GP..."
#     pip install -r $REQ_FILE
# else
#     log "✅ Dipendenze Wan2GP già installate"
# fi

# # ----------------------------
# # 7️⃣ Avvia Wan2GP solo se porta 7860 libera
# # ----------------------------
# PORT=7860
# if ! ss -tulnp | grep -q ":$PORT"; then
#     log "🚀 Avvio Wan2GP sulla porta $PORT per la rete locale..."
#     nohup python wgp.py --host 0.0.0.0 --port $PORT > ~/Wan2GP/wan2gp.log 2>&1 &
#     log "✅ Wan2GP avviato: http://<server>:$PORT"
# else
#     log "⚠️ Porta $PORT già in uso. Controlla eventuali processi Python attivi"
# fi

# log "🌐 Wan2GP disponibile: http://<server>:7860"

# # -------------------------------------------------------------------------  
# # 🔄 Servizio systemd per avvio automatico (rete locale)  
# # -------------------------------------------------------------------------  
# REAL_USER="${SUDO_USER:-$USER}"  
# REAL_HOME=$(eval echo ~"$REAL_USER")  

# SERVICE_PATH="/etc/systemd/system/wan2gp.service"  

# log "🔧 Creazione servizio systemd wan2gp.service..."  

# sudo bash -c "cat > ${SERVICE_PATH}" <<EOF
# [Unit]
# Description=Wan2GP Service
# After=network.target

# [Service]
# Type=simple
# User=${REAL_USER}
# WorkingDirectory=${REAL_HOME}/Wan2GP
# ExecStart=${REAL_HOME}/Wan2GP/venv/bin/python ${REAL_HOME}/Wan2GP/wgp.py --host 0.0.0.0 --port 7860
# Restart=always
# RestartSec=5

# [Install]
# WantedBy=multi-user.target
# EOF

# log "📌 Abilito e avvio il servizio..."  
# sudo systemctl daemon-reload  
# sudo systemctl enable wan2gp.service  
# sudo systemctl restart wan2gp.service  

# log "✅ Servizio Wan2GP installato e attivo sulla rete locale."

# # -----------------------------------------------------------
# # 🧩 Installazione NVIDIA Container Toolkit (con controlli)
# # -----------------------------------------------------------

# log "🔍 Verifico installazione NVIDIA Container Toolkit..."

# # 1️⃣ Verifica se già installato
# if dpkg -l | grep -q "^ii  nvidia-container-toolkit "; then
#     log "✅ NVIDIA Container Toolkit già installato. Salto installazione."
# else
#     log "🔹 Aggiungo repository NVIDIA Container Toolkit (solo se assente)..."

#     if [ ! -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg ]; then
#         sudo apt-get update
#         sudo apt-get install -y --no-install-recommends curl gnupg2

#         curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
#           sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
#     else
#         log "🔑 Keyring NVIDIA già presente, salto."
#     fi

#     if [ ! -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]; then
#         curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
#           sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
#           sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
#     else
#         log "📦 Repository NVIDIA Container Toolkit già configurato."
#     fi

#     log "🔄 Aggiorno pacchetti..."
#     sudo apt-get update

#     log "🛠️ Installo NVIDIA Container Toolkit..."
#     sudo apt-get install -y nvidia-container-toolkit
# fi


# # 2️⃣ Verifica configurazione Docker runtime NVIDIA
# log "🔍 Verifico configurazione runtime NVIDIA in Docker..."

# if grep -q '"default-runtime": "nvidia"' /etc/docker/daemon.json 2>/dev/null; then
#     log "✅ Docker è già configurato per usare il runtime NVIDIA. Nessuna modifica."
# else
#     log "⚙️ Configuro Docker per usare runtime NVIDIA..."
#     sudo nvidia-ctk runtime configure --runtime=docker
#     RUNTIME_CHANGED=true
# fi


# # 3️⃣ Riavvio Docker solo se necessario
# if [ "$RUNTIME_CHANGED" = true ]; then
#     log "🔄 Riavvio Docker..."
#     sudo systemctl restart docker
# else
#     log "⏩ Docker non necessita riavvio."
# fi

# log "🎉 NVIDIA Container Toolkit pronto."


# # -------------------------------------------------------------------------
# # 🐋 Clona Wan2GP e avvia script ufficiale Docker
# # -------------------------------------------------------------------------
# WAN_DIR="$USER_HOME/Wan2GP"

# if [ ! -d "$WAN_DIR" ]; then
#     log "📥 Clonazione Wan2GP..."
#     git clone https://github.com/deepbeepmeep/Wan2GP.git "$WAN_DIR"
#     cd "$WAN_DIR"
# else
#     log "🔄 Wan2GP già presente, aggiorno..."
#     cd "$WAN_DIR" && git pull
# fi

# # -------------------------------------------------------------------------
# # 🔹 Esegui script ufficiale Docker (solo build)
# # -------------------------------------------------------------------------
# log "🚀 Costruzione immagine Wan2GP tramite script ufficiale Docker..."
# sudo bash run-docker-cuda-deb.sh --host 0.0.0.0 --port 7860

# # -------------------------------------------------------------------------
# # 🔹 Ferma eventuali container esistenti
# # -------------------------------------------------------------------------
# log "🛑 Rimuovo eventuali container Wan2GP già in esecuzione..."
# sudo docker rm -f wan2gp 2>/dev/null || true

# # -------------------------------------------------------------------------
# # 🔹 Avvia il container manualmente con variabili e rete locale
# # -------------------------------------------------------------------------
# log "🐋 Avvio Wan2GP con NUMBA_DISABLE_JITCACHE=1 e rete locale..."
# sudo docker run -d --name wan2gp \
#   -p 7860:7860 \
#   -e NUMBA_DISABLE_JITCACHE=1 \
#   --gpus all \
#   deepbeepmeep/wan2gp \
#   --host 0.0.0.0 --port 7860

# # -------------------------------------------------------------------------
# # 🔹 Output stato
# # -------------------------------------------------------------------------
# log "✅ Wan2GP avviato."
# log "🌐 Accessibile sulla rete locale: http://<IP_DEL_SERVER>:7860"
# log "📌 Auto-avvio al riavvio garantito tramite Docker --restart=always"

# # ----------------------------
# # Dipendenze pyenv
# # ----------------------------
# log "🔧 Verifica dipendenze PyEnv..."
# DEPENDENCIES=(
#     make build-essential libssl-dev zlib1g-dev libbz2-dev
#     libreadline-dev libsqlite3-dev curl libncursesw5-dev
#     xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev git
# )

# for pkg in "${DEPENDENCIES[@]}"; do
#     if dpkg -s "$pkg" &>/dev/null; then
#         log "✅ Pacchetto $pkg già installato."
#     else
#         log "⬇️ Installazione pacchetto $pkg..."
#         sudo apt install -y "$pkg"
#     fi
# done

# # ----------------------------
# # Installazione pyenv solo se non presente
# # ----------------------------
# if ! command -v pyenv &>/dev/null; then
#     if [ ! -d "$USER_HOME/.pyenv" ]; then
#         log "📦 Installazione PyEnv"
#         curl https://pyenv.run | bash
#     else
#         log "⚠️ PyEnv già presente in $USER_HOME/.pyenv ma non nel PATH, configuro..."
#     fi
# else
#     log "✅ PyEnv già installato e disponibile nel PATH"
# fi

# # Aggiorno PATH e inizializzo pyenv
# export PATH="$USER_HOME/.pyenv/bin:$PATH"
# eval "$(pyenv init -)"
# eval "$(pyenv virtualenv-init -)"

# # ----------------------------
# # Python 3.10.13
# # ----------------------------
# if ! pyenv versions | grep -q "3.10.13"; then
#     log "⬇️ Installazione Python 3.10.13..."
#     pyenv install 3.10.13
# fi

# # ----------------------------
# # Clone Fooocus
# # ----------------------------
# if [ ! -d "$USER_HOME/Fooocus" ]; then
#     log "🔽 Clono repository Fooocus"
#     git clone https://github.com/lllyasviel/Fooocus.git
#     cd "$USER_HOME/Fooocus"
# else
#     log "🔄 Pull aggiornamenti Fooocus"
#     cd "$USER_HOME/Fooocus"
#     git pull
# fi

# python3 -m venv fooocus_env
# source fooocus_env/bin/activate
# pip install -r requirements_versions.txt

# # ----------------------------
# # Avvio Fooocus in background con nohup
# # ----------------------------
# log "🚀 Avvio Fooocus in background"

# nohup python entry_with_update.py --listen > "$USER_HOME/Fooocus/fooocus.log" 2>&1 &

# log "🎉 Fooocus avviato in background!"
# log "📄 Log file: $USER_HOME/Fooocus/fooocus.log"

# # -------------------------------------------------------------------------
# # 🔁 SERVIZIO SYSTEMD PER AVVIARE FOOOCUS AL REBOOT
# # -------------------------------------------------------------------------
# log "🛠️ Creazione servizio systemd per Fooocus..."

# # Script launcher eseguibile
# sudo bash -c "cat > /usr/local/bin/start_fooocus.sh <<EOF
# #!/bin/bash
# cd \"$USER_HOME/Fooocus\"
# source \"$USER_HOME/Fooocus/fooocus_env/bin/activate\"
# nohup python entry_with_update.py --listen > \"$USER_HOME/Fooocus/fooocus.log\" 2>&1 &
# EOF"

# sudo chmod +x /usr/local/bin/start_fooocus.sh

# # Determina l'utente reale per systemd
# if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
#   FOOOCUS_USER="$SUDO_USER"
# else
#   FOOOCUS_USER=$(whoami)
# fi

# # Servizio systemd
# sudo bash -c "cat > /etc/systemd/system/fooocus.service <<EOF
# [Unit]
# Description=Fooocus Stable Diffusion WebUI
# After=network.target

# [Service]
# Type=simple
# User=$FOOOCUS_USER
# WorkingDirectory=$USER_HOME/Fooocus
# ExecStart=/usr/local/bin/start_fooocus.sh
# Restart=always
# RestartSec=10

# [Install]
# WantedBy=multi-user.target
# EOF"

# # Ricarica systemd e abilita servizio
# sudo systemctl daemon-reload
# sudo systemctl enable fooocus.service
# sudo systemctl restart fooocus.service

# log '🎉 Servizio Fooocus installato e avviato!'
# echo '--------------------------------------------------------'
# echo "Fooocus sarà avviato automaticamente a ogni reboot."
# echo "👉 URL: http://$(hostname -I | awk '{print $1}'):7865"
# echo '--------------------------------------------------------'