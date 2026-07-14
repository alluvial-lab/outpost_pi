# rp-s3 — dormant download server

`rp-s3` is a minimal Rust + axum HTTP server that can serve Cockpit and other
product distribution files from a mounted directory. The server is currently
dormant and is **not deployed** as part of the current Outpost-Pi release
infrastructure.

This README retains the routes and local configuration as a reference for a
future self-hosted distribution service. It is not an instruction to operate a
currently deployed service.

## Routes

| Route | Behavior |
|---|---|
| `GET /healthz` | `200 ok` |
| `GET /downloads/<product>/...` | Files from `DATA_DIR/<product>/...` |

Rules for `/downloads` responses:

- `.dmg`/`.exe`/`.deb`/`.rpm`/`.zip` use `Content-Disposition: attachment` and
  `Cache-Control: immutable, 1 year` (artifacts live in versioned directories,
  so their URLs are never reused).
- Other files (`latest.json`, `SHA256SUMS`) use `Cache-Control: max-age=300`
  (a fixed URL propagates a new release within five minutes).
- `Access-Control-Allow-Origin: *` is set on every response so a site can read
  the manifest from another origin.
- Directories are not listed; a directory without an index returns 404.

## Configuration

| Environment variable | Default | Description |
|---|---|---|
| `DATA_DIR` | `/data` | Root served under `/downloads` |
| `PORT` | `8080` | HTTP port |
| `RUST_LOG` | `rp_s3=info,tower_http=info` | Log filter |

## Local data layout

The compose template uses local, configurable directories and mounts them
read-only into the container:

```text
./data/
├── cockpit/
│   ├── latest.json
│   └── SHA256SUMS             (optional)
└── app/
    └── latest.json
```

Override the defaults when the data lives elsewhere:

```bash
RP_S3_COCKPIT_DATA_DIR=/path/to/cockpit/data \
RP_S3_APP_DATA_DIR=/path/to/app/data \
docker compose up -d
```

The corresponding future self-hosted routes would be
`/downloads/cockpit/latest.json` and `/downloads/app/latest.json`.

## Run locally

Without Docker:

```bash
DATA_DIR=./example PORT=8080 cargo run
curl -fsS http://localhost:8080/healthz
```

The compose file is retained as a future self-hosting template. The commands
below build or run local artifacts only; they do not deploy the dormant server:

```bash
docker compose up -d
curl -fsS http://localhost:8080/healthz
```

## Build the Docker image

`build-docker.sh` reads the version from `Cargo.toml`, builds for the host
platform, and loads `outpost-pi-rp-s3:v<version>` plus `:latest` into the local
Docker daemon. It does not push or deploy the dormant server.

```bash
./build-docker.sh
```
