# Image of the agc-kanban server (API and live web): plain HTTP, SQLite in /data. Build with
# `docker compose build`; the compose file runs it on the private 172.28.0.10.
# Stage 1 builds the stylesheet and the script, so Node and pnpm never reach the image. Stage 2 holds the tools that
# must not reach it either: curl and git (`agentica install` fetches with git) and the C compiler that builds the
# native SQLite driver of agentica-db.
FROM node:24-slim AS assets

WORKDIR /web
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY app ./app
COPY tools/assets.mjs ./tools/assets.mjs
# The build writes public/assets/ and the file with their names, which stage 2 compiles in.
RUN mkdir -p src/kanban_web && node tools/assets.mjs

FROM debian:13-slim AS build

# Change the version and the sha256 together, taken from the release's
# SHA256SUMS. The image is x86_64 only (the release archive of linux-x86_64).
ARG AGENTICA_VERSION=0.30.1
ARG AGENTICA_SHA256=bfd2932a00345f1459dea974c56b9f87ad0078d722466ce485dc56dcfb45643b

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

RUN archive="agentica-${AGENTICA_VERSION}-linux-x86_64.tar.gz" \
 && curl -fsSL -o "/tmp/$archive" \
      "https://github.com/agentica-lang/agentica/releases/download/${AGENTICA_VERSION}/$archive" \
 && echo "${AGENTICA_SHA256}  /tmp/$archive" | sha256sum -c - \
 && mkdir /opt/agentica \
 && tar -xzf "/tmp/$archive" -C /opt/agentica --strip-components=1

# The package cache in a fixed folder (not under $HOME) so that stage 2 finds
# the native library at the same absolute path.
ENV XDG_CACHE_HOME=/opt/agentica-cache

WORKDIR /app
COPY agentica.toml agentica.lock ./
# The packages of the lock go to deps/, checked against the hashes of the lock;
# nothing is fetched at run time.
RUN /opt/agentica/bin/agentica install

COPY server.agc ./
COPY src ./src
COPY --from=assets /web/public ./public
COPY --from=assets /web/src/kanban_web/asset_names.agc ./src/kanban_web/asset_names.agc
# Compiling imports pkg/db/db, which builds the native SQLite driver into the
# package cache, and the bytecode stores its absolute path. The build fails if
# the library is missing: at run time a missing one would quietly fall back to
# the slower FFI driver. The image runs bytecode, not source, because a run from
# source computes the cache key with a C compiler that stage 2 does not have.
RUN /opt/agentica/bin/agentica compile server.agc -o server.agcb \
 && test "$(find "$XDG_CACHE_HOME/agentica/pkg/native-build" -name libdb_sqlite.so | wc -l)" = 1 \
 && grep -aq "$XDG_CACHE_HOME/agentica/pkg/native-build/.*/libdb_sqlite.so" server.agcb \
 && chmod -R a+rX "$XDG_CACHE_HOME/agentica/pkg/native-build"

# Stage 3: the binary, the compiled program and the native driver (no compiler).
# libsqlite3 is the database the driver opens.
FROM debian:13-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 1000 --create-home --shell /usr/sbin/nologin kanban \
 && mkdir -p /data \
 && chown kanban:kanban /data

COPY --from=build /opt/agentica/bin/agentica /usr/local/bin/agentica
COPY --from=build /app /app
COPY --from=build /opt/agentica-cache/agentica/pkg/native-build /opt/agentica-cache/agentica/pkg/native-build
# XDG_CACHE_HOME must equal the value of stage 1: the bytecode holds the path.
ENV XDG_CACHE_HOME=/opt/agentica-cache AGENTICA_DB_SQLITE_DRIVER=native
ENV GC_INITIAL_HEAP_SIZE=33554432
COPY docker/entrypoint.sh /usr/local/bin/kanban-entrypoint

WORKDIR /app
ENV HOME=/home/kanban
EXPOSE 4580

# The entrypoint starts as root only to hand /data to the app user (a bind
# mount keeps the owner of the host), then runs the app as `kanban`. The app is
# PID 1: run with `init: true` for a clean stop on SIGTERM.
ENTRYPOINT ["kanban-entrypoint"]
CMD ["agentica", "run", "--", "server.agcb"]
