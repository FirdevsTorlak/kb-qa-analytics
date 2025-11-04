/* ============================================================================
   Advanced Appendix — Indexing, FTS, Materialized Views, and Observability
   for KB-QA & Analytics (PostgreSQL)
   ----------------------------------------------------------------------------
   Purpose:
     This optional add-on complements sql/queries.sql with production-style
     capabilities you can demo: BRIN for time-series, Full-Text Search (FTS),
     a materialized view for trending, and pg_stat_statements for observability.

   Safety:
     - All CREATEs are idempotent where possible (IF NOT EXISTS).
     - Some features require superuser privileges or server flags (noted below).
     - Review comments before running in production environments.

   Tested with PostgreSQL 16.x
   ========================================================================== */


/* ============================================================================
   A) Time‑series Indexing for Large Logs — BRIN on article_view.ts
   ----------------------------------------------------------------------------
   Why:
     BRIN indexes are tiny and ideal for append-only, time-clustered tables.
     They speed up wide time-window scans at minimal storage cost.

   Notes:
     - For best results, keep table naturally ordered by ts (ingest order),
       or periodically CLUSTER/VACUUM to maintain locality.
     - Adjust pages_per_range to your table size (defaults are fine; 128 shown).
   ========================================================================== */

CREATE INDEX IF NOT EXISTS brin_article_view_ts
  ON article_view USING brin (ts)
  WITH (pages_per_range = 128);

-- Demo: compare plan/timing on a wide time range
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM article_view
-- WHERE ts >= now() - interval '60 days';


/* ============================================================================
   B) Full‑Text Search (FTS) with GIN — Weighted Title + Body
   ----------------------------------------------------------------------------
   Why:
     Improves search quality and speed; pairs well with the "search gap" analysis.

   Notes:
     - Uses English dictionary; switch to 'simple' or your locale if needed.
     - Weights: Title=A (strong), Body=B (weaker).
     - Includes a BEFORE trigger to keep a materialized tsvector column in sync.
   ========================================================================== */

-- 1) tsvector column (materialized FTS document)
ALTER TABLE knowledge_article
  ADD COLUMN IF NOT EXISTS fts tsvector;

-- 2) Trigger function: set weighted tsvector
CREATE OR REPLACE FUNCTION ka_fts_refresh() RETURNS trigger AS $$
BEGIN
  NEW.fts :=
    setweight(to_tsvector('english', coalesce(NEW.title,'')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.body ,'')), 'B');
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

-- 3) BEFORE trigger to maintain fts on insert/update
DROP TRIGGER IF EXISTS trg_ka_fts ON knowledge_article;
CREATE TRIGGER trg_ka_fts
BEFORE INSERT OR UPDATE ON knowledge_article
FOR EACH ROW EXECUTE FUNCTION ka_fts_refresh();

-- 4) One‑time backfill for existing rows
UPDATE knowledge_article
SET title = title  -- no-op to fire the trigger
WHERE fts IS NULL;

-- 5) GIN index for fast FTS predicates
CREATE INDEX IF NOT EXISTS idx_ka_fts ON knowledge_article USING gin (fts);

-- 6) Usage examples
-- Exact_phrase: plainto_tsquery OR to_tsquery for fine control
-- SELECT id, title, ts_rank_cd(fts, plainto_tsquery('vpn split tunnel')) AS rank
-- FROM knowledge_article
-- WHERE fts @@ plainto_tsquery('vpn split tunnel')
-- ORDER BY rank DESC, id
-- LIMIT 10;

-- Prefix search example (use to_tsquery with ':*')
-- SELECT id, title
-- FROM knowledge_article
-- WHERE fts @@ to_tsquery('vpn:* & split:*');


/* ============================================================================
   C) Monthly Trend as a Materialized View (MV) + Indexes
   ----------------------------------------------------------------------------
   Why:
     Stable dashboards without re-running heavy joins. MV can be refreshed
     periodically or on-demand; with a UNIQUE index you can REFRESH CONCURRENTLY.

   Steps:
     - Create MV
     - Create UNIQUE index to enable CONCURRENT refresh
     - Refresh MV when needed
   ========================================================================== */

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_monthly_trend AS
WITH m AS (
  SELECT date_trunc('month', published_at) AS mth,
         category_id,
         COUNT(*) AS cnt
  FROM knowledge_article
  WHERE published_at IS NOT NULL
  GROUP BY 1, 2
),
i AS (
  SELECT date_trunc('month', opened_at) AS mth,
         category_id,
         COUNT(*) AS cnt
  FROM incident
  GROUP BY 1, 2
)
SELECT COALESCE(m.mth, i.mth)                 AS mth,
       COALESCE(m.category_id, i.category_id) AS category_id,
       COALESCE(m.cnt, 0)                     AS articles,
       COALESCE(i.cnt, 0)                     AS incidents
FROM m
FULL JOIN i
  ON m.mth = i.mth
 AND m.category_id = i.category_id;

-- UNIQUE index enables: REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_trend_mth_cat
  ON mv_monthly_trend (mth, category_id);

-- Refresh options:
-- REFRESH MATERIALIZED VIEW mv_monthly_trend;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_trend;  -- requires UNIQUE index


/* ============================================================================
   D) Observability — pg_stat_statements (Top Queries)
   ----------------------------------------------------------------------------
   Why:
     Data-driven tuning: find slowest/heaviest queries across the system.

   Requirements:
     - Server parameter: shared_preload_libraries=pg_stat_statements
       (in Docker, set on the Postgres service, then restart container).
     - Then CREATE EXTENSION once per cluster.

   Docker compose hint (YAML):
     services:
       db:
         image: postgres:16
         command:
           - "postgres"
           - "-c"
           - "shared_preload_libraries=pg_stat_statements"

   ========================================================================== */

-- 1) Enable extension (after restart with shared_preload_libraries set)
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- 2) Example reports (uncomment once extension is enabled)

-- Top 10 by mean execution time
-- SELECT query, calls, round(mean_exec_time::numeric,2) AS mean_ms, rows
-- FROM pg_stat_statements
-- ORDER BY mean_exec_time DESC
-- LIMIT 10;

-- Highest total time consumers
-- SELECT query, calls,
--        round(total_exec_time::numeric,2) AS total_ms,
--        round((total_exec_time/sum(total_exec_time) OVER ()) * 100, 2) AS pct
-- FROM pg_stat_statements
-- ORDER BY total_exec_time DESC
-- LIMIT 10;

-- Reset stats (admin-only)
-- SELECT pg_stat_statements_reset();


/* ============================================================================
   E) Data Amplifier (Optional) — Generate Realistic Volume
   ----------------------------------------------------------------------------
   Why:
     Let the planner make interesting choices (Bitmap vs Index vs Seq).
     Adjust the number of rows to your machine.

   Safety:
     - Run in a transaction to be able to ROLLBACK if you insert too much.
     - Or DELETE later by a time predicate.
   ========================================================================== */

-- BEGIN;
-- INSERT INTO article_view (article_id, ts, user_hash)
-- SELECT ((random()*4)::int + 1)                       AS article_id,
--        now() - (random() * interval '60 days')       AS ts,
--        md5(random()::text)                           AS user_hash
-- FROM generate_series(1, 300000);                      -- adjust volume
-- -- ROLLBACK;  -- if it was too much
-- -- or keep and analyze; you can later:
-- -- DELETE FROM article_view WHERE ts < now() - interval '90 days';

