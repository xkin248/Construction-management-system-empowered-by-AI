"""Controlled construction specialties used alongside the four worker levels."""
from __future__ import annotations

import json
from typing import Iterable, Optional

SPECIALTIES = (
    "electrical", "plumbing", "welding", "carpentry", "masonry",
    "painting", "tiling", "scaffolding", "roofing", "equipment",
)
_ALIASES = {
    "electrician": "electrical", "wiring": "electrical", "plumber": "plumbing",
    "carpenter": "carpentry", "bricklaying": "masonry", "bricklayer": "masonry",
    "welder": "welding", "scaffolder": "scaffolding", "machine operator": "equipment",
}


def normalise_specialty(value: Optional[str]) -> Optional[str]:
    text = " ".join(str(value or "").strip().lower().replace("-", " ").split())
    if not text:
        return None
    text = _ALIASES.get(text, text)
    if text not in SPECIALTIES:
        raise ValueError("specialty must be one of: " + ", ".join(SPECIALTIES))
    return text


def normalise_specialties(value) -> list[str]:
    if value is None or value == "":
        return []
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            value = [value]
    if not isinstance(value, Iterable) or isinstance(value, (bytes, dict)):
        raise ValueError("specialties must be a list")
    result: list[str] = []
    for raw in value:
        specialty = normalise_specialty(raw)
        if specialty and specialty not in result:
            result.append(specialty)
    return result
