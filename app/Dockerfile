# app/Dockerfile
#
# Multi-stage build. Same approach as the slide.

# ---------------------------------------------------------------------------
# Stage 1: builder. Installs deps into an isolated layer so they can be
# cached and copied into the runtime image.
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS builder

WORKDIR /app

# Install build tools only in this stage. They will NOT be in the final image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
 && rm -rf /var/lib/apt/lists/*

# Copy requirements FIRST so this layer is reused when only app code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: runtime. Slim base, no compilers, no apt cache.
# ---------------------------------------------------------------------------
FROM python:3.12-slim AS runtime

WORKDIR /app

# Install curl (used by the ECS container healthcheck) — tiny.
RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from the builder stage.
COPY --from=builder /install /usr/local

# Copy app code.
COPY main.py .

# Create a non-root user and drop privileges.
# Containers run as root by default. Don't.
RUN useradd --create-home --uid 1001 appuser \
 && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

# uvicorn with one worker — Fargate scales by adding tasks, not workers.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
