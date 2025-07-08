#!/usr/bin/env bash

set -e

KUBE_ENDPOINT="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
BOTTLEDNS_HOSTS='/etc/bottledns.hosts'
DNSMASQ_CONF='/etc/dnsmasq.conf'
BOTTLEDNS_NAP_TIME=120

function curl_k8s {
  local path=$1
  curl -s --header "Authorization: Bearer ${KUBE_TOKEN}" --insecure "${KUBE_ENDPOINT}/${path}"
}

function get_all_ingress {
  curl_k8s "apis/networking.k8s.io/v1/ingresses"
}

function get_all_gateways {
  curl_k8s "apis/gateway.networking.k8s.io/v1/gateways" | \
  jq -r '.items[] | "\(.metadata.namespace):\(.metadata.name)"'
}

function get_gateway_ip {
  local gateway_name=${1}
  local namespace=${2}
  if [[ -z $gateway_name || -z $namespace ]]; then
    echo "Missing gateway_name or namespace"
    return 1
  fi

  jq -r '.status.addresses[]?.value // empty' <<< "$gateway_data"
}

function get_gateway_hostnames {
  local gateway=$1
  curl_k8s "apis/gateway.networking.k8s.io/v1/httproutes" \
  | jq -r --arg gw "$gateway" '
    .items[]
    | select(.spec.parentRefs[]?.name == $gw)
    | .spec.hostnames[]?
  '
}

function get_route_records {
  mapfile -t gateway_lines <<< "$(get_all_gateways)"

  for gateway_line in "${gateway_lines[@]}"; do
    mapfile -t -d ':' gateway_data <<< "${gateway_line}"
    local namespace="${gateway_data[0]%$'\n'}"
    local name="${gateway_data[1]%$'\n'}"
    ip="$(get_gateway_ip "$name" "$namespace")"
    mapfile -t hostnames <<< "$(get_gateway_hostnames "$name")"
    for hostname in "${hostnames[@]}"; do
      local host="${hostname%$'\n'}"

      [[ -z $host ]] && continue
      printf '%s %s\n' "$ip" "${host}"
    done
  done
}

function get_ingress_records {
  jq -r \
    '.items[] |
    "\(.status.loadBalancer.ingress // [] | map(.ip)[]) \(.spec.rules // [] | map(.host)[])"' \
  <<< "$(get_all_ingress)"
}

function get_records {
  get_route_records
  get_ingress_records
}

printf '%s\n' 'Starting dnsmasq'
dnsmasq -C "$DNSMASQ_CONF"

while true; do
  current_hash=$(md5sum "$BOTTLEDNS_HOSTS")
  get_records | sort > "$BOTTLEDNS_HOSTS"

  if ! md5sum -c <<< "$current_hash" &>/dev/null; then
    printf '%s\n' 'Reloading custom hosts due to change'
    pkill -SIGHUP dnsmasq
  fi

  # Needed so that we can be interupted by SIGHUP
  sleep "$BOTTLEDNS_NAP_TIME" &
  wait $!

done
