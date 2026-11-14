# Build the release image from the pinned upstream Magpie image plus the bootstrap.
#
# The upstream image already ships /bin/sh, curl, tar, sha512sum and sha256sum, so no
# package install is needed. COPY preserves the executable bit; there is no RUN step,
# so the build never depends on the image's package manager.
ARG MAGPIE_IMAGE
FROM ${MAGPIE_IMAGE}
COPY bootstrap-agy.sh /usr/local/bin/bootstrap-agy.sh
