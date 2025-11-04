# KB‑QA & Analytics (PostgreSQL) — Demo

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16.x-blue)
![Docker](https://img.shields.io/badge/Docker-Compose-informational)
![CI](https://img.shields.io/github/actions/workflow/status/OWNER/REPO/postgres-smoke.yml?label=CI%20smoke&logo=github)  
> Replace `OWNER/REPO` above after you push to GitHub to activate the CI badge.

A reproducible **Knowledge Management** mini‑stack that proves:
- a clean relational model for **Knowledge Articles ↔ Incidents ↔ KEDB (Known Errors)**,
- **complex SQL** (CTEs, FULL OUTER JOIN, coverage/division logic, P95 latency),
- **performance tuning** with `EXPLAIN (ANALYZE, BUFFERS)` and targeted indexes,
- **ops maturity** (views for KPIs, read‑only RBAC, backup/restore),
- optional **BI handoff** (CSV starter files).

This project is intentionally small, fast to spin up, and easy to talk through in an interview.

---

## Table of Contents
- [Repository Layout](#1-repository-layout)
- [Quick Start](#2-quick-start)
- [Connecting](#3-connecting-to-the-database)
- [Run the Demo Queries](#4-run-the-demo-queries)
- [Performance Lab](#5-performance-lab-what-to-show--why)
- [BI Handoff (optional)](#6-bi-handoff-optional)
- [Backup / Restore](#7-backup--restore-ops-maturity)
- [Security & Governance (RBAC)](#8-security--governance-rbac)
- [Troubleshooting](#9-troubleshooting)
- [Advanced (optional)](#advanced-optional)
- [ASCII ERD](#ascii-erd)
- [Why this works in interviews](#10-why-this-demo-works-in-interviews)
- [License](#11-license)

---

## 1) Repository Layout

```
kb-qa-analytics/
├─ docker-compose.yml
├─ sql/
│  ├─ schema.sql          # tables + constraints
│  ├─ sample_data.sql     # seed data (articles, incidents, problems, views, search logs, link checks)
│  ├─ queries.sql         # complex analytics + performance lab (run this)
│  └─ advanced_appendix.sql  # optional: FTS, BRIN, MV, pg_stat_statements, data amplifier
├─ scripts/
│  ├─ dev.ps1             # Windows helpers (up/down/reseed/dump/restore)
│  └─ dev.sh              # macOS/Linux helpers
├─ .env.example
├─ .gitignore
├─ LICENSE
└─ README.md
```

> The Postgres container auto‑loads `schema.sql` and `sample_data.sql` on first start.  
> Re‑seed by running `docker compose down -v` → `docker compose up -d`.

---

## 2) Quick Start

**Prerequisites**
- Docker Desktop (or compatible Docker engine)
- (Optional) pgAdmin 4 in your browser (provided as a container) or DBeaver on your host

**Start the stack**
```powershell
cd path\to\kb-qa-analytics
docker compose up -d
docker compose ps
```

**Services & Ports**
- **PostgreSQL 16** → `localhost:5432` (db: `kb`, user: `postgres`, pass: `postgres`)
- **pgAdmin 4** → `http://localhost:5050`  
  Defaults (customize in `docker-compose.yml`):
  - Email: `admin@local` (or `admin@example.com`)
  - Password: `admin`

> If you change pgAdmin env vars, recreate that container:  
> `docker compose stop pgadmin && docker compose rm -f pgadmin && docker compose up -d pgadmin`

---

## 3) Connecting to the Database

### 3.1 pgAdmin (web UI in Docker)
1. Open `http://localhost:5050` and log in.  
2. **Add New Server**  
   - **General / Name:** `KB Local`  
   - **Connection / Host name:** `db`  ← (Docker service name, not `localhost`)  
   - **Port:** `5432`  
   - **Maintenance DB:** `postgres`  
   - **Username:** `postgres`  
   - **Password:** `postgres`  
3. Expand **Servers → KB Local → Databases → kb**.  
4. **Right‑click `kb` → Query Tool**. Ensure the top bar shows **Database: kb**.

### 3.2 DBeaver (desktop client)
- New Connection → PostgreSQL  
  Host `localhost`, Port `5432`, Database `kb`, User `postgres`, Password `postgres`.

### 3.3 psql (CLI inside the container)
```powershell
docker exec -it kbqa_db psql -U postgres -d kb
```

---

## 4) Run the Demo Queries

Open `sql/queries.sql` in your SQL editor **connected to `kb`** and run it.  
**Highlights for a 3–5 minute demo:**
- **#1 Quality Gate** — published articles missing key fields or too short.  
- **#2 Staleness** — not reviewed in ≥180 days.  
- **#3 Coverage (division)** — authors with ≥1 article in every **critical** category.  
- **#4 Search Gaps** — top zero‑result queries (30d).  
- **#5 Low Helpfulness under High Views** — rewrite candidates.  
- **#6 P95 Publish Lead Time** — hours create → publish.  
- **#9 Monthly Trend** — **CTEs + FULL OUTER JOIN**.  
- **#10 Broken SharePoint Links** — link QC.  
- **#11 Performance Lab** — baseline `EXPLAIN`, create a **composite index**, rerun `EXPLAIN`.

**Tip:** In pgAdmin, select a block and use **Explain Analyze** (Shift+F7).

---

## 5) Performance Lab (what to show & why)

- Baseline filter on `article_view` (`article_id` + recent `ts`) → examine plan.  
- Create a composite index:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_article_view_article_ts
    ON article_view (article_id, ts);
  ```
- Rerun the same `EXPLAIN (ANALYZE, BUFFERS)` and point out:
  - Plan switch (e.g., Seq Scan → Index/Bitmap)
  - Lower execution time
  - Buffer behavior (more efficient page access)

**Optional (hot slice):**
```sql
CREATE INDEX IF NOT EXISTS idx_article4_recent
  ON article_view (ts) WHERE article_id = 4;
```
*Partial = tiny & fast for hotspots; composite = broad coverage.*

---

## 6) BI Handoff (optional)

You can export CSV from pgAdmin/DBeaver in seconds and build a quick dashboard in Power BI:
- `article_views_30d.csv` — daily views by article  
- `search_gaps_30d.csv` — zero‑result queries  

**Workflow**
1. Power BI Desktop → **Get Data → Text/CSV**.  
2. Page: line chart (*date* vs *views*), bar chart (*query_text* vs *hits*).  
3. For live demo, export fresh CSVs from the DB and **Refresh**.

---

## 7) Backup / Restore (ops maturity)

**Create a compressed dump**
```powershell
docker exec -it kbqa_db pg_dump -U postgres -d kb -Fc > kb.dump
```

**Restore to a new database**
```powershell
docker exec -it kbqa_db dropdb  -U postgres --if-exists kb_restored
docker exec -it kbqa_db createdb -U postgres kb_restored
docker cp .\kb.dump kbqa_db:/tmp/kb.dump
docker exec -it kbqa_db pg_restore -U postgres --no-owner --no-privileges --single-transaction -d kb_restored /tmp/kb.dump
```

**Verify in pgAdmin**
```sql
SELECT current_database(), COUNT(*) FROM knowledge_article;
SELECT COUNT(*) FROM article_view;
SELECT COUNT(*) FROM search_log;
```

---

## 8) Security & Governance (RBAC)

A minimal read‑only role for analysts (already included at the end of `queries.sql`):
```sql
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
```
> Demo note: This is a **demo password**. Change or remove in production.

---

## 9) Troubleshooting

**pgAdmin says “CSRF token invalid / token missing”**  
- Open `http://127.0.0.1:5050` in an **Incognito** window, or clear site data.  
- Recreate only pgAdmin (DB stays intact):  
  ```powershell
  docker compose stop pgadmin
  docker compose rm -f pgadmin
  docker compose up -d pgadmin
  ```

**“relation does not exist”**  
- You are executing on the wrong DB (`postgres`). Open Query Tool from **kb**.

**pgAdmin can’t connect to the DB**  
- Use **Host = `db`** (Docker service name), not `localhost`.  
- Check containers: `docker compose ps`.

**Re‑seeding the database**  
```powershell
docker compose down -v
docker compose up -d
```

**Windows path executed as SQL (syntax error near “C:”)**  
- Don’t type file paths into the SQL editor. Use **Open file** or copy‑paste contents.

---

## Advanced (optional)

Run **`sql/advanced_appendix.sql`** to add production‑style capabilities you can demo.

### A) Time‑series Indexing — BRIN on `article_view.ts`
- **Why:** tiny index, excellent for append‑only logs and wide time windows.  
- **Add:**  
  ```sql
  CREATE INDEX IF NOT EXISTS brin_article_view_ts
    ON article_view USING brin (ts)
    WITH (pages_per_range = 128);
  ```

### B) Full‑Text Search (FTS) + GIN (weighted title/body)
- **Why:** faster, better search; pairs with “search gaps” analysis.  
- **Adds:** `fts` column, trigger to maintain it, and a GIN index.  
- **Example:**  
  ```sql
  SELECT id, title, ts_rank_cd(fts, plainto_tsquery('vpn split tunnel')) AS rank
  FROM knowledge_article
  WHERE fts @@ plainto_tsquery('vpn split tunnel')
  ORDER BY rank DESC
  LIMIT 10;
  ```

### C) Materialized View for Monthly Trend
- **Why:** stable dashboard without re‑running heavy joins.  
- **Adds:** `mv_monthly_trend` + UNIQUE index → allows `REFRESH ... CONCURRENTLY`.

### D) Observability — `pg_stat_statements`
- **Why:** data‑driven tuning: find slow/heavy queries.  
- **Requires:** Postgres started with `shared_preload_libraries=pg_stat_statements`.  
- **Docker compose hint:**
  ```yaml
  services:
    db:
      image: postgres:16
      command: ["postgres","-c","shared_preload_libraries=pg_stat_statements"]
  ```
- **Then:** `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;` and run the sample reports.

### E) Data Amplifier (Optional)
- **Why:** add a few hundred thousand rows to make the planner’s choices obvious.  
- **Example:** see the commented `generate_series(...)` block inside `advanced_appendix.sql`.

---

## ASCII ERD

```
 person (id, display_name, role)
    ↑         ↑
    │owner_id │reviewer_id
    │         │
 knowledge_article (id, title, body, state, owner_id, reviewer_id, category_id, ... , sp_link)
           │
           │ category_id
           ↓
       category (id, name, is_critical)

 knowledge_article ──< article_tag >── tag
       id ───────────── article_id     tag_id ─────────── id

 knowledge_article ──< article_link >── (ref_type, ref_id)
       id ───────────── article_id      └─ PROBLEM → kedb_problem(id)
                                         └─ (others possible by ref_type)
 kedb_problem (id, category_id, opened_at, known_error, status)
        │
        └─────────────→ category(id)

 incident (id, category_id, opened_at, closed_at, major)
      │
      └──────────────→ category(id)

 article_view (id, article_id, ts, user_hash)
      │
      └──────────────→ knowledge_article(id)

 link_check (url, status_code, checked_at)
      ▲
      └─ matches knowledge_article.sp_link  (logical link; not an FK)
```

---

## 10) Why this demo works in interviews

- **Business‑relevant KPIs** for Knowledge Management (quality, freshness, coverage).  
- **Division logic** (#3) shows set‑based thinking.  
- **CTEs & FULL OUTER** (#9) proves data‑merging skill.  
- **Performance lab** demonstrates reading plans, choosing indexes, and measuring impact.  
- **Ops pieces** (RBAC, backup/restore) show production thinking beyond SELECTs.  
- All of it is **Dockerized** → reproducible, reviewable, portable.

---

## 11) License

MIT 