#!/bin/sh

exec bash /chunks.sh ${RUNTIME_DIR-/srv/readsb/data/chunks} ${SRC_DIR-/srv/readsb/data}
