# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Bottledns is a lightweight Kubernetes DNS solution that automatically manages DNS records for ingresses and gateway API routes. It runs as a single bash script in a container that continuously monitors Kubernetes resources and updates dnsmasq configuration.

## Architecture
The project consists of:
- `bottledns.sh` - Main bash script that polls Kubernetes API and manages DNS records
- `etc/dnsmasq.conf` - dnsmasq configuration running on port 5353
- `etc/bottledns.hosts` - Dynamic hosts file updated by the script
- `Dockerfile` - Alpine-based container with bash, curl, jq, and dnsmasq
- `example_deployment.yaml` - Complete Kubernetes deployment with RBAC

## Key Components

### Main Script (`bottledns.sh`)
- Runs in continuous loop with 120-second intervals
- Fetches ingresses via Kubernetes API using service account token
- Supports both traditional Ingress resources and Gateway API routes
- Extracts LoadBalancer IPs and hostnames using jq
- Updates `/etc/bottledns.hosts` and reloads dnsmasq on changes
- Uses MD5 hash comparison to detect configuration changes

### DNS Configuration
- dnsmasq runs on port 5353 (mapped to 53 in service)
- Uses system's default DNS resolution (no upstream resolver configured)
- Custom hosts loaded from `/etc/bottledns.hosts`
- Configuration disables system hosts file and polling

## Development Commands

### Build Container
```bash
docker build -t bottledns .
```

### Test Script Locally
```bash
# Requires kubernetes context and proper RBAC
./bottledns.sh
```

### Deploy to Kubernetes
```bash
kubectl apply -f example_deployment.yaml
```

### Test DNS Resolution
```bash
# Test against running container
dig @<bottledns-service-ip> -p 53 <hostname>

# Test locally with dnsmasq
dnsmasq -C etc/dnsmasq.conf --no-daemon
```

## Configuration
- `BOTTLEDNS_NAP_TIME` - Sleep interval between checks (default: 120 seconds)
- Script requires service account with `list` permissions on `ingresses` and `gateways`
- Supports both networking.k8s.io/v1 Ingress and gateway.networking.k8s.io/v1 Gateway resources

### Required RBAC for Gateway API
```yaml
# Add to ClusterRole for Gateway API support
- apiGroups:
  - gateway.networking.k8s.io
  resources:
  - gateways
  - httproutes
  verbs:
  - list
```

## Debugging
- Script logs to stdout when reloading DNS due to changes
- Check `/etc/bottledns.hosts` for current DNS records
- dnsmasq logs available via container logs
- Script can be interrupted with SIGHUP for graceful shutdown
- Uses MD5 hash comparison to avoid unnecessary dnsmasq restarts