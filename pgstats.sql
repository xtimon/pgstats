\echo ========= Total activity `date` =========
SELECT client_addr,
       usename,
       datname,
       count(*)
FROM pg_stat_activity
GROUP BY 1,
         2,
         3
ORDER BY 4 DESC;

\x

\echo
\echo ========= Requests for longer than 30 minutes `date` =========
SELECT client_addr,
       pid,
       usename,
       datname,
       now() - xact_start AS xact_age,
       now() - query_start AS query_age,
       query
FROM pg_stat_activity
WHERE (now() - xact_start) > interval '30 minutes'
   OR (now() - query_start) > interval '30 minutes'
ORDER BY query_start;

\echo
\echo ========= Bad transactions `date` =========
SELECT pid,
       datname,
       xact_start AS xact_age,
       state,
       query
FROM pg_stat_activity
WHERE STATE IN ('idle in transaction', 'idle in transaction (aborted)');

\echo
\echo ========= Locks `date` =========
SELECT blockeda.datname AS dbname,
       COALESCE(blockingl.relation::regclass::text,blockingl.locktype) AS locked_item,
       blockeda.pid AS blocked_pid,
       blockeda.query AS blocked_query,
       blockedl.mode AS blocked_mode,
       blockinga.pid AS blocking_pid,
       blockinga.query AS blocking_query,
       blockingl.mode AS blocking_mode
FROM pg_locks blockedl
JOIN pg_stat_activity blockeda ON blockedl.pid = blockeda.pid
JOIN pg_locks blockingl ON(((blockingl.transactionid=blockedl.transactionid)
                                                    OR (blockingl.relation=blockedl.relation
                                                    AND blockingl.locktype=blockedl.locktype))
                                                  AND blockedl.pid != blockingl.pid)
JOIN pg_stat_activity blockinga ON blockingl.pid = blockinga.pid
WHERE NOT blockedl.granted;

\x

\echo
\echo ========= Cache hit ratio `date` =========
SELECT datname,
       blks_hit,
       blks_read,
       blks_hit*100/(case when (blks_read+blks_hit) > 0 THEN (blks_read+blks_hit) ELSE 1 END)::float AS buffer_percent
FROM pg_stat_database;

\echo
\echo ========= Anomalies `date` =========
SELECT datname,
       (CASE WHEN (xact_commit+xact_rollback) > 0 THEN (xact_commit*100)/(xact_commit+xact_rollback)::float ELSE 100 END) AS xact_commit_percent,
       deadlocks,
       conflicts,
       temp_files,
       pg_size_pretty(temp_bytes) AS temp_size,
       pg_size_pretty(CASE WHEN temp_files > 0 THEN temp_bytes/temp_files ELSE 0 END) AS avg_temp_file_size
FROM pg_stat_database
WHERE (CASE WHEN (xact_commit+xact_rollback) > 0 THEN (xact_commit*100)/(xact_commit+xact_rollback)::float ELSE 100 END) < 95
   OR deadlocks > 0
   OR conflicts > 0
   OR temp_files > 0;

\echo
\echo ========= Autovacuum queue `date` =========
SELECT c.relname,
              current_setting('autovacuum_vacuum_threshold') AS av_base_thresh,
              current_setting('autovacuum_vacuum_scale_factor') AS av_scale_factor,
              (current_setting('autovacuum_vacuum_threshold')::int + (current_setting('autovacuum_vacuum_scale_factor')::float4 * c.reltuples))::int AS av_thresh,
              n_live_tup,
              n_dead_tup
FROM pg_stat_user_tables s
JOIN pg_class c ON s.relname = c.relname
WHERE s.n_dead_tup > (current_setting('autovacuum_vacuum_threshold')::int + (current_setting('autovacuum_vacuum_scale_factor')::float4 * c.reltuples));

\echo
\echo ========= Write activity `date` =========
SELECT s.relname,
       pg_size_pretty(pg_relation_size(relid)),
       coalesce(n_tup_ins,0) + 2 * coalesce(n_tup_upd,0) - coalesce(n_tup_hot_upd,0) + coalesce(n_tup_del,0) AS total_writes,
       (coalesce(n_tup_hot_upd,0)::float * 100 / (CASE WHEN n_tup_upd > 0 THEN n_tup_upd ELSE 1 END)::float)::numeric(10,2) AS n_hot_upd_percent,
        (SELECT v[1]
         FROM regexp_matches(reloptions::text,E'fillfactor=(\\d+)') AS r(v) LIMIT 1) AS fillfactor
FROM pg_stat_all_tables s
JOIN pg_class c ON c.oid=relid
WHERE coalesce(n_tup_ins,0) + 2 * coalesce(n_tup_upd,0) - coalesce(n_tup_hot_upd,0) + coalesce(n_tup_del,0) > 0
ORDER BY total_writes DESC;

\echo
\echo ========= Candidates for index creation `date` =========
SELECT relname,
              pg_size_pretty(pg_relation_size(relname::regclass)) AS SIZE,
              seq_scan,
              seq_tup_read,
              (seq_tup_read/seq_scan) AS seq_tup_avg
FROM pg_stat_user_tables
WHERE seq_tup_read > 0
ORDER BY pg_relation_size(relname::regclass) DESC,
         3 DESC;

\echo
\echo ========= List of unused indexes `date` =========
SELECT schemaname,
       indexrelname,
       idx_scan,
       idx_tup_read,
       idx_tup_fetch
FROM pg_stat_all_indexes
WHERE idx_scan = 0
   AND schemaname!='pg_toast'
   AND schemaname!='pg_catalog';
