#!/bin/bash

set -euo pipefail

BASE_DIR="/opt/homeassist"
APP_DIR="$BASE_DIR/Homeassist-Archive"
VENV_DIR="$BASE_DIR/.venv"
ENV_FILE="$BASE_DIR/postgres-login.env"
LOG_DIR="$BASE_DIR/logs"
INCOMING_DIR="$BASE_DIR/incoming"
ARCHIVE_DIR="$BASE_DIR/archive"
SSH_DIR="$BASE_DIR/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
CRON_FILE="/etc/cron.daily/homeassist-archive"

REPO_URL="https://github.com/JPT77/Homeassist-Archive.git"

HA_USER="${HA_USER:-root}"
HA_SERVER="${HA_SERVER:-homeassistant}"

echo "==> Homeassist Archive installation"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please run this script as root."
    exit 1
fi

echo "==> Creating user and directories"

if ! id homeassist >/dev/null 2>&1; then
    useradd --system --create-home \
    --home-dir "$BASE_DIR" \
    --shell /usr/sbin/nologin \
    homeassist
fi

mkdir -p -v "$BASE_DIR" "$INCOMING_DIR" "$ARCHIVE_DIR" "$LOG_DIR" "$SSH_DIR"

chown -R -v homeassist:homeassist "$BASE_DIR"

chmod -v 700 "$SSH_DIR"

echo "==> Creating SSH key"

if [[ ! -f "$SSH_KEY" ]]; then
    sudo -u homeassist ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "homeassist-archive"

    chmod -v 600 "$SSH_KEY"
    chmod -v 644 "$SSH_KEY.pub"

    echo
    echo "The SSH public key needs to be installed on Home Assistant."
    echo "You will be asked by SSH for the password of ${HA_USER}@${HA_SERVER}."
    echo

    if ssh-copy-id -i "$SSH_KEY.pub" "${HA_USER}@${HA_SERVER}"; then
        echo
        echo "SSH public key successfully installed on Home Assistant."
    else
        echo
        echo "ERROR: Could not install the SSH public key automatically."
        echo
        echo "Please add the following public key manually to:"
        echo " ${HA_USER}@${HA_SERVER}:~/.ssh/authorized_keys"
        echo cat "$SSH_KEY.pub"
        echo
        echo "For example:"
        echo " ssh ${HA_USER}@${HA_SERVER}"
        echo " mkdir -p ~/.ssh"
        echo " chmod 700 ~/.ssh"
        echo " nano ~/.ssh/authorized_keys"
        echo " chmod 600 ~/.ssh/authorized_keys"
        echo
        exit 1
    fi
    echo
else
    echo " SSH key already exists - keeping it."
fi

echo "==> Checking application directory"

if [[ ! -d "$APP_DIR/.git" ]]; then
    if [[ -d "$APP_DIR" && -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        echo "ERROR: $APP_DIR already exists and is not a Git repository."
        echo "       Please remove it or clone the repository manually."
        exit 1
    fi

    sudo -u homeassist git clone "$REPO_URL" "$APP_DIR"
else
    echo "    Git repository already exists."
fi

chown -R -v homeassist:homeassist "$APP_DIR"

echo "==> Creating Python virtual environment"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    sudo -u homeassist python3 -m venv "$VENV_DIR"
fi

echo "==> Installing Python dependencies"

sudo -u homeassist "$VENV_DIR/bin/python" -m pip install --upgrade pip

sudo -u homeassist "$VENV_DIR/bin/pip" install -r "$APP_DIR/requirements.txt"

echo "==> Creating configuration"

if [[ ! -f "$ENV_FILE" ]]; then
    cat > "$ENV_FILE" <<'EOF'

# PostgreSQL configuration

PG_USER=homeassist
PG_HOST=localhost
PG_PW=CHANGE_ME
EOF

    chmod 600 "$ENV_FILE"
    chown root:root "$ENV_FILE"

    echo
    echo "WARNING: Please edit:"
    echo "  $ENV_FILE"
    echo
    echo "Set PG_PW to the PostgreSQL password before running the importer."
else
    echo "    Configuration already exists - keeping it."
fi

echo "==> Installing daily cron job"

if [[ ! -f "$APP_DIR/cron/homeassist-archive" ]]; then
    echo "ERROR: Cron file not found:"
    echo "  $APP_DIR/cron/homeassist-archive"
    exit 1
fi

install -o root -g root -m 0750 "$APP_DIR/cron/homeassist-archive" "$CRON_FILE"

echo "==> Installation complete"
echo
echo "Application: $APP_DIR"
echo "Virtualenv:  $VENV_DIR"
echo "Incoming:   $INCOMING_DIR"
echo "Archive:    $ARCHIVE_DIR"
echo "Logs:       $LOG_DIR"
echo "Config:     $ENV_FILE"
echo "Cron:       $CRON_FILE"
echo
echo "Next steps:"
echo "  1. Add the SSH public key above to Home Assistant."
echo "  2. Edit $ENV_FILE"
echo "  3. Configure PostgreSQL"
echo "  4. Test the importer manually"
echo
echo "Manual test:"
echo "  sudo -u homeassist $VENV_DIR/bin/python $APP_DIR/fetchhomeassist.py"
