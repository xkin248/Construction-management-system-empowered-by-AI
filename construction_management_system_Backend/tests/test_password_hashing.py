"""Password hashing regression tests.

New credentials must use bcrypt.  Historical SHA-256 rows remain readable only
long enough for a successful login to upgrade them in ``auth.login``.
"""

import hashlib

from app.routers.auth import hpw, vpw


def test_new_passwords_are_bcrypt_hashed_and_verifiable():
    password_hash = hpw("correct horse battery staple")

    assert password_hash.startswith("$2")
    assert vpw("correct horse battery staple", password_hash)
    assert not vpw("wrong password", password_hash)


def test_legacy_sha256_hash_can_be_verified_for_one_time_upgrade():
    password = "legacy-password"
    legacy_hash = "sha256$" + hashlib.sha256(password.encode()).hexdigest()

    assert vpw(password, legacy_hash)
    assert not vpw("wrong password", legacy_hash)
