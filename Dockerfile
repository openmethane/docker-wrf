# First, build the application in the `/opt/wrf` directory
FROM debian:trixie-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

ARG WRF_VERSION=4.5.1
ARG WPS_VERSION=4.5

# Install the bare minimum build requirements
RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    ca-certificates \
    build-essential \
    m4 \
    csh \
    gfortran \
    libmpich-dev \
    libnetcdf-dev \
    libnetcdff-dev \
    wget

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

WORKDIR /opt/wrf

COPY scripts /opt/wrf/build/scripts/
RUN WRF_VERSION=${WRF_VERSION} WPS_VERSION=${WPS_VERSION} bash /opt/wrf/build/scripts/build_wrf.sh

FROM debian:trixie-slim AS runtime

MAINTAINER Lindsay Gaines <lindsay.gaines@superpowerinstitute.com.au>

# Install the bare runtime requirements
RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    libnetcdff7 \
    mpich

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

WORKDIR /opt/wrf
COPY --from=builder /opt/wrf /opt/wrf

ENTRYPOINT ["bash"]