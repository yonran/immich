# Networking Troubleshooting Guide

This document captures the network debugging process and solutions discovered during the WireGuard + Docker + Immich integration issues.

## Problem: HTTP Requests Hanging After TCP Connection

### Symptoms
- **API endpoints**: Work correctly (`/api/server/ping` returns `{"res":"pong"}`)
- **Web UI**: HTTP requests hang after TCP connection established
- **Connection success**: `curl -v` shows `* Connected to 192.168.29.3 (192.168.29.3) port 2283`
- **Request timeout**: No response received, eventual timeout

### Root Cause Analysis Process

#### Initial Hypothesis: Application Binding Issues
**Tested**: `IMMICH_HOST` environment variable
- **Problem**: When undefined, NestJS defaults to restrictive binding
- **Solution**: Set `IMMICH_HOST=0.0.0.0` in `.env`
- **Result**: Fixed API endpoints, web UI still broken

#### Second Hypothesis: Firewall Rules
**Tested**: iptables and NixOS firewall configuration  
- **Discovery**: Docker automatically manages port forwarding via DNAT rules
- **Evidence**: `sudo iptables -t nat -L DOCKER -n` shows `DNAT tcp dpt:2283 to:172.18.0.5:2283`
- **Result**: Firewall rules unnecessary for Docker-published ports

#### Third Hypothesis: MTU/PMTU Blackhole (CORRECT)
**Discovered by**: Testing different packet sizes
- **Small packets** (HEAD requests): ✅ Work fine  
- **Large packets** (HTML responses): ❌ Hang and timeout
- **Classic signature**: TCP connection succeeds, large data transfers fail

## MTU Investigation and Solution

### Path MTU Discovery
```bash
# Test different packet sizes (data + 28 bytes for IP/ICMP headers)
ping -D -s 1472 192.168.29.3  # 1500 MTU - FAILED
ping -D -s 1362 192.168.29.3  # 1390 MTU - FAILED  
ping -D -s 1340 192.168.29.3  # 1368 MTU - SUCCESS ✅
ping -D -s 1330 192.168.29.3  # 1358 MTU - SUCCESS ✅
ping -D -s 1252 192.168.29.3  # 1280 MTU - SUCCESS ✅
```

**Result**: Maximum path MTU = **1368 bytes** (AT&T SF → Comcast Seattle)

### WireGuard Configuration Fix
**Problem**: WireGuard default MTU (1420) exceeded path MTU (1368)  
**Solution**: Set conservative MTU in NixOS configuration

```nix
networking.wireguard.interfaces = {
  wg0 = {
    # Set MTU to 1280 to avoid PMTU blackhole issues. Path MTU testing shows
    # 1368 bytes max (AT&T SF to Comcast Seattle), but 1280 provides safe margin
    # for WireGuard overhead and is the IPv6 minimum MTU (RFC 8200).
    mtu = 1280;
  };
};
```

**Rationale for 1280**:
- **Safe margin**: Well below 1368 path MTU limit
- **WireGuard overhead**: Accounts for encryption/header overhead
- **Universal compatibility**: IPv6 minimum MTU (RFC 8200)

### Verification Tests
```bash
# Before fix
curl -I 192.168.29.3:2283     # HEAD request - worked
curl 192.168.29.3:2283/       # GET request - hung

# After fix  
curl -I 192.168.29.3:2283     # HEAD request - worked
curl 192.168.29.3:2283/       # GET request - worked ✅
```

## Network Architecture Insights

### Docker Port Forwarding
```bash
# Docker automatically creates these iptables rules:
sudo iptables -t nat -L DOCKER -n
# DNAT tcp dpt:2283 to:172.18.0.5:2283

sudo iptables -L DOCKER -n  
# ACCEPT tcp dpt:2283
```

**Key insight**: Docker-published ports bypass host `INPUT` chain entirely

### WireGuard Traffic Flow
```
Client (laptop) 
  ↓ WireGuard tunnel (192.168.29.7 → 192.168.29.3)
  ↓ MTU limit: 1368 bytes (path-specific)
Host NIC (192.168.29.3:2283)
  ↓ Docker DNAT rule  
  ↓ iptables DOCKER chain
Container (172.18.0.5:2283)
  ↓ NestJS application (IMMICH_HOST=0.0.0.0)
  ↓ Response data > 1368 bytes
  ↓ Packet fragmentation/drop
  ✗ Client timeout
```

### Application Layer Details
**NestJS Binding**:
- `IMMICH_HOST=undefined` → binds to `[::1]` (IPv6 localhost) 
- `IMMICH_HOST=0.0.0.0` → binds to all interfaces ✅

**Static File Serving**:
- Uses `sirv` middleware with compression (gzip/brotli)
- Large HTML responses trigger MTU issues
- Small API responses work fine

## Diagnostic Commands

### Network Testing
```bash
# Path MTU discovery
ping -D -s <size> <target>

# WireGuard interface status  
ip link show wg0
ip addr show wg0

# Docker networking
docker ps | grep immich
sudo netstat -tlnp | grep 2283
sudo iptables -t nat -L DOCKER -n
sudo iptables -L DOCKER -n
```

### Application Testing
```bash
# Test different request types
curl -I <target>            # HEAD (small)
curl -s <target>/api/...     # API (small) 
curl -s <target>/            # HTML (large)

# Monitor from inside container
docker exec -i <container> curl localhost:2283/
```

### MTU Verification  
```bash
# After MTU change
ip link show wg0 | grep mtu
# Should show: mtu 1280

# Test large transfers
curl -s <target>/ | wc -c
# Should complete without timeout
```

## Prevention and Monitoring

### Early Detection
- **Symptom pattern**: API works, web UI hangs
- **Connection vs data**: TCP success + data timeout = MTU issue
- **Size correlation**: Small responses work, large responses fail

### Configuration Validation
```bash
# Verify WireGuard MTU
ip link show wg0 | grep mtu

# Verify application binding  
docker exec <container> netstat -tlnp | grep 2283

# Verify Docker rules
sudo iptables -t nat -L DOCKER -n | grep 2283
sudo iptables -L DOCKER -n | grep 2283
```

### Path MTU Changes
- **ISP routing changes**: May affect path MTU over time
- **Network upgrades**: Could increase available MTU
- **Monitoring**: Periodic `ping -D` tests to verify current limits

## Related Issues

### Why This Worked Before
- **Previous setup**: Used `docker-compose.dev.yml` with separate web container
- **Different ports**: Web UI on 3001, API on 2283  
- **Request pattern**: Web assets served separately, different size distribution
- **Architecture**: Frontend/backend separation changed data transfer patterns