# cloady-magpie-baseline

Shared Magpie release for Cloady workspaces. One compose file, no hardcoded
versions: the image digest and every agy / agy-cli value come from the workspace
variables, so a release bump is a variables-only change and the `config` volume is
never recreated.

## Why this repository exists

A Cloady application created from an `upload` source pins a fixed `uploadId`. The API
refuses to change the source or the image afterwards, so an upload app can only be
"updated" by deleting it, which permanently destroys its volume. A `git`-sourced app
redeploys from this repository on every change: `redeploy`, `start` and `stop` move
containers only and volumes survive. That is what makes repeat upgrades safe.

## What the entrypoint does

`bootstrap-agy.sh` runs once per container start and is a no-op once `/config`
matches the declared release:

- agy: reuse the volume archive while its SHA512 matches; otherwise download the
  declared versioned URL, verify it, extract it, and repoint
  `/config/home/.local/bin/agy`.
- agy-cli: same against the declared commit archive, then require the staged
  `package.json` version to equal `MAGPIE_AGY_CLI_VERSION`, failing closed otherwise.
- `plugins.json`: updated with Magpie's bundled bun runtime as JSON. Other plugin
  entries, their `off` state and top-level fields survive; a registry with duplicate
  old agy-cli entries is rejected without being written (fail closed).

The image ships `sh`, `curl`, `tar`, `sed`, `grep`, `sha512sum`, `sha256sum` and its
bundled bun runtime; the script is POSIX sh and must not depend on `node`, `python3`
or `wget`.

## Deploy

```bash
cloady deploy github.com/suainam/cloady-magpie-baseline --type git \
  -w <workspace> --region <region> --name magpie --port 3425 \
  --value MAGPIE_IMAGE=ghcr.io/yetone/magpie@sha256:<digest> \
  --value MAGPIE_AGY_VERSION=<agy-version> \
  --value MAGPIE_AGY_DOWNLOAD_URL=<versioned-gcs-url> \
  --value MAGPIE_AGY_SHA512=<128-hex> \
  --value MAGPIE_AGY_CLI_VERSION=<plugin-version> \
  --value MAGPIE_AGY_CLI_COMMIT=<40-hex> \
  --value MAGPIE_AGY_CLI_SHA256=<64-hex> \
  --secretKeys MAGPIE_WEB_KEY
```

`MAGPIE_WEB_KEY` must be listed in `secretKeys`; the repository only ever names it.

Equivalent REST call:

```bash
curl -X POST "$API/workspaces/<ws>/deploy" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"region":"usw1","name":"magpie","env":"production",
       "source":{"type":"git","repoUrl":"https://github.com/suainam/cloady-magpie-baseline","branch":"main"},
       "port":3425,"scale":{"cpu":0.5,"memory":1,"volumes":{"config":1}},
       "values":{...},"secretKeys":["MAGPIE_WEB_KEY"]}'
```

## Updating a release

1. Update the shared values in the control repo's `inventories/group_vars/all/versions.yml`
   (`magpie_release_image`, `magpie_agy_*`, `magpie_agy_cli_*`).
2. Update this repository's compose: the image digest line and the bootstrap commit in
   the entrypoint URL. Both are pins; a release bump edits exactly these two lines.
3. Push, then redeploy the app (the platform does this automatically when auto update
   is on). Verify inside the container: `agy --version`, the plugin spec,
   `/magpie healthcheck`.

Never publish a bootstrap commit that has not passed the local restart tests against
the pinned upstream image (fresh volume, existing registry with other plugins,
duplicate-entry rejection).

## Known platform behavior

- The first deploy of this app also built the repo root and left an `app` deployment
  that crashloops. The compose declares `app` with `deploy.replicas: 0` to stop it;
  remove that block once the deployment is gone.
- No registry push rights for `ghcr.io` or Docker Hub are configured, so this repo
  must never grow a root `Dockerfile` that the platform would build.
- Deleting the app permanently deletes the `config` volume (agy sign-in state,
  plugin state). Treat it as the last resort only.

## Control-plane documentation

The operator-facing SOP lives in the control repo:
`docs/operations/instabox-magpie.md` (section "Cloady 托管基线") links back here.
Asset, backup and restore boundaries are in `docs/cloady-operations.md`.

## Ports

`3425` is the gateway (published). `3430` is the web UI, `expose` only. Nothing else
is published.

