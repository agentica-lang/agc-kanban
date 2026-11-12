#!/bin/sh
# Maps the compose environment to the KANBAN_* variables the server reads, then
# runs it. Variables already set win, so `docker run -e` can change any of them.
set -eu

: "${KANBAN_HOST:=0.0.0.0}"
: "${KANBAN_PORT:=4580}"
: "${KANBAN_DATA_DIR:=/data}"
export KANBAN_HOST KANBAN_PORT KANBAN_DATA_DIR

if [ "$(id -u)" = 0 ]; then
  # A bind mount keeps the owner of the host: the app must write the database
  # and its -wal and -shm files.
  mkdir -p "$KANBAN_DATA_DIR"
  chown -R kanban "$KANBAN_DATA_DIR"
  export HOME=/home/kanban
  exec setpriv --reuid=kanban --regid=kanban --init-groups -- "$@"
fi

exec "$@"
