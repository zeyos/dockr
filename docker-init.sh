#!/bin/bash

# Setup Script for ZeyOS Docker Hosts
# 
# - Installs and configures docker
# - Generate docker certificates and stores them in /root/docker-certs
# - Installs ZeyOS sshkeymgr for hetzner-cloud access
#
# Version 1.00 (Oct. 16 2024)
set -e

# Variables
DOCKER_CERTS_DIR="/root/docker-certs"
CA_KEY="$DOCKER_CERTS_DIR/ca-key.pem"
CA_CERT="$DOCKER_CERTS_DIR/ca.pem"
SERVER_KEY="$DOCKER_CERTS_DIR/server-key.pem"
SERVER_CERT="$DOCKER_CERTS_DIR/server-cert.pem"
CLIENT_KEY="$DOCKER_CERTS_DIR/key.pem"
CLIENT_CERT="$DOCKER_CERTS_DIR/cert.pem"
DOCKER_CONFIG_FILE="/etc/docker/daemon.json"
DOCKER_TCP_PORT=2376

# New Variables for sshkeymgr
SSHKEYMGR_DIR="/opt/sshkeymgr"
SSHKEYMGR_REPO="https://github.com/zeyosinc/sshkeymgr.git"
CRON_JOB_FILE="/etc/cron.d/zeyos-sshkeymgr"
CRON_JOB_CONTENT="# /etc/cron.d/zeyos-sshkeymgr
# Updates the authorized_keys every hour

0 * * * *   root   /opt/sshkeymgr/sshkeymgr.sh zeyon hetzner-cloud >/dev/null 2>&1
"

apt update
apt upgrade

# Function to install Docker if not present
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo usermod -aG docker "$USER"
        echo "Docker installed successfully."
    else
        echo "Docker is already installed."
    fi
}

# Function to install Git if not present
install_git() {
    if ! command -v git &> /dev/null; then
        echo "Git not found. Installing Git..."
        sudo apt-get update
        sudo apt-get install -y git
        echo "Git installed successfully."
    else
        echo "Git is already installed."
    fi
}

# Function to create certificates directory with secure permissions
create_certs_dir() {
    if [ ! -d "$DOCKER_CERTS_DIR" ]; then
        mkdir -p "$DOCKER_CERTS_DIR"
        sudo chmod 700 "$DOCKER_CERTS_DIR"
        sudo chown root:root "$DOCKER_CERTS_DIR" -R
        echo "Created and secured directory $DOCKER_CERTS_DIR for storing certificates."
    else
        echo "Directory $DOCKER_CERTS_DIR already exists. Ensuring it has correct permissions."
        sudo chmod 700 "$DOCKER_CERTS_DIR"
        sudo chown root:root "$DOCKER_CERTS_DIR" -R
    fi
}

# Function to generate CA
generate_ca() {
    if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CERT" ]; then
        echo "Generating CA..."
        # Generate CA key without encryption (no passphrase)
        openssl genrsa -out "$CA_KEY" 4096
        openssl req -new -x509 -days 365 -key "$CA_KEY" -sha256 -out "$CA_CERT" -subj "/C=US/ST=State/L=City/O=Organization/OU=Org/CN=ca"
        echo "CA generated without passphrase."
    else
        echo "CA already exists."
    fi
}

# Function to generate Server Certificates
generate_server_certs() {
    if [ ! -f "$SERVER_KEY" ] || [ ! -f "$SERVER_CERT" ]; then
        echo "Generating Server Key and Certificate..."
        openssl genrsa -out "$SERVER_KEY" 4096

        # Get the server's primary IP address
        SERVER_IP=$(hostname -I | awk '{print $1}')
        echo "Server IP detected as: $SERVER_IP"

        openssl req -subj "/C=DE/ST=Bavaria/L=Munich/O=ZeyOS/OU=Satellites/CN=$(hostname)" -new -key "$SERVER_KEY" -out "$DOCKER_CERTS_DIR/server.csr"

        # Update subjectAltName with the actual IP address and localhost
        echo "subjectAltName = IP:$SERVER_IP,IP:127.0.0.1,DNS:localhost" > "$DOCKER_CERTS_DIR/extfile.cnf"

        openssl x509 -req -days 365 -sha256 -in "$DOCKER_CERTS_DIR/server.csr" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$SERVER_CERT" -extfile "$DOCKER_CERTS_DIR/extfile.cnf"

        rm "$DOCKER_CERTS_DIR/server.csr" "$DOCKER_CERTS_DIR/extfile.cnf"

        echo "Server certificate generated with subjectAltName = IP:$SERVER_IP,IP:127.0.0.1,DNS:localhost."
    else
        echo "Server certificates already exist."
    fi
}

