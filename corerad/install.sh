#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-eth0}"
BIN=/usr/local/bin/corerad
CONF=/etc/corerad/corerad.toml

apt-get -qq update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get -y -qq install golang-go >/dev/null

tag="$(curl -fsSL https://api.github.com/repos/mdlayher/corerad/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')"
src="$(mktemp -d)"; trap 'rm -rf "$src"' EXIT
curl -fsSL "https://api.github.com/repos/mdlayher/corerad/tarball/$tag" | tar -xz -C "$src" --strip-components=1
( cd "$src" && CGO_ENABLED=0 go build -o "$BIN" ./cmd/corerad )

mkdir -p /etc/corerad
[[ -e "$CONF" ]] || cat > "$CONF" <<EOF
[[interfaces]]
name = "$IFACE"
advertise = true
preference = "high"

  [[interfaces.rdnss]]
EOF

cat > /etc/systemd/system/corerad.service <<EOF
[Unit]
Description=CoreRAD IPv6 NDP RA daemon
Documentation=https://github.com/mdlayher/corerad/blob/main/internal/config/reference.toml
After=network.target

[Service]
Type=notify
ExecStart=$BIN -c=$CONF
Restart=on-failure
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=yes
LimitNOFILE=1048576
RestartKillSignal=SIGHUP

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now corerad
systemctl status corerad
