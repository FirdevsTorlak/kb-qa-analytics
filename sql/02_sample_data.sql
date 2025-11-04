-- Seed data for demo

-- People
INSERT INTO person (display_name, role) VALUES
  ('Alice Bauer','OWNER'),
  ('Bob König','REVIEWER'),
  ('Cara Öz','ANALYST'),
  ('Dennis Roth','AGENT');

-- Categories
INSERT INTO category (name, is_critical) VALUES
  ('Identity & Access', true),
  ('Networking', true),
  ('Endpoints', false),
  ('Messaging', false);

-- Tags
INSERT INTO tag (name) VALUES
  ('onboarding'), ('vpn'), ('kb-policy'), ('incident-playbook'), ('sharepoint');

-- Articles
INSERT INTO knowledge_article
  (title, body, state, owner_id, reviewer_id, category_id, created_at, published_at, last_review_at, helpful_up, helpful_down, sp_link, version_no)
VALUES
  ('Reset MFA for VIP users',
   repeat('Procedure step. ', 20),
   'PUBLISHED', 1, 2, 1, now() - interval '200 days', now() - interval '180 days', now() - interval '170 days', 120, 30, 'https://sharepoint/kb/0001', 3),
  ('VPN troubleshooting L3 failures',
   repeat('Check routes and DNS. ', 30),
   'PUBLISHED', 1, 2, 2, now() - interval '40 days',  now() - interval '30 days',  now() - interval '20 days', 95, 80, 'https://sharepoint/kb/0002', 2),
  ('Standard laptop imaging',
   repeat('SOP content. ', 25),
   'IN_REVIEW', 1, 2, 3, now() - interval '10 days', NULL, NULL, 10, 1, 'https://sharepoint/kb/0003', 1),
  ('Mailbox restore after accidental delete',
   repeat('EAC steps. ', 25),
   'PUBLISHED', 1, 2, 4, now() - interval '400 days', now() - interval '395 days', now() - interval '360 days', 12, 2, 'https://sharepoint/kb/0004', 1),
  ('VPN split-tunnel policy',
   repeat('Policy text. ', 30),
   'PUBLISHED', 1, 2, 2, now() - interval '90 days', now() - interval '85 days', NULL, 40, 70, 'https://sharepoint/kb/0005', 1);

-- Article tags
INSERT INTO article_tag VALUES
  (1,1), (1,3), (2,2), (2,4), (3,1), (4,4), (5,2), (5,3);

-- Problems (KEDB)
INSERT INTO kedb_problem (category_id, opened_at, known_error, status) VALUES
  (2, now() - interval '120 days', true,  'OPEN'),
  (1, now() - interval '15 days',  true,  'IN_PROGRESS'),
  (4, now() - interval '60 days',  false, 'CLOSED');

-- Incidents
INSERT INTO incident (category_id, opened_at, closed_at, major) VALUES
  (2, now() - interval '29 days', now() - interval '28 days', false),
  (2, now() - interval '27 days', now() - interval '26 days', true),
  (1, now() - interval '12 days', now() - interval '11 days', false),
  (4, now() - interval '3 days',  NULL,                        false);

-- Links between articles and records
INSERT INTO article_link (article_id, ref_type, ref_id) VALUES
  (1, 'INCIDENT', 1),
  (1, 'INCIDENT', 2),
  (2, 'PROBLEM',  1),
  (4, 'INCIDENT', 3);

-- Search logs (some returning zero results)
INSERT INTO search_log (query_text, ts, results_count) VALUES
  ('vpn error 809', now() - interval '10 days', 0),
  ('vip mfa reset', now() - interval '9 days',  2),
  ('split tunnel policy', now() - interval '8 days', 0),
  ('mailbox restore', now() - interval '7 days', 1),
  ('kerberos failure', now() - interval '6 days', 0),
  ('vpn l3 fail', now() - interval '5 days', 0),
  ('bitlocker key', now() - interval '4 days', 3),
  ('vip onboarding', now() - interval '3 days', 0),
  ('outlook archive', now() - interval '2 days', 1),
  ('dns leak', now() - interval '1 days', 0);

-- Views (consumption) — concentrate article 2 to demonstrate poor helpful ratio
INSERT INTO article_view (article_id, ts, user_hash) SELECT 2, now() - (i||' hours')::interval, md5(i::text)
FROM generate_series(1, 250) AS i;
INSERT INTO article_view (article_id, ts, user_hash) SELECT 1, now() - (i||' hours')::interval, md5(('a'||i)::text)
FROM generate_series(1, 180) AS i;
INSERT INTO article_view (article_id, ts, user_hash) SELECT 4, now() - (i||' hours')::interval, md5(('b'||i)::text)
FROM generate_series(1, 60) AS i;

-- Link check (simulate some broken SharePoint links)
INSERT INTO link_check (url, status_code, checked_at) VALUES
  ('https://sharepoint/kb/0001', 200, now() - interval '1 day'),
  ('https://sharepoint/kb/0002', 404, now() - interval '1 day'),
  ('https://sharepoint/kb/0003', 500, now() - interval '2 days'),
  ('https://sharepoint/kb/0004', 200, now() - interval '2 days'),
  ('https://sharepoint/kb/0005', 404, now() - interval '2 days');