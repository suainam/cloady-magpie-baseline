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
- `plugins.json`: the declared agy-cli entry is added or replaced in place and every
  other entry is preserved, so plugins added later survive each redeploy.

The image ships only `sh`, `curl`, `tar`, `sha512sum` and `sha256sum`; the script is
POSIX sh and must not depend on `node`, `python3` or `wget`.

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

Change the workspace variable values, then redeploy. Nothing is deleted; `/config`
keeps the agy binary, the plugin source and every other plugin entry.

## Ports

`3425` is the gateway (published). `3430` is the web UI, `expose` only. Nothing else
is published.
