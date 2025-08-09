# Yon's Immich Architecture Documentation

This directory contains documentation about our customized Immich deployment, including deviations from standard configurations and lessons learned during troubleshooting and maintenance.

## Files Overview

### [docker-compose-configurations.md](docker-compose-configurations.md)
**Key Topics**:
- Production vs Development container architectures
- Port consolidation differences (single vs dual container)
- WireGuard network integration specifics
- Docker firewall automation insights

**Main Discoveries**:
- Production serves web + API on single port (2283)
- Development uses separate containers (web:3001, api:2283)
- Docker handles firewall rules automatically for published ports
- WireGuard requires MTU considerations for reliable operation

### [networking-troubleshooting.md](networking-troubleshooting.md)
**Key Topics**:
- MTU/PMTU blackhole diagnosis and resolution
- TCP connection success vs HTTP response failure patterns
- Path MTU discovery methodology
- WireGuard configuration optimization

**Main Discoveries**:
- Path MTU between AT&T SF and Comcast Seattle: 1368 bytes
- WireGuard MTU set to 1280 for safety margin and universal compatibility
- Large HTTP responses (HTML) failed while small responses (API JSON) succeeded
- Docker's DNAT rules bypass host INPUT chain entirely

### [database-maintenance.md](database-maintenance.md)
**Key Topics**:
- Custom database trigger management
- Schema migration impact on custom objects
- Version upgrade procedures and pitfalls
- Custom trigger functionality for asset organization

**Main Discoveries**:
- Immich migrations ignore custom triggers during schema changes
- v1.137.3 standardized table names from plural to singular
- Custom triggers require manual updates during major version upgrades
- Database schema evolution requires proactive monitoring

## System Architecture Summary

### Network Stack
```
Internet → WireGuard (MTU 1280) → Docker DNAT → Container (IMMICH_HOST=0.0.0.0)
```

### Application Stack  
```
Single Container: immich-server:2283
├─ Static Files: sirv middleware (/, /favicon.ico, etc.)
├─ API Routes: NestJS (/api/*)  
└─ Database: PostgreSQL with custom triggers
```

### Custom Components
- **yon-triggers/**: Database triggers for asset auto-organization
- **WireGuard**: Tunnel with conservative MTU settings
- **NixOS firewall**: Minimal rules, relies on Docker automation

## Key Operational Insights

### What Works Differently Than Expected
1. **Docker Firewall**: No manual rules needed, Docker handles iptables
2. **WireGuard MTU**: Conservative settings prevent packet fragmentation issues
3. **Application Binding**: Must explicitly set `IMMICH_HOST=0.0.0.0` for external access
4. **Custom Triggers**: Require manual maintenance during Immich upgrades

### Common Troubleshooting Patterns
1. **Connection + Timeout**: Usually MTU/packet size issues
2. **API Works, Web Doesn't**: Often large response packet problems
3. **Database Errors After Upgrade**: Custom triggers need schema updates
4. **Firewall Confusion**: Docker's automatic rules can be unexpected

### Maintenance Procedures
1. **Pre-upgrade**: Review Immich migration files for schema changes
2. **Post-upgrade**: Check logs for custom trigger errors
3. **Network issues**: Test with `ping -D -s <size>` for MTU problems
4. **Application issues**: Verify `IMMICH_HOST` and Docker port publishing

## Related Documentation

### External References
- [Immich Documentation](https://immich.app/docs)
- [Docker Networking](https://docs.docker.com/network/)  
- [WireGuard Configuration](https://www.wireguard.com/quickstart/)
- [NixOS Firewall](https://nixos.wiki/wiki/Firewall)

### Internal Files
- `yon-triggers/`: Custom database triggers
- `docker/.env`: Application configuration
- `nas-config/configuration.nix`: System configuration (WireGuard, firewall)

## Version History

### v1.137.3 (Current)
- ✅ Fixed custom triggers for singular table names
- ✅ Resolved WireGuard MTU issues
- ✅ Configured proper application binding
- ✅ Documented troubleshooting procedures

### v1.132.3 (Previous)  
- ✅ Working custom triggers (plural table names)
- ⚠️ WireGuard MTU issues causing intermittent failures
- ⚠️ Inconsistent external access configuration

## Future Considerations

### Monitoring Requirements
- Schema changes in new Immich releases
- WireGuard path MTU changes due to routing updates
- Custom trigger compatibility with database migrations
- Docker networking behavior changes

### Potential Improvements
- Automated custom trigger testing during upgrades
- Path MTU monitoring and alerting
- Configuration validation scripts
- Backup procedures for custom database objects