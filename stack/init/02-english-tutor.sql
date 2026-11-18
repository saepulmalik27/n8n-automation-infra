-- english-tutor question bank: reading passages crawled from open-licence sources.
-- Runs on first start; on an existing volume run it once by hand:
--   docker compose exec -T postgres psql -U n8n < init/02-english-tutor.sql
\c knowledge
CREATE SCHEMA IF NOT EXISTS english_tutor;
CREATE TABLE IF NOT EXISTS english_tutor.passages (
  id          bigserial PRIMARY KEY,
  source      text NOT NULL,          -- e.g. simplewiki
  source_id   text NOT NULL,          -- page id at the source
  title       text NOT NULL,
  url         text NOT NULL,
  license     text NOT NULL,          -- attribution is required for CC BY-SA
  body        text NOT NULL,
  word_count  int  NOT NULL,
  crawled_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source, source_id)
);
