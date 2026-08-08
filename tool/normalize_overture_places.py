#!/usr/bin/env python3
"""Normalize Overture GeoJSONSeq Places into compact app packages."""

import argparse
import gzip
import json
from pathlib import Path


def app_category(primary: str | None) -> str | None:
    value = (primary or "").lower()
    if "restaurant" in value or value in {"cafe", "coffee_shop", "bakery", "bar"}:
        return "restaurant"
    if "church" in value or value in {"religious_organization", "place_of_worship", "mosque", "synagogue"}:
        return "church"
    if value in {"gas_station", "ev_charging_station"}:
        return "gas"
    if value in {"gym", "fitness_center", "sports_center"}:
        return "gym"
    if "park" in value or value in {"garden", "nature_reserve", "playground"}:
        return "park"
    if "historic" in value or value in {"landmark", "monument", "memorial"}:
        return "historic"
    if "museum" in value or value in {"art_gallery", "visitor_center", "tourist_attraction", "zoo"}:
        return "museum" if "museum" in value else "attraction"
    if value in {"grocery_store", "supermarket", "convenience_store", "farmers_market"}:
        return "grocery"
    return None


def normalize(source: Path, output: Path, region_id: str) -> int:
    count = 0
    with source.open(encoding="utf-8") as source_file, gzip.open(output, "wt", encoding="utf-8") as target:
        for line in source_file:
            feature = json.loads(line)
            properties = feature.get("properties") or {}
            sources = properties.get("sources") or []
            if any(source.get("dataset", "").lower() == "foursquare" for source in sources):
                continue
            primary = (properties.get("categories") or {}).get("primary")
            category = app_category(primary)
            name = (properties.get("names") or {}).get("primary")
            coordinates = (feature.get("geometry") or {}).get("coordinates")
            if not category or not name or not coordinates or len(coordinates) < 2:
                continue
            addresses = properties.get("addresses") or []
            address = (addresses[0].get("freeform") or "") if addresses else ""
            row = {
                "id": f"{region_id}-{feature['id']}",
                "name": name,
                "longitude": coordinates[0],
                "latitude": coordinates[1],
                "category": category,
                "subcategory": primary or category,
                "address": address,
            }
            target.write(json.dumps(row, separators=(",", ":")) + "\n")
            count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("region_id")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(normalize(args.source, args.output, args.region_id))


if __name__ == "__main__":
    main()
