# Internal-Only Setup Guide

This guide documents the internal-only network configuration for cassie-box, designed for secure access via Tailscale with automatic service discovery.

## Overview

The cassie-box is configured for **internal-only access** with the following architecture:
- All services accessible only within the local network
- Tailscale provides secure remote access
- Automatic nginx reverse proxy with wildcard SSL
- Zero manual configuration needed for new services

## Architecture

### Network Access
- **Local Network**: All services accessible via `https://service.cassies.app`
- **Remote Access**: Via Tailscale VPN only
- **No Public Internet Exposure**: CloudFlare tunnels and dynamic DNS disabled
- **SSL**: Automatic wildcard certificate for `*.cassies.app`

### Service Discovery
- **Automatic nginx virtual hosts**: Each enabled service gets `https://servicename.cassies.app`
- **No manual configuration**: New services automatically get reverse proxy setup
- **Wildcard SSL**: All services use the same Let's Encrypt certificate

## Setup for Cassie

### Initial Setup (One-Time)
1. **Plug in the box** - all services start automatically
2. **Connect to Tailscale**:
   ```bash
   sudo tailscale up
   ```
3. **Accept device in Tailscale admin console**

### Accessing Services
Once connected to Tailscale, access services via:
- **Homepage**: `https://homepage.cassies.app`
- **Plex**: `https://plex.cassies.app`
- **Overseerr**: `https://overseerr.cassies.app`
- **Sonarr**: `https://sonarr.cassies.app`
- **Radarr**: `https://radarr.cassies.app`
- **Grafana**: `https://grafana.cassies.app`
- And all other enabled services...

## Services Included

The following services are automatically configured:

### Media Management
- **Plex**: Media server
- **Overseerr**: Request management
- **Tautulli**: Plex analytics
- **Sonarr**: TV show management
- **Radarr**: Movie management
- **Lidarr**: Music management
- **Readarr**: Book management
- **Prowlarr**: Indexer management

### Download Clients
- **SABnzbd**: Usenet downloader
- **qBittorrent**: Torrent client
- **qBittorrent-LTS**: Long-term support torrent client

### Productivity & Tools
- **Homepage**: Service dashboard
- **Immich**: Photo management
- **Paperless**: Document management
- **Calibre-Web**: Ebook management
- **Navidrome**: Music streaming
- **File Browser**: File management
- **Code Server**: VS Code in browser

### Search & Information
- **SearXNG**: Private search engine
- **Whoogle**: Google proxy
- **Redlib**: Reddit proxy
- **Invidious**: YouTube proxy

### Communication & Social
- **The Lounge**: IRC client
- **Linkding**: Bookmark manager
- **Changedetection**: Website monitoring

### Productivity
- **Vikunja**: Task management
- **Tandoor**: Recipe management
- **Silverbullet**: Note-taking

### Monitoring
- **Grafana**: Dashboards and visualization
- **VictoriaMetrics**: Time-series database
- **Maintainerr**: Plex maintenance automation

## Technical Details

### nginx Configuration
- **Automatic virtual hosts**: Generated for all enabled services
- **SSL**: Wildcard certificate for `*.cassies.app`
- **Proxy settings**: WebSocket support, proper headers
- **Default behavior**: Returns 444 for undefined hosts

### DNS Resolution
- **Internal**: Services resolve via container names or localhost
- **External**: Requires Tailscale or local network access
- **Domain**: `cassies.app` with wildcard SSL support

### Security Features
- **No public exposure**: All services internal-only
- **SSL encryption**: All traffic encrypted via Let's Encrypt
- **Network isolation**: Services can only be accessed via Tailscale or local network
- **Automatic updates**: System configured for automatic security updates

## Troubleshooting

### Service Not Accessible
1. Check service is enabled in configuration
2. Verify nginx is running: `sudo systemctl status nginx`
3. Check service logs: `sudo journalctl -u <service-name>`

### Tailscale Issues
1. Check Tailscale status: `sudo tailscale status`
2. Reconnect if needed: `sudo tailscale up`
3. Verify device approved in Tailscale admin console

### SSL Certificate Issues
1. Check ACME status: `sudo systemctl status acme-cassies.app.service`
2. Renew if needed: `sudo systemctl start acme-cassies.app.service`

### DNS Resolution
1. Verify domain configuration in nginx
2. Check local DNS settings on client device
3. Ensure Tailscale Magic DNS is working

## Adding New Services

New services automatically get nginx virtual hosts when:
1. Service is enabled in configuration: `mySystem.services.servicename.enable = true;`
2. Service follows standard port patterns
3. Service is added to the host configuration

No manual nginx configuration required - everything is automated!

## Benefits of This Setup

- **Zero configuration for Cassie**: Just plug in and connect to Tailscale
- **Secure by default**: No public internet exposure
- **Automatic SSL**: All services encrypted with valid certificates
- **Service discovery**: New services automatically get proper URLs
- **Remote access**: Full access via Tailscale from anywhere
- **Local performance**: No external dependencies for local access

This setup provides the perfect balance of security, convenience, and functionality for a personal media server and self-hosted services infrastructure.
