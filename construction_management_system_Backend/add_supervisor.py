"""
Add a site supervisor test account to the Supabase database.
Email: test   Password: test
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Load env
from dotenv import load_dotenv
load_dotenv()

from app.database import SessionLocal
from app.models import Supervisor
import hashlib

def hpw(password: str) -> str:
    """Hash password - same fallback as auth.py"""
    try:
        from passlib.context import CryptContext
        ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=4)
        return ctx.hash(password)
    except Exception:
        return "sha256$" + hashlib.sha256(password.encode()).hexdigest()

def add_supervisor(email: str, password: str, full_name: str, role: str = "site_supervisor"):
    db = SessionLocal()
    try:
        # Check if already exists
        existing = db.query(Supervisor).filter(Supervisor.email == email.strip().lower()).first()
        if existing:
            print(f"⚠️  Supervisor '{email}' already exists (ID: {existing.supervisor_id})")
            print(f"   Name: {existing.full_name}, Role: {existing.role}")
            # Update password
            existing.password_hash = hpw(password)
            db.commit()
            print(f"   ✅ Password updated to '{password}'")
            return existing

        sup = Supervisor(
            full_name=full_name,
            email=email.strip().lower(),
            password_hash=hpw(password),
            role=role,
            phone="0000000000",
        )
        db.add(sup)
        db.commit()
        db.refresh(sup)
        print(f"✅ Created supervisor:")
        print(f"   ID:       {sup.supervisor_id}")
        print(f"   Name:     {sup.full_name}")
        print(f"   Email:    {sup.email}")
        print(f"   Role:     {sup.role}")
        print(f"   Password: {password}")
        return sup
    except Exception as e:
        db.rollback()
        print(f"❌ Error: {e}")
        import traceback; traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    print("=" * 50)
    print("Adding test site supervisor accounts...")
    print("=" * 50)

    # Test account: email=test, password=test
    add_supervisor(
        email="test",
        password="test",
        full_name="Test Supervisor",
        role="site_supervisor",
    )

    print()

    # Also add admin account just in case
    add_supervisor(
        email="admin@buildsmart.com",
        password="admin123",
        full_name="Admin User",
        role="site_supervisor",
    )

    print()
    print("=" * 50)
    print("Done! You can now log in with:")
    print("  Email: test    Password: test")
    print("  Email: admin@buildsmart.com    Password: admin123")
    print("=" * 50)
