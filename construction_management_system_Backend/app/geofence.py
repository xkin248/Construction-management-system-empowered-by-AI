"""
GPS geofencing utility functions
Uses the Haversine formula to calculate the great-circle distance (meters) between two points, used to determine whether a worker is within the site geofence.
"""
import math

EARTH_RADIUS_M = 6371000.0


def distance_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate the distance between two lat/lng coordinates, in meters"""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def is_within_fence(lat: float, lng: float, center_lat: float, center_lng: float, radius_m: float):
    """Returns (whether inside the fence, distance from center in meters)"""
    d = distance_m(center_lat, center_lng, lat, lng)
    return d <= radius_m, round(d, 2)
