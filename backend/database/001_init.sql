-- 001_init.sql — initial PromptForge RAG schema (PostgreSQL 16 + pgvector)
--
-- Versioned migration: changing the embedding dimension requires a new
-- migration + full re-embed plan (see codepress-review-rules.md). Do not edit
-- this file after it has been applied; add 002_*.sql instead.
--
-- NOTE: EMBEDDING_DIM (1536) must match the embedding model configured in
-- backend/app/core/ (e.g. OpenAI text-embedding-3-small / ada-002 = 1536).
-- Changing the model without a migration + re-index plan must fail review.
--
-- NOTE: users is identity-only for US-1.2 (satisfies "schema mapped out for
-- Users"). No login/JWT endpoints yet — password_hash is reserved for the
-- future auth story. documents/chat_sessions scope to users(id) via FK so
-- every pgvector query can filter by tenant BEFORE similarity search.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

-- Identity rows for tenant scoping. Auth implementation (hashing/JWT) is out
-- of scope for US-1.2.
CREATE TABLE IF NOT EXISTS users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         CITEXT      NOT NULL UNIQUE CHECK (position('@' IN email) > 1),
    password_hash TEXT        NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RAG source documents / chunks. One row per chunk.
CREATE TABLE IF NOT EXISTS documents (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    content    TEXT         NOT NULL CHECK (char_length(content) > 0),
    embedding  vector(1536) NOT NULL,
    metadata   JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Agent chat sessions. One row per conversation.
CREATE TABLE IF NOT EXISTS chat_sessions (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title      TEXT        NOT NULL DEFAULT 'New chat',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Similarity search index (HNSW, cosine distance — the standard pgvector RAG index).
CREATE INDEX IF NOT EXISTS documents_embedding_hnsw_idx
    ON documents USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Tenant-scoped lookup indexes: all pgvector queries must filter by user scope
-- BEFORE similarity search (see codepress-review-rules.md).
CREATE INDEX IF NOT EXISTS documents_user_created_idx
    ON documents (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS chat_sessions_user_updated_idx
    ON chat_sessions (user_id, updated_at DESC);
