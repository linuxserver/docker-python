# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-alpine:3.19 as buildstage

# set version label
ARG PYTHON_VERSION=3.12.2

ENV MAKEFLAGS="-j4"

COPY patches/* /patches/

RUN \
  echo "**** install build dependencies ****" && \
  apk add --no-cache --virtual=build-dependencies \
    patch \
    bluez-dev \
    bzip2-dev \
    coreutils \
    dpkg-dev dpkg \
    expat-dev \
    findutils \
    build-base \
    gdbm-dev \
    libc-dev \
    libffi-dev \
    libnsl-dev \
    openssl \
    openssl-dev \
    libtirpc-dev \
    linux-headers \
    make \
    mpdecimal-dev \
    ncurses-dev \
    pax-utils \
    readline-dev \
    sqlite-dev \
    tcl-dev \
    tk \
    tk-dev \
    xz-dev \
    zlib-dev && \
  echo "**** compile python ****" && \
  mkdir -p \
    /tmp/python \
    /pythoncompiled && \
  curl -o \
    /tmp/python.tar.xz -L \
    "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" && \
  tar xf \
    /tmp/python.tar.xz -C \
    /tmp/python --strip-components=1 && \
  for patch in /patches/*.patch; do \
    patch -d /tmp/python -p 1 < "${patch}"; \
  done && \
  cd /tmp/python && \
  ./configure \
    --build="x86_64-linux-musl" \
    --enable-loadable-sqlite-extensions \
    --enable-optimizations \
    --enable-option-checking=fatal \
    --enable-shared \
    --prefix=/pythoncompiled \
    --with-lto \
    --with-system-libmpdec \
    --with-system-expat \
    --without-ensurepip \
    --without-static-libpython && \
  make \
    LDFLAGS="-Wl,--strip-all" \
    CFLAGS="-fno-semantic-interposition -fno-builtin-malloc -fno-builtin-calloc -fno-builtin-realloc -fno-builtin-free" \
    EXTRA_CFLAGS="-DTHREAD_STACK_SIZE=0x100000" && \
  make install && \
  find /pythoncompiled -depth \
    \( \
      -type d -a \( -name test -o -name tests \) \
    \) -exec rm -rf '{}' + && \
  cd /pythoncompiled/bin && \
  ln -s idle3 idle && \
  ln -s pydoc3 pydoc && \
  ln -s python3 python && \
  ln -s python3-config python-config && \
  curl -o \
    /tmp/get-pip.py -L \
    "https://bootstrap.pypa.io/get-pip.py" && \
  LD_LIBRARY_PATH=/pythoncompiled/lib /pythoncompiled/bin/python3 /tmp/get-pip.py \
    --prefix=/pythoncompiled \
    --disable-pip-version-check \
    --no-cache-dir \
    pip && \
  find /pythoncompiled -depth \
    \( \
        -type d -a \( -name test -o -name tests \) \
    \) -exec rm -rf '{}' + && \
  sed -i 's|pythoncompiled|usr/local|' /pythoncompiled/bin/pip /pythoncompiled/bin/pip* /pythoncompiled/bin/wheel && \
  echo "**** cleanup ****" && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    /root/.cache \
    /tmp/*

# Storage layer consumed downstream
FROM scratch

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="aptalca"

# Add files from buildstage
COPY --from=buildstage /pythoncompiled/ /usr/local/
