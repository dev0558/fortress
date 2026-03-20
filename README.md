# FORTRESS

Defense in Depth cybersecurity portfolio project. A four-zone network segmentation lab demonstrating enterprise-grade security architecture.

## Architecture

```
EXTERNAL --[rate-limit]--> DMZ (10.10.1.0/24) --[allow]--> APP (10.10.2.0/24) --[allow]--> DATA (10.10.3.0/24)
                               |                                                                |
                               +--- DENY --->  ADMIN (10.10.4.0/24) <--- ALLOW all zones ---+
```

### Zones

| Zone | Subnet | Services | Purpose |
|------|--------|----------|---------|
| DMZ | 10.10.1.0/24 | Nginx, fail2ban | Reverse proxy, rate limiting |
| APP | 10.10.2.0/24 | Flask API, Gunicorn | JWT auth, RBAC enforcement |
| DATA | 10.10.3.0/24 | PostgreSQL, pgcrypto | Encrypted data at rest |
| ADMIN | 10.10.4.0/24 | Monitoring, SSH | Administrative access |

### RBAC Roles

| Role | read:users | read:notes | write:notes | read:status |
|------|-----------|-----------|------------|------------|
| admin | Y | Y | Y | Y |
| analyst | Y | Y | Y | - |
| readonly | Y | - | - | Y |

## Quick Start

```bash
# Clone and start
git clone <repo-url> fortress && cd fortress

# Copy env and configure
cp .env.example .env
# Edit .env with your secrets

# Build and run
docker compose up --build -d

# Verify zone segmentation
bash scripts/verify_segmentation.sh

# Apply hardening rules
sudo bash scripts/harden.sh --all
```

## UI Dashboard

### Opening the Dashboard

Open `fortress-v2.html` in any modern browser. When served via Docker:

```bash
docker compose up --build -d
open http://localhost:8080/fortress-v2.html
```

For local development without Docker, open the file directly. The dashboard uses demo/mock auth and a local RBAC policy fallback when the API is unavailable.

### Login Credentials (Demo)

| Username | Password | Role |
|----------|----------|------|
| admin | admin | admin |
| analyst | analyst | analyst |
| readonly | readonly | readonly |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `R` | Run RBAC policy check |
| `L` | Clear audit log |
| `1`-`4` | Select zone (DMZ, APP, DATA, ADMIN) |
| `S` | Toggle sidebar collapsed/expanded |

### Screenshot

![FORTRESS Dashboard](docs/screenshots/dashboard.png)

### Regenerating Assets with nano-banana

The zone icons, logo, and background were designed for generation via [nano-banana-2-skill](https://github.com/kingbootoshi/nano-banana-2-skill). To regenerate:

```bash
# Install nano-banana
git clone https://github.com/kingbootoshi/nano-banana-2-skill ~/.claude/plugins/nano-banana-2-skill
cd ~/.claude/plugins/nano-banana-2-skill && npm install

# Set your Gemini API key
export GEMINI_API_KEY=<your-key-from-aistudio.google.com>

# Generate background
nano-banana "dark military tactical operations room background, deep navy blue, subtle amber targeting reticle grid lines, minimal, no text, UI background texture" -s 2K -a 16:9 -o bg-tactical -d docker/nginx/static

# Generate zone icons
nano-banana "military network zone shield icon, minimal flat design, dark theme, single color amber, no background" -t -s 1K -o icon-dmz -d docker/nginx/static
nano-banana "server rack icon, minimal flat design, single color green, no background" -t -s 1K -o icon-app -d docker/nginx/static
nano-banana "database cylinder icon, minimal flat design, single color cyan, no background" -t -s 1K -o icon-data -d docker/nginx/static
nano-banana "command terminal icon, minimal flat design, single color blue, no background" -t -s 1K -o icon-admin -d docker/nginx/static

# Generate logo
nano-banana "FORTRESS wordmark logo, military stencil font, amber color, dark transparent background, clean vector-style, no decorations" -t -s 1K -a 4:1 -o logo-fortress -d docker/nginx/static
```

### Regenerating Screen Designs with Stitch MCP

[Google Stitch MCP](https://github.com/nichochar/stitch-mcp) can generate high-fidelity screen designs for FORTRESS.

```bash
# Install Stitch MCP proxy
npx @_davideast/stitch-mcp init

# After OAuth authentication, use these prompts in Claude Code:

# Dashboard screen
# "Design a military-grade cybersecurity operations dashboard. Dark background #050709.
#  Four network zone cards, metrics row, traffic policy matrix, live audit log,
#  RBAC policy tester, role permissions table, fail2ban bans list.
#  JetBrains Mono font, amber primary accent, hacker terminal aesthetic."

# Login screen
# "Military terminal login screen for FORTRESS. CRT scanlines, ASCII logo,
#  amber/green accents, JetBrains Mono, dark background."
```

## API Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | None | Health check |
| POST | `/api/auth/login` | None | Get JWT token |
| GET | `/api/users` | read:users | List users |
| GET | `/api/notes` | read:notes | List notes |
| POST | `/api/notes` | write:notes | Create note |
| GET | `/api/status` | read:status | System status |
| POST | `/api/rbac/check` | read:status | RBAC policy tester |

## Infrastructure

### Terraform

The `terraform/` directory mirrors the Docker Compose setup using the kreuzwerker/docker provider across three modules:

- `modules/network` - Four isolated Docker bridge networks
- `modules/services` - Container definitions (nginx, flask, postgres)
- `modules/firewall` - iptables rules for zone isolation

### Hardening

```bash
# Apply all hardening rules (iptables + nftables + fail2ban)
sudo bash scripts/harden.sh --all

# Verify zone segmentation (7 tests)
bash scripts/verify_segmentation.sh
```

## Security Constraints

- All containers run as non-root with `cap_drop: ALL`
- No secrets in version control (`.env`, `terraform.tfvars` are gitignored)
- JWT tokens with expiry for API auth
- Rate limiting at the reverse proxy layer
- fail2ban for brute-force protection
- pgcrypto for data encryption at rest

## License

See [LICENSE](LICENSE).
