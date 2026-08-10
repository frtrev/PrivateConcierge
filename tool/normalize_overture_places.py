#!/usr/bin/env python3
"""Normalize Overture GeoJSONSeq Places into compact app packages."""

import argparse
import gzip
import json
import math
from pathlib import Path


def app_category(
    primary: str | None,
    basic: str | None = None,
    hierarchy: list[str] | None = None,
    include_all_named: bool = False,
) -> str | None:
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
    if value in {"pharmacy", "drugstore"}:
        return "pharmacy"
    if value in {"cinema", "movie_theater", "theatre", "drive_in_theater"}:
        return "entertainment"
    if not include_all_named:
        return None
    taxonomy = " ".join([value, (basic or "").lower(), *((hierarchy or []))]).lower()
    broad_categories = (
        (("health", "medical", "hospital", "doctor", "dentist"), "medical"),
        (("education", "school", "college", "university"), "education"),
        (("arts_and_entertainment", "entertainment", "cinema", "theatre"), "entertainment"),
        (("shopping", "store", "retail"), "shopping"),
        (("accommodation", "hotel", "lodging"), "lodging"),
        (("sports", "recreation"), "recreation"),
        (("transportation", "transit", "airport"), "transportation"),
        (("service", "business", "office"), "service"),
    )
    for terms, category in broad_categories:
        if any(term in taxonomy for term in terms):
            return category
    return "other"


def is_residential(primary: str | None, basic: str | None, hierarchy: list[str]) -> bool:
    taxonomy = " ".join([primary or "", basic or "", *hierarchy]).lower()
    return any(
        term in taxonomy
        for term in ("residential", "apartment", "housing", "private_residence")
    )


def distance_miles(latitude: float, longitude: float, center: tuple[float, float]) -> float:
    radius_miles = 3958.8
    lat1, lat2 = map(math.radians, (latitude, center[0]))
    delta_lat = lat2 - lat1
    delta_lon = math.radians(center[1] - longitude)
    value = math.sin(delta_lat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lon / 2) ** 2
    return radius_miles * 2 * math.asin(math.sqrt(value))


def normalize(
    source: Path,
    output: Path,
    region_id: str,
    center: tuple[float, float] | None = None,
    radius_miles: float | None = None,
    include_all_named: bool = False,
    include_foursquare: bool = False,
) -> int:
    count = 0
    with source.open(encoding="utf-8") as source_file, gzip.open(output, "wt", encoding="utf-8") as target:
        for line in source_file:
            feature = json.loads(line)
            properties = feature.get("properties") or {}
            sources = properties.get("sources") or []
            if not include_foursquare and any(
                source.get("dataset", "").lower() == "foursquare"
                for source in sources
            ):
                continue
            primary = (properties.get("categories") or {}).get("primary")
            basic = properties.get("basic_category")
            hierarchy = (properties.get("taxonomy") or {}).get("hierarchy") or []
            category = app_category(primary, basic, hierarchy, include_all_named)
            name = (properties.get("names") or {}).get("primary")
            coordinates = (feature.get("geometry") or {}).get("coordinates")
            if (
                not category
                or not name
                or not coordinates
                or len(coordinates) < 2
                or is_residential(primary, basic, hierarchy)
                or properties.get("operating_status") == "permanently_closed"
            ):
                continue
            if center and radius_miles and distance_miles(coordinates[1], coordinates[0], center) > radius_miles:
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
    parser.add_argument("--center", help="Latitude,longitude center for a circular extract")
    parser.add_argument("--radius-miles", type=float)
    parser.add_argument(
        "--include-all-named",
        action="store_true",
        help="Include named non-residential destinations outside the compact category list",
    )
    parser.add_argument(
        "--include-foursquare",
        action="store_true",
        help="Include Apache-2.0 Foursquare-sourced Overture places",
    )
    args = parser.parse_args()
    center = tuple(map(float, args.center.split(","))) if args.center else None
    if bool(center) != bool(args.radius_miles):
        parser.error("--center and --radius-miles must be used together")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(
        normalize(
            args.source,
            args.output,
            args.region_id,
            center,
            args.radius_miles,
            args.include_all_named,
            args.include_foursquare,
        )
    )


if __name__ == "__main__":
    main()
