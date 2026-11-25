#!/usr/bin/env bash

set -e

KUBE_ENDPOINT="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
BOTTLEDNS_HOSTS=${BOTTLEDNS_HOSTS:-"${HOME}/bottledns.hosts"}
DNSMASQ_CONF=${DNSMASQ_CONF:-"${HOME}/dnsmasq.conf"}
BOTTLEDNS_NAP_TIME=${BOTTLEDNS_NAP_TIME:-120}

# Prints the response body. Fails on a connection error or any status other
# than 200. A 404 (API group not installed) is an empty list.
function curl_k8s {
  local path=$1
  local response status
  response=$(curl -s -w '\n%{http_code}' --header "Authorization: Bearer ${KUBE_TOKEN}" --insecure "${KUBE_ENDPOINT}/${path}") || return 1
  status=${response##*$'\n'}
  case $status in
  200) printf '%s\n' "${response%$'\n'*}" ;;
  404) printf '%s\n' '{"items":[]}' ;;
  *)
    printf '%s\n' "${response%$'\n'*}"
    return 1
    ;;
  esac
}

function verify_rbac_permissions {
  local ingress_response
  ingress_response=$(curl_k8s "apis/networking.k8s.io/v1/ingresses") || true

  if echo "$ingress_response" | jq -e '.status == "Failure"' &>/dev/null; then
    echo "ERROR: $(echo "$ingress_response" | jq -r '.message')"
    echo "See example_deployment.yaml for RBAC configuration."
    exit 1
  fi
}

# Fails if any request fails, so an API outage never yields a partial record set.
function get_records {
  local ingresses gateways routes
  ingresses=$(curl_k8s "apis/networking.k8s.io/v1/ingresses") || return 1
  gateways=$(curl_k8s "apis/gateway.networking.k8s.io/v1/gateways") || return 1
  routes=$(curl_k8s "apis/gateway.networking.k8s.io/v1/httproutes") || return 1

  printf '%s\n%s\n' "$gateways" "$routes" | jq -rs '
    .[1].items as $routes
    | .[0].items[]
    | .metadata.name as $gw
    | .status.addresses[]?.value as $ip
    | $routes[]
    | select(any(.spec.parentRefs[]?; .name == $gw))
    | .spec.hostnames[]?
    | "\($ip) \(.)"
  ' || return 1

  jq -r \
    '.items[] |
    "\(.status.loadBalancer.ingress // [] | map(.ip)[]) \(.spec.rules // [] | map(.host)[])"' \
    <<<"$ingresses" || return 1
}

function write_hosts_file {
  local temp_hosts records
  if ! records=$(get_records); then
    printf '%s\n' 'Kubernetes API request failed, keeping the current hosts file'
    return 1
  fi
  temp_hosts=$(mktemp)

  if [[ -n ${BOTTLEDNS_OVERRIDE_HOSTS} ]]; then
    if [[ -f ${BOTTLEDNS_OVERRIDE_HOSTS} ]]; then
      cat "${BOTTLEDNS_OVERRIDE_HOSTS}" >"$temp_hosts"
    else
      printf '%s\n' "Warning: Override hosts file ${BOTTLEDNS_OVERRIDE_HOSTS} not found, continuing without it"
    fi
  fi

  printf '%s' "$records" | sort >>"$temp_hosts"
  cat "$temp_hosts" >"$BOTTLEDNS_HOSTS"
}

verify_rbac_permissions

printf '%s\n' 'Starting dnsmasq'
dnsmasq -C "$DNSMASQ_CONF"

while true; do
  current_hash=$(md5sum "$BOTTLEDNS_HOSTS")

  if write_hosts_file && ! md5sum -c <<<"$current_hash" &>/dev/null; then
    printf '%s\n' 'Restarting dnsmasq due to change in bottledns hosts'
    pkill dnsmasq
    # Wait a bit to avoid race condition
    sleep 0.5
    # Restart dnsmasq in the background
    dnsmasq -C "$DNSMASQ_CONF"
  fi

  # Needed so that we can be interupted by SIGHUP
  sleep "$BOTTLEDNS_NAP_TIME" &
  wait $!

done
