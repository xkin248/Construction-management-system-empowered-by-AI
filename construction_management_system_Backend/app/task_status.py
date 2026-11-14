"""Shared task-state vocabulary.

``completed`` is retained for legacy records.  New worker evidence is approved
by a supervisor and therefore finishes in ``approved``.  Every report, KPI,
AI calculation and client must treat both states as terminal.
"""

from typing import Any


TERMINAL_TASK_STATUSES = frozenset({"approved", "completed"})


def is_terminal_task_status(status: Any) -> bool:
    """Whether a task is finished and must not be counted as active."""
    return str(status or "").strip().lower() in TERMINAL_TASK_STATUSES
