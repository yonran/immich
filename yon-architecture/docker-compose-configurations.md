# Docker Compose Configuration Variants

This document explains the differences between Immich's docker-compose configurations and how our setup deviates from the standard approach.

## Standard Immich Configurations

### `docker-compose.yml` (Production)
**Architecture**: Single-container web + API server
- **Container**: `immich-server` serves both web UI and API on port `2283`
- **Web UI**: Built and copied into server container at `/build/www` 
- **Static serving**: Uses `sirv` middleware for precompressed assets and caching
- **SSR**: Server-side rendering handled by the same NestJS process
- **Image**: `ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}`

### `docker-compose.dev.yml` (Development)  
**Architecture**: Separate containers for development workflow
- **Web container**: `immich-web` on port `3001:3000` 
- **API container**: `immich-server` on port `2283:2283`
- **Development**: Supports hot reloading, source mounting
- **Image**: Locally built with `['immich-dev']` command

## Key Architectural Differences

### Port Layout
| Configuration | Web UI Port | API Port | Container Count |
|--------------|-------------|----------|-----------------|
| `docker-compose.yml` | `2283` | `2283` | 1 (consolidated) |
| `docker-compose.dev.yml` | `3001` | `2283` | 2 (separate) |

### Request Flow

**Production (`docker-compose.yml`)**:
```
Client → 192.168.29.3:2283 → immich-server container
  ├─ / (web UI) → sirv static files + SSR
  └─ /api/* → NestJS API handlers
```

**Development (`docker-compose.dev.yml`)**:
```  
Client → 192.168.29.3:3001 → immich-web container (Svelte dev server)
Client → 192.168.29.3:2283 → immich-server container (API only)
```

## Our Network Setup Deviations

### WireGuard Integration
- **Standard setup**: Direct host network access
- **Our setup**: Access via WireGuard tunnel (`192.168.29.3`)
- **MTU considerations**: Required `mtu = 1280` due to path MTU limitations between AT&T SF and Comcast Seattle (empirically tested max: 1368 bytes)

### Firewall Configuration  
- **Standard expectation**: Manual firewall rules for published ports
- **Our reality**: Docker's automatic iptables integration handles port forwarding
- **No explicit rules needed**: Docker creates DNAT and ACCEPT rules automatically
- **Rule location**: `DOCKER` chain, bypasses main `INPUT` chain

### Database Schema Customizations
- **Custom triggers**: `yon-triggers/` directory contains database triggers for:
  - `yon_auto_add_to_family.sql`: Auto-add WhatsApp images to albums
  - `yon_exclusive_archiving_albums.sql`: Exclusive album membership for document categories
- **Schema evolution**: Triggers require updates during Immich upgrades (e.g., v1.132.3 → v1.137.3 table name changes)

## Lessons Learned

### Network Troubleshooting
1. **MTU blackholes**: Large HTTP responses can hang with default WireGuard MTU (1420)
2. **Path MTU discovery**: Use `ping -D -s <size>` to find actual path limits
3. **TCP vs Application**: Connection success ≠ application success

### Docker Networking
1. **Port publishing**: Docker handles iptables automatically for `-p` flags
2. **No manual firewall rules**: Published ports work through Docker's NAT rules
3. **Interface agnostic**: Works through VPN tunnels without additional config

### Development vs Production
1. **Architecture changes**: Single container vs separate containers affects debugging
2. **Port consolidation**: Production serves web + API on same port
3. **Static asset serving**: Different mechanisms (dev server vs sirv)

### Database Maintenance
1. **Custom triggers**: Require manual updates during schema migrations
2. **Table naming changes**: v1.137.3 standardized plural → singular table names
3. **Migration awareness**: Custom database objects not handled by automatic migrations

## Configuration Files
- **Production**: `docker/.env` with `IMMICH_HOST=0.0.0.0` for external access
- **Network**: NixOS `configuration.nix` with WireGuard MTU settings
- **Database**: Custom triggers in `yon-triggers/` requiring schema updates