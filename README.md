# AmneziaWG 3.0 Easy (AWG 3.0)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](LICENSE)
[![AmneziaWG Protocol](https://img.shields.io/badge/AmneziaWG-v3.0-orange.svg)](https://github.com/amnezia-vpn/amneziawg-go)
[![Docker Multi-Arch](https://img.shields.io/badge/Docker-amd64%20%7C%20arm64-blue)](build-and-push.sh)

Modern, lightweight Web UI and VPN server with native **AmneziaWG 3.0 (AWG 3.0)** DPI-resistant obfuscation and standard **WireGuard** support.

---

## Key Features & AmneziaWG 3.0 Support

- **Full AmneziaWG 3.0 Protocol Implementation**:
  - **Dynamic Header Ranges (`H1–H4`)**: Define randomized packet type header ranges (e.g. `123456-123500`) or concrete uint32 values to prevent signature-based DPI classification.
  - **Message Padding (`S1–S4`)**: Random padding for Handshake Initiation, Response, Cookie, and Transport packets.
  - **Junk Packets (`Jc`, `Jmin`, `Jmax`)**: Pre-handshake noise injection to disrupt packet timing and size analysis.
  - **Custom Protocol Signatures (CPS `I1–I5`)**: Imitate legitimate protocols (such as DNS-over-UDP, TLS/QUIC, and WebRTC/STUN) using `<b 0xHEX...>`, `<r N>`, and `<t>` tags.
- **Built-in Obfuscation Presets**:
  - **DNS Query Mimic**: Masks handshake traffic under standard DNS UDP queries.
  - **QUIC / HTTP/3 Handshake Mimic**: Simulates modern QUIC protocol connection opening.
  - **STUN Binding Request Mimic**: Bypasses restrictive enterprise firewalls by mimicking VoIP/WebRTC traffic.
  - **Standard AWG 3.0**: Dynamic random header ranges and standard padding.
  - **Clean WireGuard**: Zero-overhead standard WireGuard for trusted networks.
- **Per-Client Granular Configuration**: Each client can inherit server parameters or define custom junk packets and CPS signatures.
- **Client Compatibility**: Fully compatible with the official **AmneziaVPN Client (v5.0.0.5+)**, AmneziaWG for Android/iOS/Windows/macOS/Linux, and standard WireGuard clients.
- **Automated Diagnostics & Management**: Web-based Path MTU calculation and presets, kernel module installer, Docker health checks, and Nginx Proxy Manager SSL.

---

## Quick Start & Server Diagnostics

The repository includes `server-check.sh` and built-in Web Admin diagnostics for fast deployment and management:

```bash
# 1. (Optional) Install native DKMS kernel module for Ubuntu, Debian, RHEL/CentOS, Fedora, Arch, Alpine
sudo ./server-check.sh --install-module

# 2. Start the project with Docker Compose
./server-check.sh --start

# 3. Perform deep health check of container, network interface, and Web UI
./server-check.sh --health
```

---

## Production Deployment with Docker Compose

1. Configure `docker-compose.yml`:

```yaml
services:
  wg-easy:
    image: ${IMAGE_TAG:-shu1t3/wg-eas-awg3:latest}
    container_name: wg-easy
    restart: unless-stopped
    environment:
      - PORT=51821
      - INSECURE=false
      - INIT_ENABLED=true
      - INIT_HOST=vpn.yourdomain.com
      - INIT_PORT=51820
      - INIT_USERNAME=admin
      - INIT_PASSWORD=YourSecurePassword123!
      - INIT_DNS=1.1.1.1,8.8.8.8
      - INIT_IPV4_CIDR=10.8.0.0/24
      - INIT_IPV6_CIDR=fdcc:ad94:bacf:61a3::/64
    volumes:
      - etc_wireguard:/etc/wireguard
      - /lib/modules:/lib/modules:ro
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv6.conf.all.forwarding=1
      - net.ipv6.conf.default.forwarding=1
```

2. Start the container:

```bash
docker compose up -d
```

3. Access the Web Admin Panel at `http://<YOUR_SERVER_IP>:51821` (or via HTTPS reverse proxy).

---

## HTTPS & SSL via Nginx Proxy Manager

A pre-configured **Nginx Proxy Manager** is integrated into `docker-compose.yml` for automated Let's Encrypt SSL certificates:

```bash
# Start Nginx Proxy Manager
./server-check.sh --start-npm

# Check NPM status and view connection instructions
./server-check.sh --npm
```

1. Open Web Admin UI at `http://<YOUR_SERVER_IP>:81` (Default: `admin@example.com` / `changeme`).
2. Add a Proxy Host:
   - **Domain Names:** `vpn.yourdomain.com`
   - **Scheme:** `http`
   - **Forward Hostname / IP:** `wg-easy` (or `10.42.42.42`)
   - **Forward Port:** `51821`
   - **SSL Tab:** Select *Request a new SSL Certificate*, enable *Force SSL* and *HTTP/2 Support*.

---

## Environment Variables Reference

| Variable | Default | Description |
|---|---|---|
| `PORT` | `51821` | Port the Web UI listens on inside the container |
| `HOST` | `0.0.0.0` | Host binding address |
| `INSECURE` | `false` | Set `true` if behind an external reverse proxy (HTTP) |
| `DISABLE_IPV6` | `false` | Disable IPv6 support if not available on host |
| `DISABLE_VERSION_CHECK` | `false` | Disable auto-check for updates |
| `DEBUG` | `Server,WireGuard,Database,CMD,Firewall` | Debug logging namespaces |
| `INIT_ENABLED` | `false` | Set `true` to auto-provision initial admin and network settings |
| `INIT_HOST` | - | Public IP or domain for generated client profiles |
| `INIT_PORT` | `51820` | AmneziaWG UDP port used by clients |
| `INIT_USERNAME` | `admin` | Initial admin username |
| `INIT_PASSWORD` | - | Initial admin password |
| `INIT_DNS` | `1.1.1.1,8.8.8.8` | DNS servers pushed to clients |
| `INIT_IPV4_CIDR` | `10.8.0.0/24` | VPN IPv4 subnet |
| `INIT_IPV6_CIDR` | `fdcc:ad94:bacf:61a3::/64` | VPN IPv6 subnet |
| `INIT_ALLOWED_IPS` | `0.0.0.0/0, ::/0` | Allowed IPs for client configurations |
| `INIT_MTU` | `1420` | MTU for WireGuard interface & client configs (or configure via Web UI) |
| `DISABLE_PASSWORD_AUTH` | `false` | Disable local password login (for OAuth only) |
| `OAUTH_PROVIDERS` | - | Comma-separated: `google,github,oidc` |
| `OAUTH_ALLOWED_DOMAINS`| - | Allowed email domains (e.g. `example.com`) |
| `OAUTH_AUTO_REGISTER` | `false` | Auto-register users logging in via OAuth |
| `OAUTH_AUTO_LAUNCH` | - | Provider name to auto-redirect login |

---

## Development & Multi-Arch Build

### Run Development Server
```bash
pnpm dev
```

### Build & Deploy Multi-Arch Docker Image (`linux/amd64`, `linux/arm64`)
```bash
# Build for all architectures and push manifest list
./build-and-push.sh

# Quick local build for current machine architecture only
./build-and-push.sh --local

# Build specific version tag
./build-and-push.sh --tag v1.0.0
```

---

## License

This project is licensed under the AGPL-3.0 License - see the [LICENSE](LICENSE) file for details.
