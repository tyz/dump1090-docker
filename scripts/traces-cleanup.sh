#!/bin/bash

GH_DIR=/srv/readsb-ads-b/volatile/globe_history
TR_DIR=/srv/readsb-ads-b/volatile/traces

rm -fv ${GH_DIR}/*/*/*/traces/*/*.json

for ntrace in ${TR_DIR}/*/nearby_*.json; do
    D=$(dirname "${ntrace}")
    F=$(basename "${ntrace}")
    ICAO=${F:7:6}
    [ -f "${D}/trace_full_${ICAO}.json" ] || rm -v "${ntrace}"
done
