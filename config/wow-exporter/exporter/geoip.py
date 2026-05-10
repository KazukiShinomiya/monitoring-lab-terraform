import logging
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

try:
    import geoip2.database
    _GEOIP_AVAILABLE = True
except ImportError:
    _GEOIP_AVAILABLE = False

_reader = None
_asn_reader = None


def init(db_path: str) -> bool:
    global _reader
    if not _GEOIP_AVAILABLE:
        logger.warning("geoip2 not installed, GeoIP disabled")
        return False
    try:
        _reader = geoip2.database.Reader(db_path)
        logger.info("GeoIP database loaded: %s", db_path)
        return True
    except FileNotFoundError:
        logger.warning("GeoIP database not found: %s", db_path)
        return False


def init_asn(db_path: str) -> bool:
    global _asn_reader
    if not _GEOIP_AVAILABLE:
        return False
    try:
        _asn_reader = geoip2.database.Reader(db_path)
        logger.info("GeoIP ASN database loaded: %s", db_path)
        return True
    except FileNotFoundError:
        logger.warning("GeoIP ASN database not found: %s", db_path)
        return False


def lookup(ip: str) -> Tuple[Optional[str], Optional[str]]:
    """Returns (country_code, country_name) or (None, None) on failure."""
    if _reader is None:
        return None, None
    try:
        response = _reader.country(ip)
        return response.country.iso_code, response.country.name
    except Exception:
        return None, None


def lookup_asn(ip: str) -> Tuple[Optional[str], Optional[str]]:
    """Returns (asn_string, org_name) e.g. ("AS16509", "Amazon.com") or (None, None)."""
    if _asn_reader is None:
        return None, None
    try:
        response = _asn_reader.asn(ip)
        asn = f"AS{response.autonomous_system_number}"
        org = response.autonomous_system_organization or asn
        return asn, org
    except Exception:
        return None, None
