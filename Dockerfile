# Jasper isn't packaged in Debian trixie (dropped for its CVE history in the
# old 1.9 branch), but WPS's GRIB2 support hard-links against it for JPEG2000
# decoding, so build a current, static copy from source to avoid depending on
# any distro package for it.
FROM debian:trixie-slim AS jasper-builder

ARG JASPER_VERSION=4.2.5

RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    ca-certificates \
    build-essential \
    cmake \
    wget

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

WORKDIR /opt
RUN wget -nv https://github.com/jasper-software/jasper/releases/download/version-${JASPER_VERSION}/jasper-${JASPER_VERSION}.tar.gz -O jasper.tar.gz \
    && tar -xzf jasper.tar.gz \
    && rm jasper.tar.gz

# Build a static library only - WPS links it into ungrib.exe directly, so
# there's no need to ship a shared libjasper in the runtime image.
RUN cmake -S jasper-${JASPER_VERSION} -B /opt/jasper-build \
    -DCMAKE_INSTALL_PREFIX=/opt/jasper \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DJAS_ENABLE_SHARED=OFF \
    -DJAS_ENABLE_LIBJPEG=OFF \
    -DJAS_ENABLE_LIBHEIF=OFF \
    -DJAS_ENABLE_OPENGL=OFF \
    -DJAS_ENABLE_DOC=OFF \
    -DJAS_ENABLE_PROGRAMS=OFF \
    && make -C /opt/jasper-build -j"$(nproc)" \
    && make -C /opt/jasper-build install \
    && rm -rf /opt/jasper-build jasper-${JASPER_VERSION}

# Next, build the application in the `/opt/wrf` directory
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
    libpng-dev \
    zlib1g-dev \
    wget

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

COPY --from=jasper-builder /opt/jasper /opt/jasper
ENV JASPERLIB=/opt/jasper/lib
ENV JASPERINC=/opt/jasper/include

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
    libpng16-16t64 \
    mpich

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

WORKDIR /opt/wrf

COPY --from=builder /opt/wrf/WRF /opt/wrf
COPY --from=builder /opt/wrf/WPS /opt/wps

# Update the PATH variable
ENV PATH="/opt/wrf/main:/opt/wps:${PATH}"

CMD ["bash"]