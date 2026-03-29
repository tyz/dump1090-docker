#!/bin/sh

UPINTHEAIR="${UPINTHEAIR:-/data/upintheair.json}"
HEYWHATSTHAT_ID_ALTS="${HEYWHATSTHAT_ID_ALTS-30000}"
AIRCRAFT_DB_DIR="${AIRCRAFT_DB_DIR:-/usr/local/share/tar1090}"
INSTALL_AIRCRAFT_DB="${INSTALL_AIRCRAFT_DB-false}"

if [ "${ENABLE_BIAS_T}" = "true" ]; then
    echo "Activating Bias-T for active antenna..."
    /usr/local/bin/rtl_biast -b 1
    sleep 2
    echo
fi

if [ "${HEYWHATSTHAT_ID}" -a ! -f ${UPINTHEAIR} ]; then
    echo "Creating upintheair.json for altitudes ${HEYWHATSTHAT_ID_ALTS}"
    curl -sLo ${UPINTHEAIR} "http://www.heywhatsthat.com/api/upintheair.json?id=${HEYWHATSTHAT_ID}&refraction=0.25&alts=${HEYWHATSTHAT_ID_ALTS}"
    echo
fi

if [ "${INSTALL_AIRCRAFT_DB}" = "true" ]; then
    if [ -f ${AIRCRAFT_DB_DIR}/aircraft.csv.gz ]; then
        echo "Updating aircraft database"
        cd ${AIRCRAFT_DB_DIR}
        git pull
        cd -
    else
        echo "Installing aircraft database"
        git clone --depth 1 --branch csv --single-branch https://github.com/wiedehopf/tar1090-db ${AIRCRAFT_DB_DIR}
    fi
    echo
fi

echo "Starting readsb..."
exec /app/readsb "$@"
