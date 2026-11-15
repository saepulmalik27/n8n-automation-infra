-- Private knowledge index (separate database from n8n's own tables).
-- Runs only on the first start, when the Postgres volume is empty.
CREATE DATABASE knowledge;
\c knowledge
CREATE EXTENSION IF NOT EXISTS vector;
