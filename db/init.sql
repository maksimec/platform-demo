-- ============================================================
-- BookStore Platform — Database Initialisation Script
-- ============================================================
-- Apply once against an empty bookstore database:
--
--   psql -h localhost -U bookstore -d bookstore -f db/init.sql
--
-- Safe to re-run: all statements use IF NOT EXISTS / ON CONFLICT DO NOTHING.
-- Does NOT drop or truncate existing data.
-- ============================================================


-- ── Schema ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS books (
    id          SERIAL PRIMARY KEY,
    title       VARCHAR(255)   NOT NULL,
    author      VARCHAR(255)   NOT NULL,
    price       NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    description TEXT,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id             SERIAL PRIMARY KEY,
    book_id        INTEGER REFERENCES books(id) ON DELETE SET NULL,
    customer_name  VARCHAR(255) NOT NULL,
    customer_email VARCHAR(255) NOT NULL,
    quantity       INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1),
    created_at     TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS admin_users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP DEFAULT NOW()
);


-- ── Indexes ───────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_orders_book_id    ON orders (book_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_books_created_at  ON books  (created_at DESC);


-- ── Seed: Books ───────────────────────────────────────────────────────
-- 5 realistic DevOps / SRE / programming titles.
-- ON CONFLICT DO NOTHING makes this idempotent.

INSERT INTO books (id, title, author, price, description) VALUES
(1,
 'The Phoenix Project',
 'Gene Kim, Kevin Behr, George Spafford',
 29.99,
 'A novel about IT, DevOps, and helping your business win. Follows Bill, an IT manager thrust into saving a critical project, and the Three Ways of DevOps that transform how his team works.'),

(2,
 'Site Reliability Engineering',
 'Betsy Beyer, Chris Jones, Jennifer Petoff, Niall Richard Murphy',
 49.99,
 'How Google runs production systems. Covers SLOs, error budgets, toil elimination, on-call practices, and the cultural and technical foundations of reliability engineering at scale.'),

(3,
 'The DevOps Handbook',
 'Gene Kim, Jez Humble, Patrick Debois, John Willis',
 34.99,
 'A practical guide to implementing DevOps in any organisation. Details the Three Ways, continuous delivery, telemetry, learning from accidents, and building a generative culture.'),

(4,
 'Kubernetes: Up and Running',
 'Brendan Burns, Joe Beda, Kelsey Hightower',
 44.99,
 'The definitive introduction to Kubernetes from its creators. Covers pods, deployments, services, storage, RBAC, and operating production clusters on major cloud providers.'),

(5,
 'Designing Distributed Systems',
 'Brendan Burns',
 39.99,
 'Patterns and paradigms for scalable, reliable distributed systems. Covers sidecar, ambassador, and adapter single-node patterns as well as scatter/gather, event-driven, and coordinated batch patterns.')
ON CONFLICT (id) DO NOTHING;

-- Reset the sequence so the next INSERT gets id = 6
SELECT setval('books_id_seq', (SELECT MAX(id) FROM books));


-- ── Seed: Admin user ──────────────────────────────────────────────────
-- Username : admin
-- Password : admin123
-- Hash     : bcrypt, 12 rounds, generated with passlib / py-bcrypt
--
-- To replace the password, generate a new hash:
--   python3 -c "import bcrypt; print(bcrypt.hashpw(b'newpassword', bcrypt.gensalt(12)).decode())"
-- Then UPDATE admin_users SET password_hash = '<new-hash>' WHERE username = 'admin';

INSERT INTO admin_users (username, password_hash)
VALUES ('admin', '$2b$12$6jpFFfMMCc3rC5egVvzTE.gwbSw.585FKFMgJ3SuJ6dbxf5mUCao6')
ON CONFLICT (username) DO NOTHING;
