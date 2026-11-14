# cloady-magpie-baseline

Shared Magpie release for Cloady workspaces. One compose file, no hardcoded
versions: the image digest and every agy / agy-cli value come from the workspace
variables below, so a release bump is a variables-only change and the `config`
volume is never recreated.

## Why this repo exists

Cloady applications created from an `upload` source pin a fixed `uploadId`; the API
refuses to change the source or image afterwards, so an upload app can only be
"updated" by deleting it, which permanently destroys its volume. A `git`-sourced app
redeploys from this repository on every change instead: `redeploy`, `start`, `stop`
move containers only, and volumes survive. That is what makes repeat upgrades safe.

## Deploy

```bash
cloady deploy github.com/suainam/cloady-magpie-baseline --type git \
  -w <workspace> --region <region> --name magpie --port 3425 \
  --value MAGPIE_IMAGE=ghcr.io/yetone/magpie@sha256:<digest> \
  --value MAGPIE_AGY_VERSION=<agy version> \
  --value MAGPIE_AGY_DOWNLOAD_URL=<versioned GCS url> \
  --value MAGPIE_AGY_SHA512=<128 hex> \
  --value MAGPIE_AGY_CLI_VERSION=<plugin version> \
  --value MAGPIE_AGY_CLI_COMMIT=<40 hex> \
  --value MAGPIE_AGY_CLI_SHA256=<64 hex> \
  --secretKeys MAGPIE_WEB_KEY
```

`MAGPIE_WEB_KEY` must be listed in `secretKeys`; the repository only ever names it.
Equivalent REST calls:

```bash
curl -X POST "$API/workspaces/<ws>/deploy" -d '{"region":"usw1","name":"magpie",
  "env":"production","source":{"type":"git","repoUrl":"https://github.com/suainam/cloady-magpie-baseline"},
  "port":3425,"scale":{"cpu":0.5,"memory":1,"volumes":{"config":1}},"values":{...},"secretKeys":["MAGPIE_WEB_KEY"]}'
```

## Updating a release

Change the variable values in the workspace (dashboard or `PATCH`/`deploy` `values`),
then redeploy. The container is recreated, `/config` is kept, and
`bootstrap-agy.sh` reconciles agy and agy-cli in place:

- agy is reused while its archive SHA512 matches; otherwise the declared versioned
  URL is downloaded, verified, and extracted.
- agy-cli is reused while its archive SHA256 matches; otherwise the declared commit
  archive is downloaded, verified, and extracted.
- the staged `package.json` version must equal `MAGPIE_AGY_CLI_VERSION`, otherwise
  startup fails closed.
- `plugins.json` is edited in place: the declared agy-cli entry is added or replaced
  and every other plugin entry is preserved.

## Ports

`3425` is the gateway (published), `3430` is the web UI (internal `expose` only).
Nothing else is published.

## Compatibility

The image ships `sh`, `curl`, `tar`, `sha512sum` and `sha256sum` only. The bootstrap
script is POSIX sh and must not depend on `node`, `python3` or `wget`.
