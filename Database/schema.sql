-- =====================================================================
-- RAG Knowledge Base Assistant — Supabase / Postgres Schema
-- =====================================================================
-- Run this entire file once against a fresh Supabase project
-- (SQL Editor -> New Query -> paste -> Run).
--
-- It is fully idempotent: safe to re-run without duplicating objects.
-- =====================================================================

-- 1. Extensions --------------------------------------------------------

create extension if not exists vector;
create extension if not exists pgcrypto; -- for gen_random_uuid()

-- 2. Tables --------------------------------------------------------------

-- One row per source markdown document
create table if not exists public.documents (
    id            uuid primary key default gen_random_uuid(),
    title         text not null,
    source_path   text not null unique,       -- e.g. "accepting-payments.md"
    checksum      text,                        -- sha256 of file contents, used to skip re-ingestion
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

-- One row per semantic chunk of a document
create table if not exists public.document_chunks (
    id            uuid primary key default gen_random_uuid(),
    document_id   uuid not null references public.documents(id) on delete cascade,
    document_title text not null,               -- denormalized for fast citation lookup
    section       text not null default 'General',  -- nearest markdown heading
    chunk_index   int not null,                 -- order of chunk within document
    content       text not null,                -- raw chunk text sent to the LLM
    token_count   int,
    embedding     vector(1536) not null,        -- text-embedding-3-small = 1536 dims
    metadata      jsonb not null default '{}'::jsonb,
    created_at    timestamptz not null default now()
);

comment on table public.documents is 'Source markdown files ingested into the knowledge base';
comment on table public.document_chunks is 'Semantic chunks with OpenAI text-embedding-3-small vectors';

-- 3. Indexes --------------------------------------------------------------

-- Vector similarity index (HNSW - fast + accurate for < few million rows)
create index if not exists document_chunks_embedding_hnsw_idx
    on public.document_chunks
    using hnsw (embedding vector_cosine_ops)
    with (m = 16, ef_construction = 64);

-- Fallback / additional IVFFlat index (uncomment if you prefer IVFFlat over HNSW)
-- create index if not exists document_chunks_embedding_ivfflat_idx
--     on public.document_chunks
--     using ivfflat (embedding vector_cosine_ops)
--     with (lists = 100);

create index if not exists document_chunks_document_id_idx
    on public.document_chunks (document_id);

create index if not exists documents_source_path_idx
    on public.documents (source_path);

-- 4. updated_at trigger ----------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists documents_set_updated_at on public.documents;
create trigger documents_set_updated_at
    before update on public.documents
    for each row
    execute function public.set_updated_at();

-- 5. Similarity search RPC (Top-K retrieval) --------------------------------
-- Called from n8n via: POST /rest/v1/rpc/match_document_chunks
--
-- Parameters:
--   query_embedding  vector(1536)  -- embedding of the user's question
--   match_count      int           -- how many chunks to return (default 5)
--   match_threshold   float         -- minimum cosine similarity (0-1), default 0.0

create or replace function public.match_document_chunks(
    query_embedding vector(1536),
    match_count int default 5,
    match_threshold float default 0.0
)
returns table (
    id uuid,
    document_id uuid,
    document_title text,
    section text,
    chunk_index int,
    content text,
    similarity float
)
language plpgsql
as $$
begin
    return query
    select
        dc.id,
        dc.document_id,
        dc.document_title,
        dc.section,
        dc.chunk_index,
        dc.content,
        1 - (dc.embedding <=> query_embedding) as similarity
    from public.document_chunks dc
    where 1 - (dc.embedding <=> query_embedding) > match_threshold
    order by dc.embedding <=> query_embedding
    limit match_count;
end;
$$;

comment on function public.match_document_chunks is
    'Top-K cosine similarity search over document_chunks. similarity = 1 - cosine_distance (higher = more relevant).';

-- 6. Row Level Security (optional but recommended) --------------------------
-- These tables are only ever accessed by n8n using the service_role key,
-- so RLS can remain enabled with no public policies (default-deny).

alter table public.documents enable row level security;
alter table public.document_chunks enable row level security;

-- No policies are created intentionally: only the service_role key
-- (used server-side by n8n) bypasses RLS. Anonymous/public clients
-- get zero access to raw chunks or embeddings.

-- 7. Sample insert (manual testing only — n8n does this automatically) ------

-- insert into public.documents (title, source_path, checksum)
-- values ('Accepting Payments', 'accepting-payments.md', 'sha256:sample')
-- returning id;

-- insert into public.document_chunks
--   (document_id, document_title, section, chunk_index, content, token_count, embedding)
-- values (
--   '00000000-0000-0000-0000-000000000000', -- replace with real document_id
--   'Accepting Payments',
--   'Overview',
--   0,
--   'Stripe Checkout is the fastest way to start accepting payments online...',
--   42,
--   -- 1536-dim zero vector placeholder, replace with a real embedding array
--   array_fill(0, array[1536])::vector
-- );

-- 8. Handy maintenance queries -----------------------------------------------

-- Count chunks per document
-- select document_title, count(*) from public.document_chunks group by document_title;

-- Delete a document and cascade-delete its chunks
-- delete from public.documents where source_path = 'accepting-payments.md';

-- Test the RPC directly (replace the embedding with a real 1536-length vector)
-- select * from public.match_document_chunks(array_fill(0, array[1536])::vector, 5, 0.0);
