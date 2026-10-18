FROM ghcr.io/astral-sh/uv:0.13.1 AS uv
FROM python:3.14-slim
COPY --from=uv /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY src ./src
COPY --chown=10001:10001 .agent_configs ./.agent_configs
RUN uv sync --frozen --no-dev && useradd --create-home --uid 10001 agent
USER agent
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1 ENABLE_SENSITIVE_DATA=false OPTIMIZATION_LOCAL_DIR=/app/.agent_configs
EXPOSE 8088
CMD ["workplace-agent"]
