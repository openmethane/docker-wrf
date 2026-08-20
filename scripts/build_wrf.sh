#!/usr/bin/env bash
# Builds WRF and WPS using the prebuilt dependencies

set -xe

# Setup
WRF_VERSION="${WRF_VERSION:-4.5.1}"
WPS_VERSION="${WPS_VERSION:-4.5}"

# Link to the compiled dependencies
# NOTE: WRF's own configure/Config.pl ignores $LDFLAGS for netCDF linkage -
# it only adds -lnetcdf/-lnetcdff to the final link line when $NETCDF_LDFLAGS
# is set (otherwise sw_usenetcdf/sw_usenetcdff stay empty, since ./configure
# never passes -usenetcdf=/-usenetcdff= to Config.pl). Without this,
# real.exe/wrf.exe fail to link with "undefined reference to nf_*".
export NETCDF_LDFLAGS="$(nf-config --flibs)"
#export CPPFLAGS=
export CC=gcc
export CXX=g++
export FC=gfortran
export FCFLAGS="-m64  -fallow-argument-mismatch"
export F77=gfortran
export FFLAGS="-m64  -fallow-argument-mismatch"
export NETCDF=$(nc-config --prefix)
export NETCDF4=1
#export JASPERLIB=
#export JASPERINC=
export J="-j 8"
export ARCH=$(uname -m)

# WRF's configure always links against unsuffixed -lhdf5/-lhdf5_hl and expects
# to find them via $HDF5_PATH/lib, so alias the actual installed library in
# "/usr/lib/x86_64-linux-gnu/hdf5/serial" as "/lib" and point to its parent.
ln -s /usr/lib/x86_64-linux-gnu/hdf5/serial /usr/lib/x86_64-linux-gnu/hdf5/lib
export HDF5_PATH=/usr/lib/x86_64-linux-gnu/hdf5

# WPS's own configure only adds -lnetcdff to its link line when it finds a
# static $NETCDF/lib/libnetcdff.a; Debian puts that file under the multiarch
# directory, not the plain lib dir, so alias it in place. Without this,
# metgrid.exe/ungrib.exe fail to link with "undefined reference to nf90_*".
ln -s /usr/lib/x86_64-linux-gnu/libnetcdff.a /usr/lib/libnetcdff.a

# GCC 14 (shipped in trixie) turns implicit-function-declaration/implicit-int
# from warnings into hard errors by default. WRF/WPS's bundled C sources (the
# Registry tool, io_grib1, io_grib_share, WPS's cio.c) predate that and rely
# on implicit declarations of libc functions, so demote those back to
# warnings wherever we patch in generated build configs below.
GCC14_COMPAT_CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"

# Build directory
cd /opt/wrf

# Build WRF
if [ ! -f WRF-${WRF_VERSION}/run/real.exe ]; then
  wget -nv https://github.com/wrf-model/WRF/releases/download/v${WRF_VERSION}/v${WRF_VERSION}.tar.gz -O WRF-v${WRF_VERSION}.tar.gz
  tar -xzf WRF-v${WRF_VERSION}.tar.gz
  pushd WRFV${WRF_VERSION} || exit

  if [[ $ARCH == "aarch64" ]]; then
    echo "11\n1\n" | ./configure  # dmpar + gfortran + aarch64
  else
    echo "34\n1\n" | ./configure  # dmpar + gfortran + x86_64
  fi

  sed -i "s/\(CFLAGS_LOCAL[[:space:]]*=[[:space:]]*-w -O3 -c\)/\1 ${GCC14_COMPAT_CFLAGS}/" configure.wrf
  sed -i "s/\(CFLAGS = \$(CC_TOOLS_CFLAGS)\)/\1 ${GCC14_COMPAT_CFLAGS}/" tools/Makefile

  ./compile em_real
  popd
  ln -s WRFV${WRF_VERSION} WRF
fi

# Build WPS
if [ ! -f WPS-${WPS_VERSION}/wps.exe ]; then
  wget -nv https://github.com/wrf-model/WPS/archive/v${WPS_VERSION}.tar.gz -O WPS-v${WPS_VERSION}.tar.gz
  tar -xzf WPS-v${WPS_VERSION}.tar.gz

  pushd WPS-${WPS_VERSION} || exit

  # Add some compiler options for aarch64 (based on x86_64)
  cat /opt/wrf/build/scripts/configure.aarch64 >> arch/configure.defaults

  # option 1 = serial/gfortran/GRIB2. Without GRIB2 support, ungrib.exe refuses
  # to decode Grib Edition 2 data (most current GFS/ERA5 sources) with
  # NEED_GRIB2_LIBS. $JASPERLIB/$JASPERINC (set in the Dockerfile) point
  # ./configure at the Jasper build from the jasper-builder stage, so this
  # picks up real JPEG2000 + PNG support, matching an unmodified WPS build.
  echo "1" | ./configure # serial + gfortran, GRIB2

  # See the GCC14_COMPAT_CFLAGS note above - WPS's own cio.c hits the same
  # implicit-function-declaration/implicit-int errors, and configure.wps's
  # CFLAGS for this arch starts out empty (no "-w" to interact with).
  sed -i "s/\(^CFLAGS[[:space:]]*=\)[[:space:]]*$/\1 ${GCC14_COMPAT_CFLAGS}/" configure.wps

  # WPS 4.2-4.6 reads an uninitialised local (is_subgrid_var) when building
  # metgrid's output field list; under gfortran 14 every field is discarded and
  # metgrid writes empty met_em files while reporting success. Fixed in WPS 4.7.0.
  sed -i -E "s/^(FFLAGS|F77FLAGS)([[:space:]]*=.*)$/\\1\\2 -finit-logical=false/" configure.wps

  # Fail loudly rather than silently building a metgrid.exe that writes nothing.
  grep -qE "^FFLAGS[[:space:]]*=.*-finit-logical=false" configure.wps \
    || { echo "Failed to patch FFLAGS in configure.wps"; exit 1; }

  ./compile
  popd
  ln -s WPS-${WPS_VERSION} WPS
fi

rm *.tar.gz

[[ -f /opt/wrf/WRF/main/real.exe ]] || { echo "WRF real.exe failed to build"; exit 1; }
[[ -f /opt/wrf/WRF/main/wrf.exe ]] || { echo "WRF wrf.exe failed to build"; exit 1; }
[[ -f /opt/wrf/WPS/metgrid.exe ]] || { echo "WPS metgrid.exe failed to build"; exit 1; }
[[ -f /opt/wrf/WPS/geogrid.exe ]] || { echo "WPS geogrid.exe failed to build"; exit 1; }
[[ -f /opt/wrf/WPS/ungrib.exe ]] || { echo "WPS ungrib.exe failed to build"; exit 1; }
