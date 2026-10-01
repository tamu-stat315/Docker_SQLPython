# syntax=docker/dockerfile:1.7
FROM python:3.14.7-slim-trixie@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d

COPY --from=ghcr.io/astral-sh/uv:0.12.10@sha256:2bb3ebca0a796a155094a27773d290c4b074572e6107f171d88d086682fd2500 /uv /uvx /bin/

LABEL org.opencontainers.image.source="https://github.com/tamu-stat315/Docker_SQLPython"
LABEL org.opencontainers.image.description="Python 3.14 and Jupyter environment for STAT 315"
LABEL org.opencontainers.image.licenses="MIT"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates graphviz \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 stat315 \
    && useradd --uid 1000 --gid stat315 --create-home stat315 \
    && mkdir -p /home/stat315/workspace/course_examples \
       /home/stat315/workspace/student_notebooks \
    && chown -R stat315:stat315 /home/stat315

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_COMPILE_BYTECODE_TIMEOUT=600 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PATH="/opt/stat315/.venv/bin:$PATH" \
    PYTHONPATH="/opt/stat315"

WORKDIR /opt/stat315
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --locked --no-install-project --no-dev \
    && uv cache clean

COPY --chown=stat315:stat315 stat315_db.py verify_environment.py ./

USER stat315
WORKDIR /home/stat315/workspace/student_notebooks

EXPOSE 8888

CMD ["jupyter", "lab", "--no-browser", "--ip=0.0.0.0", "--port=8888", "--ServerApp.root_dir=/home/stat315/workspace", "--IdentityProvider.token=stat315"]
