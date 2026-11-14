#!/bin/sh
# Bring /config to the declared agy and agy-cli release, then start Magpie.
#
# No version is hardcoded: the image digest comes from docker-compose.yml and every
# agy/agy-cli value is injected from the workspace variables, so a release bump is a
# variables-only change. Cloady recreates the container, the `config` volume survives,
# and this script reconciles the new release in place. Nothing is deleted or rebuilt.
#
# The image ships only sh, curl, tar, sha512sum and sha256sum, so this stays POSIX sh.
# Plugin registration is additive: entries present in plugins.json are preserved and
# only the declared agy-cli entry is added or replaced, leaving room for other plugins.
set -eu

for name in MAGPIE_AGY_VERSION MAGPIE_AGY_DOWNLOAD_URL MAGPIE_AGY_SHA512 \
            MAGPIE_AGY_CLI_VERSION MAGPIE_AGY_CLI_COMMIT MAGPIE_AGY_CLI_SHA256; do
  eval "value=\${$name:-}"
  if [ -z "${value}" ]; then
    echo "missing required release variable ${name}" >&2
    exit 64
  fi
done

AGY_DIR=/config/bin/agy-${MAGPIE_AGY_VERSION}
AGY_STAGE=/config/bin/.agy-stage
AGY=${AGY_STAGE}/antigravity
AGY_ARCHIVE=/config/artifacts/agy-${MAGPIE_AGY_VERSION}.tar.gz
PLUGIN_SRC=/config/plugins-${MAGPIE_AGY_CLI_COMMIT}
PLUGIN_ARCHIVE=/config/artifacts/plugin-${MAGPIE_AGY_CLI_COMMIT}.tar.gz
SPEC=/config/plugins-${MAGPIE_AGY_CLI_COMMIT}/packages/agy-cli
PACKAGE_VERSION=${PLUGIN_SRC}/packages/agy-cli/.release-version
REGISTRY=/config/magpie/plugins.json
mkdir -p "${AGY_DIR}" /config/artifacts /config/home/.local/bin /config/magpie

# agy: reuse the volume copy while its checksum matches, otherwise verify and replace.
if [ ! -f "${AGY_ARCHIVE}" ] || [ "$(sha512sum "${AGY_ARCHIVE}" | cut -d' ' -f1)" != "${MAGPIE_AGY_SHA512}" ]; then
  tmp="${AGY_ARCHIVE}.tmp.$$"
  trap 'rm -f "${tmp}"' EXIT
  curl -fsSL --retry 3 -o "${tmp}" "${MAGPIE_AGY_DOWNLOAD_URL}"
  echo "${MAGPIE_AGY_SHA512}  ${tmp}" | sha512sum -c -
  rm -rf "${AGY_STAGE}"
  mkdir -p "${AGY_STAGE}"
  tar -xzf "${tmp}" -C "${AGY_STAGE}"
  chmod 0755 "${AGY}"
  rm -f "${tmp}"
  trap - EXIT
fi
mkdir -p "${AGY_DIR}"
mv -f "${AGY}" "${AGY_DIR}/antigravity"
AGY="${AGY_DIR}/antigravity"
ln -sf "${AGY}" /config/home/.local/bin/agy

# agy-cli: same, verified against the declared commit archive.
if [ ! -f "${PLUGIN_ARCHIVE}" ] || [ "$(sha256sum "${PLUGIN_ARCHIVE}" | cut -d' ' -f1)" != "${MAGPIE_AGY_CLI_SHA256}" ]; then
  tmp="${PLUGIN_ARCHIVE}.tmp.$$"
  trap 'rm -f "${tmp}"' EXIT
  curl -fsSL --retry 3 -o "${tmp}" \
    "https://codeload.github.com/magpie-community/plugins/tar.gz/${MAGPIE_AGY_CLI_COMMIT}"
  echo "${MAGPIE_AGY_CLI_SHA256}  ${tmp}" | sha256sum -c -
  staged="${PLUGIN_SRC}.staged.$$"
  rm -rf "${staged}"
  mkdir -p "${staged}"
  tar -xzf "${tmp}" -C "${staged}"
  rm -rf "${PLUGIN_SRC}"
  mv "${staged}/plugins-${MAGPIE_AGY_CLI_COMMIT}" "${PLUGIN_SRC}"
  rm -rf "${staged}" "${tmp}"
  trap - EXIT
fi

# Fail closed when the staged plugin does not declare the promised version.
printf '%s\n' "${MAGPIE_AGY_CLI_VERSION}" > "${PACKAGE_VERSION}"
version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "${PLUGIN_SRC}/packages/agy-cli/package.json" | head -1)"
if [ "${version}" != "${MAGPIE_AGY_CLI_VERSION}" ]; then
  echo "agy-cli version ${version:-unknown} does not match declared ${MAGPIE_AGY_CLI_VERSION}" >&2
  exit 65
fi

# Registration: reconcile only the declared agy-cli entry, keep every other plugin.
# Editing the array in place means plugins added by hand survive every redeploy.
if [ -f "${REGISTRY}" ] && grep -q '"plugins"' "${REGISTRY}"; then
  sed -i '\|"spec"[[:space:]]*:[[:space:]]*"/config/plugins-[0-9a-f][0-9a-f]*/packages/agy-cli"|d' \
    "${REGISTRY}"
  sed -i "0,/{/s//{\"spec\": \"${SPEC}\" },{/" "${REGISTRY}"
else
  printf '{"plugins":[{"spec":"%s"}]}\n' "${SPEC}" > "${REGISTRY}"
fi

cd /config
exec /magpie serve
