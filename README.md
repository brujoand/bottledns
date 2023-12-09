# Bottledns
A tiny solution to a tiny problem

Why?
  - In my homelab I host a bunch of services
  - When I add a service ingress I need to set up a host override on my DNS server
  - This is boring and I always forget to do it (and rarely remove old ones)
  - I don't want to use something fancy like external-dns because well, this is internal

How it works:
  1. Curl(k8s-api/ingresses) --> jq(extract "address=/host/LoadBalancerIP") --> dnsmasq.conf
  2. Reload dnsmasq
  3. Sleep and repeat

Now just point DNS server to bottledns and resolve your ingress hosts.

Requirements:
  - Ingresses with LoadBalancer IPs
  - Service account with ClusterRole that allows listing ingresses
