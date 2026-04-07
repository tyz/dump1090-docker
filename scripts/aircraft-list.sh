#!/bin/sh

jq -r '.aircraft[] | "\(.hex) \(.r) \(.t) \(.flight) \(.alt_geom) \(.rssi) \(.seen)"' aircraft.json | \
    sort | \
    awk 'BEGIN {
        fmtstr = "%-6s %-6s %-4s %-7s %5s %5s %5s\n"
        printf fmtstr, "ICAO","Reg","Type","Flight","Alt", "RSSI", "Seen"
    }
    {
        printf fmtstr, $1, $2, $3, $4, $5, $6, $7
    }'