# Function to generate Client Certificates
generate_client_certs() {
    if [ ! -f "$CLIENT_KEY" ] || [ ! -f "$CLIENT_CERT" ]; then
        echo "Generating Client Key and Certificate..."
        openssl genrsa -out "$CLIENT_KEY" 4096
        openssl req -subj "/C=DE/ST=Bavaria/L=Munich/O=ZeyOS/OU=Satellites/CN=gitlab-ci" -new -key "$CLIENT_KEY" -out "$DOCKER_CERTS_DIR/client.csr"
        echo "extendedKeyUsage = clientAuth" > "$DOCKER_CERTS_DIR/client-extfile.cnf"
        openssl x509 -req -days 365 -sha256 -in "$DOCKER_CERTS_DIR/client.csr" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$CLIENT_CERT" -extfile "$DOCKER_CERTS_DIR/client-extfile.cnf"
        rm "$DOCKER_CERTS_DIR/client.csr" "$DOCKER_CERTS_DIR/client-extfile.cnf"
        echo "Client certificate generated."
    else
        echo "Client certificates already exist."
    fi
}

# Function to configure Docker daemon
configure_docker_daemon() {
    echo "Configuring Docker daemon to use TLS..."

    # Create or update daemon.json
    if [ ! -f "$DOCKER_CONFIG_FILE" ]; then
        sudo touch "$DOCKER_CONFIG_FILE"
    fi

    sudo tee "$DOCKER_CONFIG_FILE" > /dev/null <<EOF
{
  "tlsverify": true,
  "tlscacert": "$CA_CERT",
  "tlscert": "$SERVER_CERT",
  "tlskey": "$SERVER_KEY",
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:$DOCKER_TCP_PORT"]
}
EOF

    echo "Docker daemon configured to use TLS on port $DOCKER_TCP_PORT."

    # Validate JSON syntax using jq
    if command -v jq &> /dev/null; then
        if ! sudo jq empty "$DOCKER_CONFIG_FILE" 2>/dev/null; then
            echo "Error: Invalid JSON syntax in $DOCKER_CONFIG_FILE."
            exit 1
        fi
        echo "JSON syntax in $DOCKER_CONFIG_FILE is valid."
    else
        echo "jq not installed; skipping JSON validation."
    fi
}

# Function to override Docker service to remove conflicting flags
override_docker_service() {
    echo "Overriding Docker service to remove conflicting host flags..."

    sudo mkdir -p /etc/systemd/system/docker.service.d

    sudo tee /etc/systemd/system/docker.service.d/override.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --config-file /etc/docker/daemon.json
EOF

    sudo systemctl daemon-reload
    sudo systemctl restart docker

    echo "Docker service overridden successfully."
}

# Function to restart Docker daemon
restart_docker() {
    echo "Restarting Docker daemon..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    echo "Docker daemon restarted."
}

# Function to display certificate locations
display_certs_info() {
    echo "Certificates are stored in $DOCKER_CERTS_DIR:"
    echo " - CA Certificate: $CA_CERT"
    echo " - Client Certificate: $CLIENT_CERT"
    echo " - Client Key: $CLIENT_KEY"
    echo ""
    echo "Use these certificates in your GitLab CI/CD configuration to securely access the Docker daemon."
}

# New Function to set up sshkeymgr
setup_sshkeymgr() {
    if [ ! -d "$SSHKEYMGR_DIR" ]; then
        echo "Directory $SSHKEYMGR_DIR not found. Cloning sshkeymgr repository..."
        sudo git clone "$SSHKEYMGR_REPO" "$SSHKEYMGR_DIR"
        echo "Repository cloned to $SSHKEYMGR_DIR."
    else
        echo "Directory $SSHKEYMGR_DIR already exists. Skipping clone."
    fi

    # Ensure the sshkeymgr.sh script is executable
    sudo chmod +x "$SSHKEYMGR_DIR/sshkeymgr.sh"

    # Create the cron job file if it does not exist
    if [ ! -f "$CRON_JOB_FILE" ]; then
        echo "Creating cron job at $CRON_JOB_FILE..."
        echo "$CRON_JOB_CONTENT" | sudo tee "$CRON_JOB_FILE" > /dev/null
        echo "Cron job created."
    else
        echo "Cron job file $CRON_JOB_FILE already exists. Skipping creation."
    fi

    # Writing the keys
    /opt/sshkeymgr/sshkeymgr.sh zeyon hetzner-cloud
}

# Function to install dependencies
install_dependencies() {
    install_git
    # Add other dependencies here if needed in the future
}

# Main Execution Flow
install_docker
install_dependencies
create_certs_dir
generate_ca
generate_server_certs
generate_client_certs
configure_docker_daemon
override_docker_service
display_certs_info
setup_sshkeymgr

echo "Setup completed successfully."
