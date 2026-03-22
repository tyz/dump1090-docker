#!/bin/sh

if [ "${ENABLE_BIAS_T}" = "true" ]; then
    echo "Activating Bias-T for active antenna..."
    /usr/local/bin/rtl_biast -b 1
    sleep 2
    echo
fi

if [ "${HEYWHATSTHAT_ID}" -a ! -f /data/upintheair.json ]; then
    echo "Creating upintheair.json for altitudes ${HEYWHATSTHAT_ID_ALTS-30000}"
    curl -sLo /data/upintheair.json "http://www.heywhatsthat.com/api/upintheair.json?id=${HEYWHATSTHAT_ID}&refraction=0.25&alts=${HEYWHATSTHAT_ID_ALTS-30000}"
    echo
fi

echo "Updating aircraft database"
curl -Lo /usr/local/share/tar1090/aircraft.csv.gz https://github.com/wiedehopf/tar1090-db/raw/csv/aircraft.csv.gz
ls -lh /usr/local/share/tar1090/aircraft.csv.gz
echo

echo "Starting readsb..."
exec /app/readsb "$@"
