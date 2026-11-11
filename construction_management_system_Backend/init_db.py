"""
Initialize the database (create tables + seed demo data)
Usage: python init_db.py
"""
from app.database import engine, Base, SessionLocal
from app import models
from app.routers.auth import hpw

Base.metadata.create_all(bind=engine)

db = SessionLocal()
try:
    # 1) Default admin account
    if not db.query(models.Supervisor).filter_by(email="admin@buildsmart.com").first():
        sup = models.Supervisor(
            full_name="Admin Supervisor",
            email="admin@buildsmart.com",
            password_hash=hpw("admin123"),
            phone="0123456789",
            role="site_supervisor",
        )
        db.add(sup)
        db.commit()
        db.refresh(sup)
    else:
        sup = db.query(models.Supervisor).filter_by(email="admin@buildsmart.com").first()

    # 2) Default project (project_id=1), GPS geofence center point + radius
    project = db.get(models.Project, 1)
    if not project:
        project = models.Project(
            project_name="Demo Site",
            location_address="Kuala Lumpur, Malaysia",
            status="in_progress",
            progress=10.0,
            supervisor_id=sup.supervisor_id,
            center_lat=3.1390,
            center_lng=101.6869,
            fence_radius=5000.0,
        )
        db.add(project)
        db.commit()
        db.refresh(project)

    # 3) Default worker (worker_id=1), used by the frontend for check-in demos
    if not db.get(models.Worker, 1):
        worker = models.Worker(
            name="Ali bin Ahmad",
            ic_number="900101-14-5678",
            phone="0198765432",
            trade="electrician",
            project_id=project.project_id,
            has_safety_training=True,
            is_safety_officer=False,
        )
        db.add(worker)
        db.commit()

    # 4) A second project + a few extra workers, so the Workers/Tasks/Attendance
    #    screens have more than a single row to display.
    project2 = db.query(models.Project).filter_by(project_name="Riverside Residency").first()
    if not project2:
        project2 = models.Project(
            project_name="Riverside Residency",
            location_address="Petaling Jaya, Malaysia",
            status="in_progress",
            progress=35.0,
            supervisor_id=sup.supervisor_id,
            center_lat=3.1073,
            center_lng=101.6067,
            fence_radius=5000.0,
        )
        db.add(project2)
        db.commit()
        db.refresh(project2)

    for name, trade, pid in [
        ("Tan Boon Chong", "electrician", project.project_id),
        ("Mohamad Farid", "welder", project2.project_id),
        ("Rajesh Kumar", "scaffolder", project2.project_id),
    ]:
        if not db.query(models.Worker).filter_by(name=name).first():
            db.add(models.Worker(name=name, trade=trade, project_id=pid,
                                  has_safety_training=True, is_safety_officer=False))
    db.commit()

    # 5) A sample task, so the Tasks screen isn't empty
    if db.query(models.Task).count() == 0:
        first_worker = db.query(models.Worker).first()
        db.add(models.Task(
            task_name="Foundation Pile Driving — Block B",
            description="Drive foundation piles for Block B per structural drawings.",
            assigned_worker_id=first_worker.worker_id if first_worker else None,
            project_id=project.project_id,
            priority="high", status="in_progress",
        ))
        db.commit()

    # 6) Default settings row (single-row table, id=1). Attendance time-window
    #    columns use their server defaults (08:00-10:30 / 15:00-17:00 / 12:00-13:00).
    if db.query(models.Settings).count() == 0:
        db.add(models.Settings(id=1))
        db.commit()

    print("Database initialized successfully")
    print("Admin login: admin@buildsmart.com / admin123")
    print(f"Default project ID: {project.project_id}")
finally:
    db.close()
