#!/bin/sh
# Reconcile /config to the declared agy + agy-cli release, then start Magpie.
#
# Runs on every container start and must be idempotent: an already-matching
# /config is left untouched, so a restart never re-downloads or re-extracts.
# Every value comes from the workspace variables; nothing is hardcoded here.
#
# The upstream Magpie image ships only sh, curl, tar, sed, grep, sha256sum and
# sha512sum, so this stays POSIX sh with no node, python or wget.
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
AGY=${AGY_DIR}/antigravity
AGY_ARCHIVE=/config/artifacts/agy-${MAGPIE_AGY_VERSION}.tar.gz
PLUGIN_SRC=/config/plugins-${MAGPIE_AGY_CLI_COMMIT}
PLUGIN_ARCHIVE=/config/artifacts/plugin-${MAGPIE_AGY_CLI_COMMIT}.tar.gz
SPEC=${PLUGIN_SRC}/packages/agy-cli
REGISTRY=/config/magpie/plugins.json

mkdir -p /config/bin /config/artifacts /config/home/.local/bin /config/magpie

# Download a verified archive, reusing the volume copy while its digest matches.
# $1 url, $2 expected hex digest, $3 destination, $4 checksum binary
fetch_verified() {
  if [ -f "$3" ] && echo "$2  $3" | "$4" -c - >/dev/null 2>&1; then
    return 0
  fi
  tmp="$3.tmp.$$"
  trap 'rm -f "${tmp}"' EXIT
  curl -fsSL --retry 3 -o "${tmp}" "$1"
  echo "$2  ${tmp}" | "$4" -c -
  mv -f "${tmp}" "$3"
  trap - EXIT
}

# agy: only unpack when the declared version is not already in place.
if [ ! -x "${AGY}" ]; then
  fetch_verified "${MAGPIE_AGY_DOWNLOAD_URL}" "${MAGPIE_AGY_SHA512}" "${AGY_ARCHIVE}" sha512sum
  stage="${AGY_DIR}.staged.$$"
  rm -rf "${stage}"
  mkdir -p "${stage}"
  tar -xzf "${AGY_ARCHIVE}" -C "${stage}"
  chmod 0755 "${stage}/antigravity"
  rm -rf "${AGY_DIR}"
  mv "${stage}" "${AGY_DIR}"
fi
ln -sfn "${AGY}" /config/home/.local/bin/agy

# agy-cli: same, plus a fail-closed check that the archive declares the promised version.
if [ ! -f "${SPEC}/package.json" ]; then
  fetch_verified \
    "https://codeload.github.com/magpie-community/plugins/tar.gz/${MAGPIE_AGY_CLI_COMMIT}" \
    "${MAGPIE_AGY_CLI_SHA256}" "${PLUGIN_ARCHIVE}" sha256sum
  stage="${PLUGIN_SRC}.staged.$$"
  rm -rf "${stage}"
  mkdir -p "${stage}"
  tar -xzf "${PLUGIN_ARCHIVE}" -C "${stage}"
  rm -rf "${PLUGIN_SRC}"
  mv "${stage}/plugins-${MAGPIE_AGY_CLI_COMMIT}" "${PLUGIN_SRC}"
  rm -rf "${stage}"
fi
version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "${SPEC}/package.json" | head -1)"
if [ "${version}" != "${MAGPIE_AGY_CLI_VERSION}" ]; then
  echo "agy-cli version ${version:-unknown} does not match declared ${MAGPIE_AGY_CLI_VERSION}" >&2
  exit 65
fi

# Registration is additive: every other entry survives, and an entry already
# pointing at this spec makes the whole step a no-op.
if [ ! -f "${REGISTRY}" ]; then
  printf '{"plugins":[{"spec":"%s"}]}\n' "${SPEC}" > "${REGISTRY}"
elif grep -q "\"spec\"[[:space:]]*:[[:space:]]*\"${SPEC}\"" "${REGISTRY}"; then
  :
else
  # Drop any other agy-cli spec, then append this one inside the plugins array.
  sed -i '\|"spec"[[:space:]]*:[[:space:]]*"/config/plugins-[0-9a-f]*/packages/agy-cli"|d' "${REGISTRY}"
  sed -i "s|\]}|,{\"spec\":\"${SPEC}\"}]}|" "${REGISTRY}"
  grep -q "\"spec\"[[:space:]]*:[[:space:]]*\"${SPEC}\"" "${REGISTRY}" || {
    echo "could not register ${SPEC} in ${REGISTRY}; leaving it untouched" >&2
    exit 66
  }
fi

cd /config
exec /magpie serve
