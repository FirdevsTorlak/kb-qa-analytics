/* ============================================================================
   KB-QA & Analytics — Complex Queries + Performance Lab (PostgreSQL)
   ----------------------------------------------------------------------------
   Usage (pgAdmin / DBeaver / psql):
     1) Connect to database: kb
     2) Run sections top → bottom (or cherry-pick)
     3) Perf Lab: baseline → create index → baseline again

   Expected schema (tables):
     person(id, display_name, role)
     category(id, name, is_critical)
     knowledge_article(id, title, body, state, owner_id, reviewer_id,
                       category_id, created_at, published_at, last_review_at,
                       helpful_up, helpful_down, sp_link, version_no)
     tag(id, name)
     article_tag(article_id, tag_id)
     kedb_problem(id, category_id, opened_at, known_error, status)
     incident(id, category_id, opened_at, closed_at, major)
     article_link(article_id, ref_type, ref_id)
     search_log(id, query_text, ts, results_count)
     article_view(id, article_id, ts, user_hash)
     link_check(url, status_code, checked_at)

   Notes:
     - Pure SQL (no \i, no tool-specific commands).
     - Idempotent where appropriate (IF NOT EXISTS).
     - Clean outputs suited for interview demos & CI runs.

   Tested with PostgreSQL 16.x
   ========================================================================== */


/* --------------------------------------------------------------------------
   0) Session sanity (optional)
   -------------------------------------------------------------------------- */

-- Keep output tidy and runs deterministic during demos/CI
SET client_min_messages = WARNING;
SET search_path         = public;
SET timezone            = 'UTC';
SET statement_timeout   = '60s';
SET lock_timeout        = '3s';

-- Ensure planner stats are fresh (harmless if already analyzed)
ANALYZE;

-- Quick row counts (simple, readable; avoid reserved words in aliases)
SELECT 'knowledge_article' AS tbl, COUNT(*) AS rows FROM knowledge_article
UNION ALL
SELECT 'article_view'      AS tbl, COUNT(*) FROM article_view
UNION ALL
SELECT 'search_log'        AS tbl, COUNT(*) FROM search_log
ORDER BY tbl;


/* --------------------------------------------------------------------------
   0.1) Central parameters (tune here during the demo)
   -------------------------------------------------------------------------- */

WITH params AS (
  SELECT
    180::int    AS review_days_threshold,    -- stale if not reviewed in N days
    30::int     AS recent_days_window,       -- lookback window (days)
    100::int    AS min_views_for_attention,  -- min 30-day views to flag
    0.60::float AS helpful_ratio_floor,      -- helpful_up / (up+down)
    2::int      AS perf_demo_article_id,     -- article chosen for perf lab
    20::int     AS search_gap_limit          -- top-N zero-result queries
)
SELECT * FROM params;  -- visible knobs for interview/script logs


/* --------------------------------------------------------------------------
   1) Quality gate — published but missing key fields / too-short content
   -------------------------------------------------------------------------- */

SELECT id, title
FROM knowledge_article
WHERE published_at IS NOT NULL
  AND (
    owner_id IS NULL
    OR reviewer_id IS NULL
    OR char_length(body) < 100
  )
ORDER BY id;


/* --------------------------------------------------------------------------
   2) Staleness — published & not reviewed in the last N days
   -------------------------------------------------------------------------- */

WITH params AS (SELECT 180::int AS review_days_threshold)
SELECT id, title, last_review_at
FROM knowledge_article, params
WHERE state = 'PUBLISHED'
  AND (
    last_review_at IS NULL
    OR last_review_at < now() - (params.review_days_threshold || ' days')::interval
  )
ORDER BY last_review_at NULLS FIRST, id;


/* --------------------------------------------------------------------------
   3) Coverage (division logic) — authors with ≥1 article in every critical cat
   -------------------------------------------------------------------------- */

SELECT p.display_name
FROM person p
JOIN knowledge_article a ON a.owner_id = p.id
JOIN category c ON c.id = a.category_id AND c.is_critical
GROUP BY p.display_name
HAVING COUNT(DISTINCT c.id) = (SELECT COUNT(*) FROM category WHERE is_critical)
ORDER BY p.display_name;


/* --------------------------------------------------------------------------
   4) Search gap analysis — most frequent zero-result queries (last N days)
   -------------------------------------------------------------------------- */

WITH params AS (SELECT 30::int AS recent_days_window, 20::int AS search_gap_limit)
SELECT query_text, COUNT(*) AS hits
FROM search_log, params
WHERE ts >= now() - (params.recent_days_window || ' days')::interval
  AND results_count = 0
GROUP BY query_text
ORDER BY hits DESC, query_text
LIMIT (SELECT search_gap_limit FROM params);


/* --------------------------------------------------------------------------
   5) Low helpfulness under high view volume — candidates to rewrite/curate
   -------------------------------------------------------------------------- */

WITH params AS (
  SELECT 30::int AS recent_days_window,
         100::int AS min_views_for_attention,
         0.60::float AS helpful_ratio_floor
),
s AS (
  SELECT a.id,
         a.title,
         NULLIF(a.helpful_up + a.helpful_down, 0) AS votes,
         (a.helpful_up::float / NULLIF(a.helpful_up + a.helpful_down, 0)) AS helpful_ratio,
         COUNT(v.*) AS views_30d
  FROM knowledge_article a
  LEFT JOIN article_view v
    ON v.article_id = a.id
   AND v.ts >= now() - (SELECT (recent_days_window || ' days')::interval FROM params)
  GROUP BY a.id, a.title, a.helpful_up, a.helpful_down
)
SELECT *
FROM s, params
WHERE views_30d >= params.min_views_for_attention
  AND helpful_ratio < params.helpful_ratio_floor
