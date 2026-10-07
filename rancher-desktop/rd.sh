#!/usr/bin/env bash
# Run the Excalidraw collaboration stack on Rancher Desktop.
#
#   ./rd.sh compose up|down|purge|logs|ps   Container stack via docker/nerdctl compose
#   ./rd.sh k8s up|down|purge|status        Kubernetes stack via the bundled k3s + Traefik
#
# "down" stops the stack and keeps saved drawings; "purge" also deletes them.
# Pass -y to purge without the confirmation prompt.
#
# The Kubernetes commands always target the "rancher-desktop" kube context, so
# they never touch whatever cluster your current context points at.
set -euo pipefail

cd "$(dirname "$0")"

KUBE_CONTEXT="${KUBE_CONTEXT:-rancher-desktop}"
NAMESPACE=excalidraw

die() { echo "error: $*" >&2; exit 1; }

rd_setting() {
  # Prints a Rancher Desktop setting by dotted path, e.g. containerEngine.name.
  command -v rdctl >/dev/null || die "rdctl not found; is Rancher Desktop installed and ~/.rd/bin on PATH?"
  rdctl list-settings | python3 -c '
import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1].split("."):
    v = v[k]
print(str(v).lower())' "$1"
}

compose_cmd() {
  case "$(rd_setting containerEngine.name)" in
    moby) echo "docker compose" ;;
    containerd) echo "nerdctl compose" ;;
    *) die "unknown Rancher Desktop container engine" ;;
  esac
}

kc() { kubectl --context "$KUBE_CONTEXT" "$@"; }

confirm_purge() {
  [ "${1:-}" = -y ] && return
  [ -t 0 ] || die "refusing to purge without a terminal; pass -y to confirm"
  echo "This permanently deletes all saved Excalidraw drawings ($2)."
  read -r -p "Type 'purge' to continue: " answer
  [ "$answer" = purge ] || die "aborted"
}

cmd_compose() {
  local c; c="$(compose_cmd)"
  case "${1:-}" in
    up)
      $c -f compose.yaml up -d
      echo
      echo "Excalidraw: http://localhost:${FRONTEND_PORT:-8080}/"
      ;;
    down) $c -f compose.yaml down ;;
    purge)
      confirm_purge "${2:-}" "compose volume mongo-data"
      $c -f compose.yaml down -v
      ;;
    logs) $c -f compose.yaml logs -f ;;
    ps) $c -f compose.yaml ps ;;
    *) die "usage: $0 compose up|down|purge|logs|ps" ;;
  esac
}

cmd_k8s() {
  case "${1:-}" in
    up)
      [ "$(rd_setting kubernetes.enabled)" = true ] || die "Kubernetes is disabled in Rancher Desktop (Preferences > Kubernetes)"
      [ "$(rd_setting kubernetes.options.traefik)" = true ] || die "Traefik is disabled in Rancher Desktop (Preferences > Kubernetes)"
      kc apply -k k8s
      kc -n "$NAMESPACE" rollout status deploy --timeout=300s
      echo
      echo "Excalidraw: http://localhost/ (or http://<this machine's IP>/ from other PCs)"
      if [ "$(uname -s)" = Linux ] && [ "$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo 0)" -gt 80 ]; then
        cat >&2 <<'MSG'

warning: Rancher Desktop on Linux cannot forward Traefik to localhost:80 until
unprivileged processes may bind port 80. Run once, then restart Rancher Desktop:

  echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rancher-desktop.conf
  sudo sysctl --system
MSG
      fi
      ;;
    down)
      # Keep the namespace, MongoDB volume and its credentials so "up" finds
      # the saved drawings again.
      kc -n "$NAMESPACE" delete deploy,svc,ingress,configmap,middlewares.traefik.io \
        -l app.kubernetes.io/part-of=excalidraw --ignore-not-found
      ;;
    purge)
      confirm_purge "${2:-}" "namespace $NAMESPACE and its MongoDB volume"
      kc delete -k k8s --ignore-not-found
      ;;
    status) kc -n "$NAMESPACE" get pods,svc,ingress,pvc ;;
    *) die "usage: $0 k8s up|down|purge|status" ;;
  esac
}

case "${1:-}" in
  compose) shift; cmd_compose "$@" ;;
  k8s) shift; cmd_k8s "$@" ;;
  *) die "usage: $0 compose|k8s <command>" ;;
esac
