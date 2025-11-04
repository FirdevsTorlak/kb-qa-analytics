-- KB-QA & Analytics — Core schema (PostgreSQL 16)
-- This schema models a central ITIL Knowledge Database with quality and analytics hooks.

-- Optional extension for text similarity (uncomment if you want to demo duplicate detection)
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE person (
  id            BIGSERIAL PRIMARY KEY,
  display_name  TEXT NOT NULL,
  role          TEXT CHECK (role IN ('OWNER','REVIEWER','AGENT','ANALYST','OTHER')) DEFAULT 'OWNER'
);

CREATE TABLE category (
  id          BIGSERIAL PRIMARY KEY,
  name        TEXT UNIQUE NOT NULL,
  is_critical BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE knowledge_article (
  id             BIGSERIAL PRIMARY KEY,
  title          TEXT NOT NULL,
  body           TEXT NOT NULL,
  state          TEXT NOT NULL CHECK (state IN ('DRAFT','IN_REVIEW','PUBLISHED','RETIRED')),
  owner_id       BIGINT REFERENCES person(id),
  reviewer_id    BIGINT REFERENCES person(id),
  category_id    BIGINT REFERENCES category(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at   TIMESTAMPTZ,
  last_review_at TIMESTAMPTZ,
  helpful_up     INTEGER NOT NULL DEFAULT 0 CHECK (helpful_up >= 0),
  helpful_down   INTEGER NOT NULL DEFAULT 0 CHECK (helpful_down >= 0),
  sp_link        TEXT,            -- placeholder for SharePoint URL
  version_no     INTEGER NOT NULL DEFAULT 1,
  CHECK (length(title) BETWEEN 5 AND 200),
  CHECK (length(body) >= 50)
);

CREATE TABLE tag (
  id   BIGSERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL
);

CREATE TABLE article_tag (
  article_id BIGINT REFERENCES knowledge_article(id) ON DELETE CASCADE,
  tag_id     BIGINT REFERENCES tag(id) ON DELETE CASCADE,
  PRIMARY KEY (article_id, tag_id)
);

CREATE TABLE kedb_problem (
  id           BIGSERIAL PRIMARY KEY,
  category_id  BIGINT REFERENCES category(id),
  opened_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  known_error  BOOLEAN NOT NULL DEFAULT FALSE,
  status       TEXT NOT NULL CHECK (status IN ('OPEN','IN_PROGRESS','CLOSED'))
);

CREATE TABLE incident (
  id          BIGSERIAL PRIMARY KEY,
  category_id BIGINT REFERENCES category(id),
  opened_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at   TIMESTAMPTZ,
  major       BOOLEAN NOT NULL DEFAULT FALSE
);

-- Generic link table to associate articles with Problems/Incidents/Changes
CREATE TABLE article_link (
  article_id BIGINT REFERENCES knowledge_article(id) ON DELETE CASCADE,
  ref_type   TEXT NOT NULL CHECK (ref_type IN ('PROBLEM','INCIDENT','CHANGE')),
  ref_id     BIGINT NOT NULL,
  PRIMARY KEY (article_id, ref_type, ref_id)
);

-- Logs to analyze search gaps and consumption
CREATE TABLE search_log (
  id            BIGSERIAL PRIMARY KEY,
  query_text    TEXT NOT NULL,
  ts            TIMESTAMPTZ NOT NULL DEFAULT now(),
  results_count INTEGER NOT NULL DEFAULT 0 CHECK (results_count >= 0)
);

CREATE TABLE article_view (
  id         BIGSERIAL PRIMARY KEY,
  article_id BIGINT REFERENCES knowledge_article(id) ON DELETE CASCADE,
  ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_hash  TEXT
);

-- (Optional) link checker results for SharePoint/URL sanity
CREATE TABLE link_check (
  url          TEXT PRIMARY KEY,
  status_code  INTEGER NOT NULL,
  checked_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Helpful base indexes (FKs and common filters)
CREATE INDEX IF NOT EXISTS idx_article_cat ON knowledge_article(category_id);
CREATE INDEX IF NOT EXISTS idx_article_state ON knowledge_article(state);
CREATE INDEX IF NOT EXISTS idx_article_published_at ON knowledge_article(published_at);

CREATE INDEX IF NOT EXISTS idx_article_view_article_ts ON article_view(article_id, ts);
CREATE INDEX IF NOT EXISTS idx_search_log_ts ON search_log(ts);
CREATE INDEX IF NOT EXISTS idx_incident_category_opened ON incident(category_id, opened_at);
CREATE INDEX IF NOT EXISTS idx_kedb_category ON kedb_problem(category_id);