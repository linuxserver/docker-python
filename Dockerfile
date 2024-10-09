# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-alpine:3.19 as buildstage

# set version label
ARG PYTHON_VERSION

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
  if [ -z "${PYTHON_VERSION}" ]; then \
    PYTHON_VERSION=$(curl -sX GET https://api.github.com/repos/python/cpython/tags | jq -r '.[] | select(.name | contains("rc") or contains("a") or contains("b") | not) | .name' | sed 's|^v||g' | sort -rV | head -1); \
  fi && \
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
  sed -i -E 's|\$\(LLVM_PROF_FILE\) \$\(RUNSHARED\) \./\$\(BUILDPYTHON\) \$\(PROFILE_TASK\)$|$(LLVM_PROF_FILE) $(RUNSHARED) ./$(BUILDPYTHON) $(PROFILE_TASK) \|\| true|g' Makefile.pre.in && \
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
  find /pythoncompiled -type f -executable -not \( -name '*tkinter*' \) -exec scanelf --needed --nobanner --format '%n#p' '{}' ';' \
    | tr ',' '\n' \
    | sort -u \
    | awk 'system("[ -e /pythoncompiled/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    | xargs -rt echo > /pythoncompiled/python-deps.txt && \
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
  find /pythoncompiled/bin -type f -not \( -name 'python*' \) -exec sed -i 's|pythoncompiled|usr/local|' '{}' '+' && \
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