ORDER BY helpful_ratio ASC NULLS FIRST, views_30d DESC, id;


/* --------------------------------------------------------------------------
   6) Publishing lead time (P95) — hours from create → publish
   -------------------------------------------------------------------------- */

SELECT
  percentile_cont(0.95) WITHIN GROUP (
    ORDER BY EXTRACT(EPOCH FROM (published_at - created_at))/3600.0
  ) AS p95_hours_to_publish
FROM knowledge_article
WHERE published_at IS NOT NULL;


/* --------------------------------------------------------------------------
   7) Duplicate candidates by similar titles (enable pg_trgm if you use it)
   -------------------------------------------------------------------------- */

-- Optional one-time setup (requires superuser privileges):
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX IF NOT EXISTS idx_ka_title_trgm
--   ON knowledge_article USING gin (title gin_trgm_ops);
--
-- Then run:
-- SELECT a1.id AS article_a,
--        a2.id AS article_b,
--        similarity(a1.title, a2.title) AS sim
-- FROM knowledge_article a1
-- JOIN knowledge_article a2 ON a1.id < a2.id
-- WHERE similarity(a1.title, a2.title) > 0.60
-- ORDER BY sim DESC, article_a, article_b;


/* --------------------------------------------------------------------------
   8) KEDB coverage gaps — known errors without a linked KB article
   -------------------------------------------------------------------------- */

SELECT k.id AS problem_id, c.name AS category
FROM kedb_problem k
JOIN category c ON c.id = k.category_id
WHERE k.known_error = true
  AND NOT EXISTS (
    SELECT 1
    FROM article_link l
    WHERE l.ref_type = 'PROBLEM'
      AND l.ref_id = k.id
  )
ORDER BY problem_id;


/* --------------------------------------------------------------------------
   9) Monthly trend — articles vs incidents per category (CTEs + FULL OUTER)
   -------------------------------------------------------------------------- */

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
SELECT COALESCE(m.mth, i.mth)                 AS month,
       COALESCE(m.category_id, i.category_id) AS category_id,
       COALESCE(m.cnt, 0)                     AS articles,
       COALESCE(i.cnt, 0)                     AS incidents
FROM m
FULL JOIN i
  ON m.mth = i.mth
 AND m.category_id = i.category_id
ORDER BY month, category_id;


/* --------------------------------------------------------------------------
   10) Broken SharePoint links — external reference QC
   -------------------------------------------------------------------------- */

SELECT a.id, a.title, a.sp_link
FROM knowledge_article a
JOIN link_check lc ON lc.url = a.sp_link
WHERE lc.status_code <> 200
ORDER BY a.id;


/* ======================================================================
   11) Performance Lab — targeted composite index (before/after EXPLAIN)
   ----------------------------------------------------------------------
   NOTE: EXPLAIN must precede a complete SELECT statement. To keep this
         portable across pgAdmin/psql, constants are inlined here.
   ====================================================================== */

-- a) Baseline (likely Seq Scan if no suitable index exists)
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, COSTS, TIMING)
SELECT *
FROM article_view
WHERE article_id = 2
  AND ts >= now() - INTERVAL '30 days';

-- b) Create composite index (idempotent)
CREATE INDEX IF NOT EXISTS idx_article_view_article_ts
  ON article_view (article_id, ts);

-- c) Rerun and compare (should show index usage + lower timing)
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, COSTS, TIMING)
SELECT *
FROM article_view
WHERE article_id = 2
  AND ts >= now() - INTERVAL '30 days';

-- Optional: targeted partial index example for a hot article slice
-- CREATE INDEX IF NOT EXISTS idx_article4_recent
--   ON article_view (ts) WHERE article_id = 4;

-- Optional: reset to show “pre-index” baseline again later
-- DROP INDEX IF EXISTS idx_article_view_article_ts;
-- DROP INDEX IF EXISTS idx_article4_recent;


/* ======================================================================
   12) Bonus polish — productized checks & RBAC (ops maturity)
   ====================================================================== */

-- Views that productize quality checks (consumable by BI tools)
CREATE OR REPLACE VIEW vw_stale_articles AS
SELECT id, title, last_review_at
FROM knowledge_article
WHERE state = 'PUBLISHED'
  AND (last_review_at IS NULL OR last_review_at < now() - INTERVAL '180 days');

CREATE OR REPLACE VIEW vw_kedb_gaps AS
SELECT k.id AS problem_id, c.name AS category
FROM kedb_problem k
JOIN category c ON c.id = k.category_id
WHERE k.known_error = true
  AND NOT EXISTS (
    SELECT 1 FROM article_link l
    WHERE l.ref_type = 'PROBLEM' AND l.ref_id = k.id
  );

-- Read-only role for analysts (safe reporting without write perms)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'report_reader') THEN
    CREATE ROLE report_reader LOGIN PASSWORD 'Report!2025';
  END IF;
END$$;

GRANT CONNECT ON DATABASE kb TO report_reader;
GRANT USAGE   ON SCHEMA public TO report_reader;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO report_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO report_reader;