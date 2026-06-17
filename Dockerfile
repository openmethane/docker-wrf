FROM continuumio/miniconda3 as build

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install the bare minimum software requirements on top of trixie-slim
RUN <<EOT
apt-get update -qy
apt-get install -qyy \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    m4 \
    csh \
    jq \
    file \
    build-essential

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
EOT

COPY environment.yml /opt/environment.yml
RUN conda env create -f /opt/environment.yml

# Install conda-pack:
RUN conda install -c conda-forge conda-pack

# Use conda-pack to create a standalone enviornment
# in /venv:
RUN conda-pack -n wrf -o /tmp/env.tar && \
  mkdir /opt/venv && cd /opt/venv && tar xf /tmp/env.tar && \
  rm /tmp/env.tar

# We've put venv in same path it'll be in final image,
# so now fix up paths:
RUN /opt/venv/bin/conda-unpack

COPY scripts /opt/wrf/build/scripts/
RUN WRF_VERSION=${WRF_VERSION} WPS_VERSION=${WPS_VERSION} bash /opt/wrf/build/scripts/build_wrf.sh


FROM debian:trixie-slim AS runtime

MAINTAINER Lindsay Gaines <lindsay.gaines@superpowerinstitute.com.au>

ARG WRF_VERSION=4.5.1
ARG WPS_VERSION=4.5

WORKDIR /opt/wrf
COPY --from=build /opt/venv /opt/venv
COPY --from=build /opt/wrf /opt/wrf


ENTRYPOINT ["/bin/bash"]