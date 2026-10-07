# Excalidraw collaboration on Rancher Desktop

Two ways to run the full stack (frontend, storage, room server, MongoDB) on
[Rancher Desktop](https://rancherdesktop.io/). Both persist scenes in MongoDB.

| Mode | Uses | URL |
| --- | --- | --- |
| Compose | Container engine (moby or containerd) | <http://localhost:8080/> |
| Kubernetes | Bundled k3s + Traefik ingress | <http://localhost/> or `http://<host IP>/` |

`rd.sh` reads Rancher Desktop's settings through `rdctl`, so it picks
`docker compose` or `nerdctl compose` to match your engine and checks that
Kubernetes and Traefik are enabled. Kubernetes commands always use the
`rancher-desktop` kube context (override with `KUBE_CONTEXT=...`), whatever
your current context is.

## Compose

```sh
./rancher-desktop/rd.sh compose up     # or: down | purge | ps | logs
```

| Service | Address |
| --- | --- |
| Excalidraw | <http://localhost:8080/> |
| Storage backend | <http://localhost:8081> |
| Room server | <http://localhost:8082> |

Ports stay off 80/443 so they don't collide with Traefik when Kubernetes is
enabled. Override them with `FRONTEND_PORT`, `STORAGE_PORT` and `ROOM_PORT`.
Without the script, run `docker compose -f rancher-desktop/compose.yaml up -d`
(moby) or `nerdctl compose -f rancher-desktop/compose.yaml up -d` (containerd).

## Saved drawings

Both modes keep drawings in MongoDB on a persistent volume. `down` stops the
stack and keeps that volume, so the next `up` picks up where you left off.
`purge` stops the stack **and deletes all saved drawings**; it asks you to
type `purge` first, or pass `-y` to skip the prompt (for example in scripts).

```sh
./rancher-desktop/rd.sh k8s purge      # or: compose purge, add -y to skip the prompt
```

Rancher Desktop's **Reset Kubernetes** and **Factory Reset** also delete the
Kubernetes and Compose data respectively.

## Kubernetes

Requires **Kubernetes** and **Traefik** enabled under Preferences > Kubernetes.

```sh
./rancher-desktop/rd.sh k8s up         # or: down | purge | status
```

This applies the [k8s/](k8s) kustomization into the `excalidraw` namespace and
routes these paths through Traefik on port 80, for any hostname or IP:

| Path | Service |
| --- | --- |
| `/` | frontend |
| `/storage/` | storage backend (prefix stripped) |
| `/socket.io/` | room server (WebSocket) |

MongoDB data lives on a PersistentVolumeClaim from k3s's local-path
provisioner.

The ingress rules have no host and the frontend uses relative URLs, so the
same deployment answers on `http://localhost/`, this machine's LAN or
Tailscale IP, or any name pointing at it. No DNS is needed. Ingresses with a
host rule elsewhere in the cluster still take precedence over this catch-all.

### Access from other PCs

- **Firewall:** open port 80 (and 443 if you add TLS). On Fedora:
  `sudo firewall-cmd --permanent --add-service=http --add-service=https && sudo firewall-cmd --reload`
- **HTTPS for collaboration:** browsers only allow the crypto APIs that live
  collaboration uses on `localhost` or over HTTPS. From another PC over plain
  `http://<host IP>/`, drawing and saving work, but starting a live session
  fails with a `generateKey` error. Serve it over HTTPS for that.

## Platform notes

- **Linux:** Rancher Desktop can only forward Traefik to `localhost:80` when
  unprivileged processes may bind port 80. Run once, then restart Rancher
  Desktop:

  ```sh
  echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/99-rancher-desktop.conf
  sudo sysctl --system
  ```

  Until then, use Compose mode, which listens on ports above 1024.
- **Apple Silicon:** the Excalidraw images are published for `linux/amd64`
  only. Enable Rosetta under Preferences > Virtual Machine > Emulation (VZ).
- The default MongoDB credentials (`excalidraw`/`excalidraw`) are for local
  use only; the database is not exposed outside the stack.
