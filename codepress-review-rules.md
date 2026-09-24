# CodePress Review Rules — PromptForge (AI Agent Chat + RAG)

Stack: Python 3.12+ / FastAPI / LangChain / OpenAI / Pydantic v2 / PostgreSQL 16 + pgvector / Next.js 16 App Router / React 19 / TailwindCSS v4 / Docker Compose. Package managers: `uv` (backend), `pnpm` (frontend). Linters: `ruff` (backend), `biome` (frontend).

## Security
- All database queries must use parameterized statements (SQLAlchemy / psycopg parameters — never f-string SQL).
- API keys must never be hardcoded. Must come from env (`OPENAI_API_KEY`, `DATABASE_URL`). Frontend must never reference server secrets; only `NEXT_PUBLIC_*` vars are allowed client-side.
- User input must be validated before use — backend with Pydantic v2 models (`BaseModel`, `Field` constraints), frontend with schema validation before API calls.
- All FastAPI endpoints that handle user data must have authentication/authorization checks; new public endpoints without auth must be explicitly justified in the PR.
- LLM prompts must treat all user input and all retrieved RAG documents as untrusted: never interpolate raw user text into system prompts without delimiters/sanitization; guard against prompt injection and jailbreak exfiltration of system prompts.
- File uploads (for RAG ingestion) must validate MIME type, extension, and size server-side, cap total size, and scan/store outside web root.
- No secrets, tokens, or `.env` values in `docker-compose.yml`, Dockerfiles, logs, or frontend bundles. `DATABASE_URL` default credentials in compose must not be used in production.
- All API endpoints must have rate limiting (slowapi / middleware), especially `/chat`, `/embed`, `/ingest` and any LLM-backed route to prevent cost abuse.
- CORS must be allowlist-based (`allow_origins` explicit), never `["*"]` with credentials.

## Architecture — Backend (FastAPI / Python)
- Python `>=3.12` with full type hints on all new functions; `ruff check` and `ruff format` must pass. Dependencies managed via `uv` / `pyproject.toml` — no pip-freeze dumps, no unpinned LLM deps.
- Follow `backend/app/` layering: `api/` (routers) → `services/` (business/agent/RAG logic) → `models/` (Pydantic + ORM) → `core/` (config, clients, deps). Services should not directly import from other service modules — share via `core/` or dependency injection.
- Routers must use `APIRouter` with prefix/tags, Pydantic request/response models, explicit `status_code`, and `Depends()` for DB sessions / settings / auth. No business logic inside route handlers.
- Use `async def` for I/O-bound endpoints (DB, OpenAI, LangChain calls); never block the event loop with sync HTTP, `time.sleep`, or large in-request embedding loops — offload to background tasks / workers.
- Centralize OpenAI/LangChain client construction in `core/` (singleton with timeout, retries, model name from config). No per-request client creation, no scattered model-name strings.
- Config via `pydantic-settings` (`BaseSettings`); every new env var must be added to `.env.example` and documented.

## Architecture — RAG / AI Agent
- Ingestion pipeline must be deterministic and reviewable: chunking strategy (size/overlap), embedding model name + vector dimension must be constants in config, not magic numbers. Changing embedding model without a migration/re-index plan must fail review.
- All pgvector queries must filter by tenant/user scope *before* similarity search; never return cross-user chunks. `top_k` / score threshold must be configurable with sane defaults and caps (prevent huge context windows).
- Every agent/chat response must persist and/or return source citations (document id + chunk id + score). New LLM routes that drop provenance must fail review.
- Enforce token/cost guards: max context tokens, max iterations for agent loops, request timeout, and max output tokens. Agent loops require a hard iteration cap and stop condition.
- No unbounded chat history sent to the LLM — must use windowed history / summarization with explicit limits.
- Prompts and system instructions must live in versioned files/modules (not inline strings scattered in handlers) so diffs are reviewable.
- Streaming responses (SSE) must handle client disconnects and always close DB sessions / LLM streams in `finally`.

## Architecture — Frontend (Next.js 16 / React 19 / TailwindCSS v4)
- App Router conventions only: `src/app/` routing, `layout.tsx` / `loading.tsx` / `error.tsx` where appropriate. New pages must include `metadata`. Verify against installed Next.js docs — do not use removed/renamed APIs from training data.
- Default to React Server Components; add `"use client"` only for interactivity (chat input, streaming UI). Never import server-only code (DB, API keys) into client components.
- Chat UI must handle streaming, loading, error, and empty states; no `any` types — strict TypeScript, typed API responses in `src/lib/`. `biome check` must pass.
- Data fetching to FastAPI goes through `src/lib/` helpers with base URL from env, timeout + error handling; no hardcoded `localhost:8000` URLs.
- Styling with TailwindCSS v4 only (no new global CSS / CSS modules unless justified); support `dark:` variants for chat surfaces; use `next/image` for images.
- No secrets in frontend code. API keys, `DATABASE_URL`, OpenAI keys in `frontend/` must fail review.

## Database — PostgreSQL 16 + pgvector
- Schema changes must be migrations (Alembic or versioned SQL in `backend/database/`), never manual edits; pgvector extension (`CREATE EXTENSION vector`) and index definitions (`HNSW`/`IVFFlat`) must be in migrations.
- Embedding column dimension must match the embedding model everywhere; changing dimensions requires a migration + re-embed plan.
- Use connection pooling (SQLAlchemy pool / `asyncpg` pool) and request-scoped sessions with guaranteed close. No global cursors, no unclosed sessions in streaming paths.
- Queries must be indexed: vector index for similarity, B-tree on `(user_id, document_id, created_at)`. New RAG query without `EXPLAIN`-sane index usage or with N+1 loading must fail review.
- No destructive migrations without backup strategy; PII in chat logs must have retention/redaction policy.

## Docker / Config / Ops
- `docker-compose.yml` services must pin image versions (e.g. `pgvector/pgvector:pg16`), define `healthcheck` for postgres, use named volumes, and read secrets from env files — never commit real credentials.
- Backend and frontend, when containerized, must run via non-root user, expose only needed ports, and include `/health` checks. Frontend `next build` must pass with no TypeScript errors.
- Every new env var must be added to `.env.example` with a placeholder value; README/docs updated if setup steps change.
- Logs must be structured without PII / prompt contents / API keys; LLM request/response logging must be opt-in and redacted.

## Testing
- All public functions require unit tests (backend: `pytest`; frontend: component/util tests). New `services/` logic without tests must fail review.
- Integration tests required for API endpoints — including RAG paths with mocked embeddings/LLM (no live OpenAI calls in CI) plus at least one pgvector-backed test.
- RAG changes (chunking, retrieval, prompts) must include evaluation evidence: before/after retrieval precision or golden-query chat examples in the PR description.
- Frontend chat changes require loading/error/empty-state coverage; `tsc --noEmit`, `pnpm build`, and `biome check` must pass.
- `uv lock` / `pnpm-lock.yaml` changes must be intentional and minimal — no drive-by dependency upgrades; LLM-adjacent upgrades (`langchain`, `openai`, `next`) require changelog check in PR.
