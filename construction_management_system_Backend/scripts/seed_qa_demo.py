"""Idempotently prepare realistic, clearly-labelled QA data for BuildSmart.

The script never deletes existing data.  It makes the supervisor who owns
``Demo Site`` see five projects in total, with twenty test workers and at
least ten tasks per project.  When an API URL is supplied it also uploads one
plain-text site document per project through the real file API, verifies the
signed download URL, and adds a related in-app notification.

Examples:
    python scripts/seed_qa_demo.py
    python scripts/seed_qa_demo.py --api-url https://example.onrender.com \
      --email admin@buildsmart.com

For non-interactive use, set BS_QA_SEED_PASSWORD instead of entering it at the
prompt.  Credentials are deliberately never written to the database or logs.
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from datetime import date, timedelta
from typing import Iterable

try:
    import requests
except ImportError:  # pragma: no cover - only used for the optional API phase
    requests = None

from app.database import SessionLocal
from app.models import File, FileLink, Notification, Project, Supervisor, Task, TaskWorker, Worker


QA_PREFIX = "QA Demo - "
WORKERS_PER_PROJECT = 20
TASKS_PER_PROJECT = 10

NEW_PROJECTS = (
    {
        "project_name": f"{QA_PREFIX}Harbour View Tower",
        "location_address": "Jalan Tun Razak, Kuala Lumpur, Malaysia",
        "center_lat": 3.1579,
        "center_lng": 101.7123,
    },
    {
        "project_name": f"{QA_PREFIX}Metro Station Upgrade",
        "location_address": "Jalan Bangsar, Kuala Lumpur, Malaysia",
        "center_lat": 3.1290,
        "center_lng": 101.6780,
    },
    {
        "project_name": f"{QA_PREFIX}Greenfield Warehouse",
        "location_address": "Shah Alam, Selangor, Malaysia",
        "center_lat": 3.0738,
        "center_lng": 101.5183,
    },
)

TRADES = ("general_worker", "semi_skilled_worker", "skilled_worker", "foreman")
SPECIALTIES = ("masonry", "electrical", "plumbing", "painting", "carpentry")
TASK_TEMPLATES = (
    ("Site induction and safety briefing", "high", "pending"),
    ("Set out work area", "medium", "in_progress"),
    ("Inspect material delivery", "medium", "pending"),
    ("Prepare work platform", "high", "pending"),
    ("Install first work section", "high", "in_progress"),
    ("Quality-control inspection", "medium", "pending"),
    ("Update daily progress record", "low", "pending"),
    ("Clear and organise work zone", "low", "pending"),
    ("Supervisor walk-through", "medium", "pending"),
    ("Close-out checklist", "medium", "completed"),
)


def owner_and_projects(db):
    demo = db.query(Project).filter(Project.project_name == "Demo Site").first()
    if demo and demo.supervisor_id:
        owner = db.get(Supervisor, demo.supervisor_id)
    else:
        owner = db.query(Supervisor).filter(Supervisor.email == "admin@buildsmart.com").first()
    if owner is None:
        raise RuntimeError("No Demo Site owner or admin supervisor exists; run init_db.py first.")

    for spec in NEW_PROJECTS:
        project = db.query(Project).filter(Project.project_name == spec["project_name"]).first()
        if project is None:
            project = Project(
                **spec,
                supervisor_id=owner.supervisor_id,
                start_date=date.today() - timedelta(days=14),
                end_date=date.today() + timedelta(days=180),
                status="in_progress",
                progress=0.0,
                fence_radius=500.0,
            )
            db.add(project)
    db.commit()

    projects = (
        db.query(Project)
        .filter(Project.supervisor_id == owner.supervisor_id)
        .order_by(Project.project_id.asc())
        .all()
    )
    # Preserve the user's normal projects and the three QA projects.  The seeded
    # account currently owns two normal projects, so this results in five.
    return owner, projects[:2] + [
        p for p in projects if p.project_name.startswith(QA_PREFIX)
    ]


def ensure_workers(db, projects: Iterable[Project]):
    created = 0
    for project in projects:
        workers = db.query(Worker).filter(Worker.project_id == project.project_id).all()
        missing = max(0, WORKERS_PER_PROJECT - len(workers))
        for offset in range(missing):
            ordinal = len(workers) + offset + 1
            token = f"{project.project_id:03d}{ordinal:03d}"
            db.add(Worker(
                name=f"QA Worker {project.project_id:02d}-{ordinal:02d}",
                ic_number=f"990101{token}",
                phone=f"019{project.project_id:03d}{ordinal:04d}",
                email=f"qa.worker.{project.project_id}.{ordinal}@example.test",
                trade=TRADES[(ordinal - 1) % len(TRADES)],
                specialties=[SPECIALTIES[(ordinal - 1) % len(SPECIALTIES)]],
                project_id=project.project_id,
                has_safety_training=True,
                is_safety_officer=(ordinal == 1),
                role="worker",
            ))
            created += 1
    db.commit()
    return created


def ensure_tasks(db, projects: Iterable[Project]):
    created = 0
    for project in projects:
        existing = db.query(Task).filter(Task.project_id == project.project_id).count()
        workers = db.query(Worker).filter(Worker.project_id == project.project_id).order_by(Worker.worker_id).all()
        if not workers:
            raise RuntimeError(f"Project {project.project_id} has no workers after seeding.")
        for ordinal in range(existing + 1, TASKS_PER_PROJECT + 1):
            title, priority, status = TASK_TEMPLATES[(ordinal - 1) % len(TASK_TEMPLATES)]
            worker = workers[(ordinal - 1) % len(workers)]
            task = Task(
                task_name=f"QA Demo {ordinal:02d}: {title}",
                description=(
                    f"QA test task {ordinal} for {project.project_name}. "
                    "Created for local testing; no real site work is required."
                ),
                project_id=project.project_id,
                assigned_worker_id=worker.worker_id,
                priority=priority,
                status=status,
                trade=worker.trade,
                required_specialty=(worker.specialties or [None])[0],
                due_date=date.today() + timedelta(days=ordinal * 2),
                progress={"pending": 0, "in_progress": 50, "completed": 100}[status],
            )
            db.add(task)
            db.flush()
            db.add(TaskWorker(task_id=task.task_id, worker_id=worker.worker_id))
            created += 1
    db.commit()
    return created


def document_bytes(project: Project) -> bytes:
    return (
        "BuildSmart QA Demo Document\n"
        "===========================\n\n"
        f"Project: {project.project_name}\n"
        f"Project ID: {project.project_id}\n"
        f"Generated: {date.today().isoformat()}\n\n"
        "This is a harmless test document. It verifies that the project Files "
        "screen can list, open, and download an uploaded document.\n"
    ).encode("utf-8")


def api_login(base_url: str, email: str, password: str) -> str:
    if requests is None:
        raise RuntimeError("The requests package is required for --api-url.")
    response = requests.post(
        f"{base_url}/api/auth/login",
        data={"username": email, "password": password},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["access_token"]


def ensure_documents_and_notifications(db, projects, base_url: str, token: str, owner: Supervisor):
    headers = {"Authorization": f"Bearer {token}"}
    verified = []
    for project in projects:
        name = f"QA-Demo-Project-{project.project_id}-Site-Checklist.txt"
        existing = db.query(File).filter(
            File.project_id == project.project_id,
            File.original_name == name,
        ).first()
        if existing is None:
            response = requests.post(
                f"{base_url}/api/files/upload",
                headers=headers,
                params={"project_id": project.project_id, "file_category": "documents"},
                files={"file": (name, document_bytes(project), "text/plain")},
                timeout=45,
            )
            response.raise_for_status()
            file_id = int(response.json()["file_id"])
            existing = db.get(File, file_id)
            if existing is None:
                raise RuntimeError(f"Upload returned file {file_id}, but it is not in the database.")

        link = db.query(FileLink).filter(
            FileLink.file_id == existing.file_id,
            FileLink.entity_type == "project",
            FileLink.entity_id == project.project_id,
        ).first()
        if link is None:
            db.add(FileLink(file_id=existing.file_id, entity_type="project", entity_id=project.project_id))

        notification_title = f"QA document ready: {project.project_name}"
        notice = db.query(Notification).filter(
            Notification.supervisor_id == owner.supervisor_id,
            Notification.title == notification_title,
        ).first()
        if notice is None:
            db.add(Notification(
                supervisor_id=owner.supervisor_id,
                notification_type="document",
                title=notification_title,
                content=f"Open or download {name} from Project Files.",
                related_entity_type="file",
                related_entity_id=existing.file_id,
            ))
        db.commit()

        link_response = requests.get(
            f"{base_url}/api/files/{existing.file_id}/download-link",
            headers=headers,
            params={"ttl": 300},
            timeout=30,
        )
        link_response.raise_for_status()
        download_url = link_response.json()["download_url"]
        download = requests.get(download_url, timeout=45)
        download.raise_for_status()
        expected = document_bytes(project)
        if download.content != expected:
            raise RuntimeError(f"Downloaded content for file {existing.file_id} did not match the upload.")
        verified.append(existing.file_id)
    return verified


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-url", help="Deployed or local API base URL, e.g. https://api.example.com")
    parser.add_argument("--email", default="admin@buildsmart.com", help="Supervisor account used for file upload")
    parser.add_argument("--password", help="Supervisor password (or set BS_QA_SEED_PASSWORD)")
    args = parser.parse_args()

    base_url = (args.api_url or "").rstrip("/")
    with SessionLocal() as db:
        owner, projects = owner_and_projects(db)
        if len(projects) != 5:
            raise RuntimeError(f"Expected five visible QA projects, found {len(projects)}.")
        workers_created = ensure_workers(db, projects)
        tasks_created = ensure_tasks(db, projects)

        result = {
            "supervisor_id": owner.supervisor_id,
            "project_ids": [p.project_id for p in projects],
            "workers_created": workers_created,
            "tasks_created": tasks_created,
            "workers_visible": db.query(Worker).filter(Worker.project_id.in_([p.project_id for p in projects])).count(),
            "tasks_per_project": {
                p.project_id: db.query(Task).filter(Task.project_id == p.project_id).count()
                for p in projects
            },
        }

        if base_url:
            password = args.password or os.getenv("BS_QA_SEED_PASSWORD")
            if not password:
                password = getpass.getpass("Supervisor password for file upload: ")
            token = api_login(base_url, args.email, password)
            result["verified_file_ids"] = ensure_documents_and_notifications(
                db, projects, base_url, token, owner
            )
        print(result)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"QA seed failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
