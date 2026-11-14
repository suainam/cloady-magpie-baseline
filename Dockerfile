# Copy the release bootstrap into the image. The upstream Magpie image already
# ships /bin/sh, curl, tar, sha512sum and sha256sum, so no package install is needed.
# COPY preserves the executable bit from the repository; there is no RUN step, so the
# build does not depend on the image's package manager.
ARG MAGPIE_IMAGE=ghcr.io/yetone/magpie:latest
FROM ${MAGPIE_IMAGE}
COPY bootstrap-agy.sh /usr/local/bin/bootstrap-agy.sh
