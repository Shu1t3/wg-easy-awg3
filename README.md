# AmneziaWG Easy (AWG)

Web UI & Server with native AmneziaWG 2.0 (AWG) obfuscation and WireGuard support.

## Quick Start & Server Diagnostics

Use the included `server-check.sh` script to verify kernel modules, install the AmneziaWG DKMS kernel module for your Linux distribution, validate Docker sysctls, and healthcheck your deployment:

```bash
# Diagnostic check only
./server-check.sh --check

# Install AmneziaWG kernel module (supports Ubuntu, Debian, RHEL/CentOS, Fedora, Arch, Alpine)
sudo ./server-check.sh --install-module

# Start project & run deep health check
./server-check.sh --start
./server-check.sh --health
```

## Production Deployment with Docker Compose

1. Adjust `docker-compose.yml` to set your desired environment variables:

```yaml
services:
  wg-easy:
    image: shu1t3/wg-eas-awg3:latest
    container_name: wg-easy
    restart: unless-stopped
    environment:
      - PORT=51821
      - INSECURE=false
      - INIT_ENABLED=true
      - INIT_HOST=vpn.yourdomain.com
      - INIT_PORT=51820
      - INIT_USERNAME=admin
      - INIT_PASSWORD=YourStrongPassword123!
```

2. Start the service:

```bash
docker compose up -d
```

3. Access the Web UI at `http://<YOUR_SERVER_IP>:51821` (or your domain).

## Environment Variables Reference

| Variable | Default | Description |
|---|---|---|
| `PORT` | `51821` | Port the Web UI listens on inside the container |
| `HOST` | `0.0.0.0` | Host binding address |
| `INSECURE` | `false` | Set `true` if behind HTTP reverse proxy |
| `DISABLE_IPV6` | `false` | Disable IPv6 support if not available on host |
| `DISABLE_VERSION_CHECK` | `false` | Disable update notifications |
| `DEBUG` | `Server,WireGuard,Database,CMD,Firewall` | Debug logging namespaces |
| `INIT_ENABLED` | `false` | Set `true` to auto-provision on first start |
| `INIT_HOST` | - | Public IP or domain for generated client profiles |
| `INIT_PORT` | `51820` | AmneziaWG UDP port used by clients |
| `INIT_USERNAME` | `admin` | Initial admin username |
| `INIT_PASSWORD` | - | Initial admin password |
| `INIT_DNS` | `1.1.1.1,8.8.8.8` | DNS servers pushed to clients |
| `INIT_IPV4_CIDR` | `10.8.0.0/24` | VPN IPv4 subnet |
| `INIT_IPV6_CIDR` | `fdcc:ad94:bacf:61a3::/64` | VPN IPv6 subnet |
| `INIT_ALLOWED_IPS` | `0.0.0.0/0, ::/0` | Allowed IPs for full tunnel clients |
| `DISABLE_PASSWORD_AUTH` | `false` | Disable local password login (for OAuth only) |
| `OAUTH_PROVIDERS` | - | Comma-separated: `google,github,oidc` |
| `OAUTH_ALLOWED_DOMAINS`| - | Allowed email domains (e.g. `example.com`) |
| `OAUTH_AUTO_REGISTER` | `false` | Auto-register users logging in via OAuth |
| `OAUTH_AUTO_LAUNCH` | - | Provider name to auto-redirect login |

## Development

### Dev Server
```shell
pnpm dev
```

### Dev CLI
```shell
pnpm cli:dev
```

### Build Image
```shell
./build-and-push.sh
```

## License

This project is licensed under the AGPL-3.0 License - see the [LICENSE](LICENSE) file for details.
