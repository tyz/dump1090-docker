#!/usr/bin/env python3

# dump all planes flying within RADIUS_NM, and not higher than MAX_ALT_NM, to the file flyovers.json

import os
import sys
import requests
import json
import gzip
import time
import logging

from math import cos, asin, sqrt, pi
from datetime import datetime, timedelta

# CONFIG
INTERVAL = int(os.getenv("INTERVAL", "10"))
HOME_LAT = float(os.getenv("HOME_LAT", "51.889997"))
HOME_LON = float(os.getenv("HOME_LON", "1.476164"))
TRACES_DIR = os.getenv("TRACES_DIR", "/srv/readsb-ads-b/volatile/traces")
HEATMAP_DIR = os.getenv("HEATMAP_DIR", "/srv/readsb-ads-b/volatile/globe_history")
OUTPUT_FILE = os.getenv("OUTPUT_FILE", "/srv/readsb-ads-b/volatile/flyovers.json")
RADIUS_NM = float(os.getenv("RADIUS_NM", "0.53"))
RADIUS_KM = RADIUS_NM * 1.852
MAX_ALT_NM = float(os.getenv("MAX_ALT_NM", "25000"))
TAR1090_URL = os.getenv("TAR1090_URL", "http://localhost:8080/tar1090/")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
LOG_FORMAT = os.getenv("LOG_FORMAT", "%(asctime)s [%(levelname)s] [%(name)s] %(message)s")

# TODO: RADIUS_NM_NOISY for planes taking of (later: + noisy (b747, a400, etc))

# CONST
TIME_REF = 0
LAT = 1
LON = 2
ALT = 3
GROUND_SPEED = 4
TRACK = 5
BITFIELD = 6  # (altitude_geom << 3) | (rate_geom << 2) | (state->leg_marker << 1) | (state->stale << 0);
RATE = 7
STATE = 8
SECONDS_IN_HOUR = 3600
FEET_TO_M = 3.280839895
NM_TO_KM = 1.852

# LOGGING
level = getattr(logging, LOG_LEVEL, logging.INFO)
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(logging.Formatter(LOG_FORMAT))
logger = logging.getLogger()
logger.setLevel(level)
logger.handlers.clear()
logger.addHandler(handler)

photo_cache = {}


class CachingRequests:

    def __init__(self, key, cache_dir=".cache"):
        self.key = key
        self.cache_dir = cache_dir

    def _get_cache_path(self, url):
        return os.path.join(self.cache_dir, f"{self.key}.json")

    def get(self, url, headers={}, timeout=5):
        if not os.path.exists(self.cache_dir):
            os.makedirs(self.cache_dir)
        cache_path = self._get_cache_path(url)
        if os.path.exists(cache_path):
            with open(cache_path, "r") as f:
                logger.debug(f"Found {url} in cache")
                return json.load(f)
        response = requests.get(url, headers=headers, timeout=timeout)
        if response.status_code == 200:
            data = response.json()
            with open(cache_path, "w") as f:
                json.dump(data, f)
            return data
        return None


def read_json(path, quiet=True, open_func=gzip.open) -> list[dict] | None:
    try:
        with open_func(path, "r") as f:
            return json.load(f)
    except Exception as e:
        if not quiet:
            logger.error(f"{path}: {e}")
        return None


def ts_replay_str(ts) -> str:
    return (datetime.utcfromtimestamp(ts) - timedelta(minutes=3)).strftime("%Y-%m-%d-%H:%M")


def ts_heatmap_file(ts) -> str:
    dt = datetime.utcfromtimestamp(ts)
    fname = dt.hour * 2
    if dt.minute > 30:
        fname += 1
    return dt.strftime(f"{HEATMAP_DIR}/%Y/%m/%d/heatmap/{fname}.bin.ttf")


def ts_str(ts) -> str:
    return datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S") if ts else "None"


def get_aircraft_photo(hex_code) -> dict:
    try:
        url = f"https://api.planespotters.net/pub/photos/hex/{hex_code}"
        headers = {"User-Agent": "HomeAssistant-ADSB-Tracker/1.0"}
        cr = CachingRequests(key=hex_code)
        if (data := cr.get(url, headers=headers, timeout=5)) is not None:
            if "photos" in data and data["photos"]:
                p = data["photos"][0]
                resp = {
                    "thumbnail": p["thumbnail"]["src"],
                    "thumbnail_large": p["thumbnail_large"]["src"],
                    "link": p["link"],
                }
                return resp
    except Exception as e:
        logger.error(f"{hex_code}: Error fetching photo: {e}")
    return None


def distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Return the distance between 2 coordinates in kilometers"""
    p = pi / 180
    a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2
    return 12742 * asin(sqrt(a))


def track_speed(p1, p2) -> float:
    """average speed in km/h between two coordinates"""
    t = abs(p1[TIME_REF] - p2[TIME_REF])
    d = distance(p1[LAT], p1[LON], p2[LAT], p2[LON])
    return round((d / t) * SECONDS_IN_HOUR)


def closest_point(trace) -> list:
    closest_dist = None
    closest_pos = None
    flight = None
    speed = 0
    vspeed = 0
    alt = 0

    for pos, point in enumerate(trace):
        if point[ALT] is not None and point[ALT] != "ground" and point[ALT] > MAX_ALT_NM:
            continue
        d = distance(HOME_LAT, HOME_LON, point[LAT], point[LON])
        if data := point[STATE]:
            """always store, because the closest_pos might not have this data"""
            if not flight:
                flight = data.get("flight")
            vspeed = int(data.get("geom_rate", 0) * NM_TO_KM)
        if not closest_dist or d < closest_dist:
            closest_dist = d
            closest_pos = pos

    if closest_pos is None:
        return [None] * 7

    ts = trace[closest_pos][TIME_REF]
    heading = trace[closest_pos][TRACK]
    if trace[closest_pos][GROUND_SPEED]:
        speed = round(float(trace[closest_pos][GROUND_SPEED]) * NM_TO_KM)
    if not alt and trace[closest_pos][ALT] and trace[closest_pos][ALT] != "ground":
        alt = round(trace[closest_pos][ALT] / FEET_TO_M)

    if not speed and closest_pos:
        """the speed was not reported, calculate it"""
        speed = track_speed(trace[closest_pos - 1], trace[closest_pos])
        logger.debug(f"Calculated speed: {speed} km/h")

    if closest_dist is None:
        return [None] * 7
    return [ts, closest_dist, alt, flight, heading, speed, vspeed]


def merge_traces(full, recent) -> list:
    combined = {}

    ref_t = full["timestamp"]
    for t in full["trace"]:
        key = round(ref_t + t[TIME_REF], 1)
        combined[key] = t[LAT:]

    if len(recent["trace"]):
        added_from_recent = 0
        ref_t = recent["timestamp"]
        for t in recent["trace"]:
            key = round(ref_t + t[TIME_REF], 1)  # round to make time from full and recent match
            if key not in combined:
                combined[key] = t[LAT:]
                added_from_recent += 1
            else:  # debug
                if combined[key][0] != t[LAT:][0] or combined[key][1] != t[LAT:][1]:
                    logger.error(f"Recent trace differs from full for key {key}: combined[key] != t[1:]")
        logger.debug(f"Merged {added_from_recent} of {len(recent['trace'])} from recent")

    return sorted([[x] + y for x, y in combined.items()], key=lambda z: z[0])


def analyze_traces(allow_list=[]):
    all_aircraft = []
    filecount = 0
    cache_hits = 0
    has_changes = False

    for root, dirs, files in os.walk(TRACES_DIR):
        for file_pos, file in enumerate(files):
            aircraft = []

            if not file.endswith(".json") or not file.startswith("trace_full_"):
                continue

            if allow_list:
                ignore_cache = True
                filter_files = [f"trace_full_{x}.json" for x in allow_list]
                if file not in filter_files:
                    continue
                logger.debug(f"Found file in {filter_files}")
            else:
                ignore_cache = False

            full_path = os.path.join(root, file)
            recent_path = os.path.join(root, f"trace_recent_{file[11:-5]}.json")
            nearby_path = os.path.join(root, f"nearby_{file[11:-5]}.json")

            full_mtime = os.path.getmtime(full_path)
            recent_mtime = os.path.getmtime(recent_path)
            try:
                nearby_mtime = os.path.getmtime(nearby_path)
            except FileNotFoundError:
                nearby_mtime = 0

            aircraft = []

            if not ignore_cache and (recent_mtime <= nearby_mtime or full_mtime <= nearby_mtime):
                if (aircraft := read_json(nearby_path, open_func=open)) is not None:
                    updated = False
                    for a in aircraft:
                        if "replay=" not in a["link"]:
                            icao_hex = a["hex"]
                            ts = a["timestamp"]
                            heatmap = ts_heatmap_file(ts)
                            if os.path.exists(heatmap):
                                a["link"] = (
                                    f"{TAR1090_URL}?replay={ts_replay_str(ts)}&icao={icao_hex}"
                                    f"&lat={HOME_LAT}&lon={HOME_LON}&zoom=12.0"
                                )
                                logger.debug(f"{icao_hex}: Updated link to {a['link']}")
                                updated = True
                    if updated:
                        with open(nearby_path, "w") as f:
                            json.dump(aircraft, f)
                    if len(aircraft):
                        all_aircraft += aircraft
                        cache_hits += 1
                    continue

            full_data = read_json(full_path, quiet=False)
            if full_mtime < recent_mtime:
                recent_data = read_json(recent_path, quiet=False)
            else:
                recent_data = {"timestamp": 0, "trace": []}

            if (icao_hex := full_data.get("icao", None)) is None:
                logger.error(f"{full_path}: No 'icao' attr in {full_data}")
                return None

            filecount += 1

            traces = merge_traces(full_data, recent_data)

            logger.debug(
                f"{icao_hex}: Got {len(traces)} traces ({len(full_data['trace'])} full and {len(recent_data['trace'])} recent)"
            )

            current_trace = []
            while True:
                t = traces.pop(0)
                if not traces or (current_trace and (t[TIME_REF] - current_trace[-1][TIME_REF] > 300)):
                    """last entry in list or new flyover (last time seen more than 5 minutes ago)"""
                    if not traces:
                        current_trace.append(t)
                        logger.debug(f"{icao_hex}: End of trace ({len(current_trace)} points)")
                        ts, min_dist_km, alt, flight, heading, speed, vspeed = closest_point(current_trace)
                    else:
                        diff = round(t[TIME_REF] - current_trace[-1][TIME_REF]) if current_trace else 0
                        logger.debug(f"{icao_hex}: New trace ({len(current_trace)} points, {diff} sec since last one)")
                        ts, min_dist_km, alt, flight, heading, speed, vspeed = closest_point(current_trace)
                    if ts:
                        logger.debug(f"{icao_hex}: Closest point: t:{ts_str(ts)} d:{min_dist_km:.1f}km a:{alt}m f:{flight}")
                    else:
                        logger.debug(f"{icao_hex}: Not within distance")
                    current_trace = []
                    if ts is not None and min_dist_km < RADIUS_KM:
                        # TODO: should compare to saved min dist for previously saved entries
                        logger.debug(
                            f"{icao_hex}: New closest point for trace #{len(aircraft)}: {min_dist_km:.1f}km @ {ts_str(ts)}"
                        )
                        heatmap = ts_heatmap_file(ts)
                        link = f"{TAR1090_URL}?icao={icao_hex}&lat={HOME_LAT}&lon={HOME_LON}&zoom=12.0"
                        if os.path.exists(heatmap):
                            link += f"&replay={ts_replay_str(ts)}"
                        else:
                            logger.debug(f"{icao_hex}: Too early, heatmap {heatmap} does not exist yet")
                        has_changes = True
                        aircraft.append(
                            {
                                "hex": icao_hex,
                                "timestamp": int(ts),
                                "flight": flight.strip(),
                                "registration": full_data.get("r", "unknown"),
                                "type": full_data.get("desc", full_data.get("t", "unknown")),
                                "min_dist": int(min_dist_km * 1000),
                                "alt": alt,
                                "heading": heading,
                                "speed": speed,
                                "vspeed": vspeed,
                                "images": get_aircraft_photo(icao_hex),
                                "link": link,
                            }
                        )
                if not traces:
                    break
                current_trace.append(t)

            with open(nearby_path, "w") as f:
                try:
                    if not ignore_cache:
                        json.dump(aircraft, f, indent=2)
                except Exception as e:
                    logger.error(f"Error writing to {nearby_path}: {e}")

            if aircraft:
                all_aircraft += aircraft

    if not has_changes:
        logger.info(f"No changes. Scanned {filecount} new/changed files, loaded {cache_hits} from cache")
        return

    with open(OUTPUT_FILE, "w") as f:
        result = {
            "total": len(all_aircraft),
            "aircraft": all_aircraft,
        }
        json.dump(result, f, indent=2)
        logger.info(f"Wrote {len(all_aircraft)} entries, scanned new/changed {filecount} files, loaded {cache_hits} from cache")


if __name__ == "__main__":
    # allow_list = ["c04a7d", "484a96", "4844c2"]  # NCG01, ZXP06, LIFELN1
    allow_list = sys.argv[1:]
    while True:
        analyze_traces(allow_list=allow_list)
        time.sleep(INTERVAL)
