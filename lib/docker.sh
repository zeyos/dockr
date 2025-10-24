#!/usr/bin/env bash

DOCKER_APT_KEYRING=/etc/apt/keyrings/docker.gpg
DOCKER_APT_SOURCE=/etc/apt/sources.list.d/docker.list
DOCKER_DAEMON_CONFIG=/etc/docker/daemon.json
DOCKER_SYSTEMD_OVERRIDE=/etc/systemd/system/docker.service.d/override.conf
DOCKER_CERT_DIR=/root/docker-certs

install_docker_engine() {
  if command_exists docker; then
    log_info "Docker already installed"
    return
  fi

  apt_install_packages ca-certificates curl gnupg lsb-release software-properties-common
  ensure_directory /etc/apt/keyrings 755 root root
  if [[ ! -f "$DOCKER_APT_KEYRING" ]]; then
    log_info "Adding Docker GPG key"
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | gpg --dearmor >/tmp/docker.gpg
    install -m 644 /tmp/docker.gpg "$DOCKER_APT_KEYRING"
    rm -f /tmp/docker.gpg
  fi

  local codename
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  if [[ -z "$codename" ]]; then
    log_fatal "Unable to determine Ubuntu codename"
  fi
  local arch
  arch=$(dpkg --print-architecture)
  local repo_line="deb [arch=$arch signed-by=$DOCKER_APT_KEYRING] https://download.docker.com/linux/ubuntu $codename stable"
  if [[ ! -f "$DOCKER_APT_SOURCE" ]] || ! grep -Fxq "$repo_line" "$DOCKER_APT_SOURCE"; then
    echo "$repo_line" >"$DOCKER_APT_SOURCE"
  fi
  apt_update_once
  apt_install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemd_enable_service docker.service
  systemd_enable_service containerd.service
}

configure_docker_daemon() {
  local tlsverify="$1" remote_api="$2" tcp_port="$3"
  ensure_directory /etc/docker 755 root root

  local hosts_json
  if [[ "$remote_api" == true ]]; then
    hosts_json='["unix:///var/run/docker.sock", "tcp://0.0.0.0:'"$tcp_port"'"]'
  else
    hosts_json='["unix:///var/run/docker.sock"]'
  fi

  local config
  config=$(cat <<JSON
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "tlsverify": $tlsverify,
  "tlscacert": "$DOCKER_CERT_DIR/ca.pem",
  "tlscert": "$DOCKER_CERT_DIR/server-cert.pem",
  "tlskey": "$DOCKER_CERT_DIR/server-key.pem",
  "hosts": $hosts_json
}
JSON
)
  ensure_file_contents "$DOCKER_DAEMON_CONFIG" "$config" 640 root root

  ensure_directory "/etc/systemd/system/docker.service.d" 755 root root
  local override
  override='[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --config-file /etc/docker/daemon.json'
  ensure_file_contents "$DOCKER_SYSTEMD_OVERRIDE" "$override" 644 root root

  systemd_daemon_reload
  systemd_restart_service docker
}

ensure_docker_certificates() {
  local host_name="$1" host_addr="$2" host_domain="$3" client_name="$4" days_valid="$5"
  ensure_directory "$DOCKER_CERT_DIR" 700 root root

  local ca_key="$DOCKER_CERT_DIR/ca-key.pem"
  local ca_cert="$DOCKER_CERT_DIR/ca.pem"
  local server_key="$DOCKER_CERT_DIR/server-key.pem"
  local server_cert="$DOCKER_CERT_DIR/server-cert.pem"
  local client_key="$DOCKER_CERT_DIR/key.pem"
  local client_cert="$DOCKER_CERT_DIR/cert.pem"

  if [[ ! -f "$ca_key" || ! -f "$ca_cert" ]]; then
    log_info "Generating Docker CA"
    openssl genrsa -out "$ca_key" 4096
    openssl req -new -x509 -days "$days_valid" -key "$ca_key" -sha256 -out "$ca_cert" -subj "/C=US/ST=State/L=City/O=dockr/OU=CA/CN=$host_name"
  else
    log_info "Docker CA already exists"
  fi

  local server_ip
  if [[ -n "$host_addr" ]]; then
    server_ip="$host_addr"
  else
    server_ip=$(hostname -I | awk '{print $1}')
  fi
  if [[ ! -f "$server_key" || ! -f "$server_cert" ]]; then
    log_info "Generating Docker server certificate"
    openssl genrsa -out "$server_key" 4096
    local csr="$DOCKER_CERT_DIR/server.csr"
    local ext="$DOCKER_CERT_DIR/server-ext.cnf"
    local sans="IP:$server_ip,IP:127.0.0.1,DNS:localhost"
    if [[ -n "$host_domain" ]]; then
      sans+="\nDNS:$host_domain"
    fi
    printf 'subjectAltName = %s
extendedKeyUsage = serverAuth
' "$sans" >"$ext"
    openssl req -subj "/C=US/ST=State/L=City/O=dockr/OU=Server/CN=$host_name" -new -key "$server_key" -out "$csr"
    openssl x509 -req -days "$days_valid" -sha256 -in "$csr" -CA "$ca_cert" -CAkey "$ca_key" -CAcreateserial -out "$server_cert" -extfile "$ext"
    rm -f "$csr" "$ext"
  else
    log_info "Docker server certificate already exists"
  fi

  if [[ ! -f "$client_key" || ! -f "$client_cert" ]]; then
    log_info "Generating Docker client certificate"
    openssl genrsa -out "$client_key" 4096
    local csr="$DOCKER_CERT_DIR/client.csr"
    local ext="$DOCKER_CERT_DIR/client-ext.cnf"
    printf 'extendedKeyUsage = clientAuth
' >"$ext"
    openssl req -subj "/C=US/ST=State/L=City/O=dockr/OU=Client/CN=$client_name" -new -key "$client_key" -out "$csr"
    openssl x509 -req -days "$days_valid" -sha256 -in "$csr" -CA "$ca_cert" -CAkey "$ca_key" -CAcreateserial -out "$client_cert" -extfile "$ext"
    rm -f "$csr" "$ext"
  else
    log_info "Docker client certificate already exists"
  fi
}

backup_docker_certs() {
  local dest_dir="$1" timestamp="$2"
  ensure_directory "$dest_dir" 700 root root
  local archive="$dest_dir/docker-certs-$timestamp.tar.gz"
  tar -czf "$archive" -C "$DOCKER_CERT_DIR" .
  printf '%s\n' "$archive"
}

