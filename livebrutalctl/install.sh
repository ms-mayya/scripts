#!/usr/bin/env bash
set -euo pipefail

# Install TCP Brutal
bash <(curl -fsSL https://tcp.hy2.sh/)

# Install grpcurl
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y jq

os="linux"
arch=$(dpkg --print-architecture)
package_suffix=".deb"
package_install="dpkg -i"

latest_release=$(curl -s https://api.github.com/repos/fullstorydev/grpcurl/releases/latest)
download_version=$(echo "$latest_release" | grep tag_name | head -n 1 | awk -F: '{print $2}' | sed 's/[", v]//g')
package_name="grpcurl_${download_version}_${os}_${arch}${package_suffix}"
package_url="https://github.com/fullstorydev/grpcurl/releases/download/v${download_version}/${package_name}"

echo "Downloading $package_url"
curl --fail -Lo "$package_name" "$package_url"

curl_exit_status=$?
if [ $curl_exit_status -ne 0 ]; then
  exit $curl_exit_status
fi

if command -v sudo >/dev/null 2>&1; then
  package_install="sudo $package_install"
fi

echo "$package_install $package_name"
sh -c "$package_install \"$package_name\""
rm -f "$package_name"

# Create livebrutalctl.sh
cat > /usr/local/bin/livebrutalctl.sh <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

grpcurl -plaintext \
    -H "Authorization: Bearer sing" \
    -d '{"interval":3600000}' \
    127.0.0.1:9099 \
    daemon.StartedService/SubscribeConnections |
jq --unbuffered -r '
    .events[]?
    | select(.type == "CONNECTION_EVENT_CLOSED")
    | .connection.source // empty
' |
while IFS= read -r src; do
    ip="${src%:*}"
    [[ -n "$ip" ]] || continue
    brutalctl add "$ip" 100
done
EOF

chmod +x /usr/local/bin/livebrutalctl.sh

# Install systemd service
cat > /etc/systemd/system/livebrutalctl.service <<EOF
[Unit]
Description=Live Brutalctl IP Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/livebrutalctl.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now livebrutalctl.service
