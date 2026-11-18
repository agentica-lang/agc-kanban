# Server

## Docker

The compose file publishes no port. `make url` prints the container's address on this machine.

```sh
cp .env.example .env   # then set KANBAN_API_KEY (openssl rand -hex 32)
make up        # docker compose up -d --build --wait
make down      # stop (the data volume stays)
```

A machine's own network, fixed IP or published port goes in `docker-compose.override.yml`, which `docker compose` reads after `docker-compose.yml` and which is not in git. For example, a network that already exists and a fixed address:

```yaml
services:
  kanban:
    networks:
      shared:
        ipv4_address: 10.0.1.51
networks:
  shared:
    name: apps
    external: true
```

Or a port on this machine only: `ports: ["127.0.0.1:4580:4580"]` under `kanban`. Set `KANBAN_URL` (for example `http://10.0.1.51:4580`) if `make url` does not find the address you want.

## Without Docker

Needs Agentica 0.33.0, Node and corepack.

```sh
export KANBAN_API_KEY="$(openssl rand -hex 32)"
make install assets run
```

## Configuration

The server reads these variables (the compose file sets the host, port and data dir). The CLI's own variables are in [cli.md](cli.md).

| Variable | Meaning |
| --- | --- |
| `KANBAN_API_KEY` | the one key, for the server and the CLI (at least 32 characters); it also signs the session cookie, so a new key signs the web out |
| `KANBAN_COOKIE_SECURE` | `1` to mark the web session cookie Secure (HTTPS only), and to name it `__Host-kanban_session`; set it behind HTTPS |
| `KANBAN_HOST`, `KANBAN_PORT` | where the server listens (default `127.0.0.1:4580`) |
| `KANBAN_DATA_DIR` | folder of the SQLite file (default `./data`) |
| `KANBAN_LEASE_MINUTES` | claim lease in minutes (`0`, the compose default, turns leases off) |

The web view is in [web.md](web.md).
