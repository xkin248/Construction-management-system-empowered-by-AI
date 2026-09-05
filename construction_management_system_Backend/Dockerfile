# ── Stage 1: Builder (has gcc + libpq-dev for compiling psycopg2) ──────────────
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
# Install into /install so we can copy just the packages to the runtime image
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: Runtime (no compiler, ~75% smaller image) ─────────────────────────
FROM python:3.11-slim

# Only the runtime shared library is needed (not the dev headers / gcc)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

WORKDIR /app
COPY . .

EXPOSE 8000

# 2 workers: suitable for a small-to-mid sized deployment.
# Adjust --workers based on available CPU cores (typically: 2 × CPU + 1).
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
