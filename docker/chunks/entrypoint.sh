#!/bin/sh

DATA_DIR=${SRC_DIR-/srv/readsb/data}
CHUNKS_DIR=${DATA_DIR}/chunks

[ -d ${CHUNKS_DIR} ] || mkdir ${CHUNKS_DIR}

exec bash /chunks.sh ${CHUNKS_DIR} ${DATA_DIR}
