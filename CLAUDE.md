# bottledns

Polls Kubernetes Ingresses and Gateway API routes, writes a dnsmasq hosts file.
A single bash script in an Alpine container.

## Hard rules

- **Never push to `main`/`master`.** Feature branch + PR, always. Open the PR,
  report the URL, stop — **only the human merges.**
- **Conventional Commits** (`feat:`, `fix:`, `chore:`, …). Never hand-bump a version.
- Plan every non-trivial task. If the plan fails, restart planning.

## Workflow

Default branch is `main`. There is no pre-commit config and no mise here; the only
CI is `docker-publish.yml`. The workspace bash standards still apply.

## Architecture

- `bottledns.sh` — polls the Kubernetes API and manages DNS records
- `etc/dnsmasq.conf` — dnsmasq on port 5353 (mapped to 53 by the Service)
- `etc/bottledns.hosts` — the dynamic hosts file the script rewrites
- `Dockerfile` — Alpine + bash, curl, jq, dnsmasq
- `example_deployment.yaml` — full deployment with RBAC

The script loops on `BOTTLEDNS_NAP_TIME` (default 120s), fetches Ingresses with its
service-account token, extracts LoadBalancer IPs and hostnames with `jq`, and
reloads dnsmasq only when an MD5 of the rendered hosts file changes. It handles
both `networking.k8s.io/v1` Ingress and `gateway.networking.k8s.io/v1` Gateway.

## Commands

```bash
docker build -t bottledns .
./bottledns.sh                              # needs a kube context + RBAC
kubectl apply -f example_deployment.yaml
dig @<service-ip> -p 53 <hostname>
dnsmasq -C etc/dnsmasq.conf --no-daemon     # test locally
```

## Gotchas

- Bash standards: `#!/usr/bin/env bash`, `set -e`, `[[` not `[`, `$()` not
  backticks, `local` in functions, no emojis, 2-space indent. Use `jq` for JSON,
  never python.
- The service account needs `list` on `ingresses`; Gateway API support
  additionally needs `list` on `gateways` and `httproutes` in the ClusterRole.
- dnsmasq is deliberately configured with no upstream resolver and the system
  hosts file disabled.
- The MD5 comparison exists to avoid restarting dnsmasq on every poll — keep it.
- The script traps SIGHUP for graceful shutdown; it logs to stdout only when it
  actually reloads.
