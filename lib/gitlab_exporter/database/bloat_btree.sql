-- Originally from: https://github.com/ioguix/pgsql-bloat-estimation/blob/master/btree/btree_bloat.sql
--
-- Rewritten to use CROSS JOIN LATERAL stages so this query stays in sync with the
-- `postgres_index_bloat_estimate(p_schema, p_idxname)` function used by the main GitLab
-- application's reindexing pipeline:
-- https://gitlab.com/gitlab-org/gitlab/-/blob/master/db/migrate/20260526120000_add_postgres_index_bloat_estimate_function.rb
--
-- Expanding the index columns inside a LATERAL join (instead of putting a set-returning
-- function such as generate_series in the SELECT list) avoids the ProjectSet barrier that
-- prevents the planner from pushing predicates down. See:
-- https://gitlab.com/gitlab-org/gitlab/-/work_items/569363
-- https://gitlab.com/gitlab-org/gitlab/-/work_items/599210
--
-- WARNING: executed with a non-superuser role, the query inspects only indexes on tables you are granted to read.
-- WARNING: rows with is_na = 't' are known to have bad statistics ("name" type is not supported).
-- This query is compatible with PostgreSQL 9.3 and after (LATERAL joins).
--
-- Note: unlike the previous ioguix-style query, this form does NOT need to materialize
-- pg_stats to stay fast on PostgreSQL 17. The old query joined pg_stats once as a single
-- large join that the PG17 planner badly underestimated (see f18ac4b); here pg_stats is
-- looked up per index inside the LATERAL, resolving through the pg_statistic indexes, so
-- there is no single join for the planner to misestimate.
SELECT
  current_database(),
  n.nspname AS schemaname,
  ct.relname AS tblname,
  ci.relname AS object_name,
  c.bs * ci.relpages::bigint AS real_size,
  c.bs * (ci.relpages - bloat.est_pages)::bigint AS extra_size,
  100 * (ci.relpages - bloat.est_pages)::float / ci.relpages AS extra_ratio,
  c.fillfactor,
  CASE WHEN ci.relpages > bloat.est_pages_ff
    THEN c.bs * (ci.relpages - bloat.est_pages_ff)
    ELSE 0
  END AS bloat_size,
  100 * (ci.relpages - bloat.est_pages_ff)::float / ci.relpages AS bloat_ratio,
  bloat.is_na
FROM pg_catalog.pg_class ci
JOIN pg_catalog.pg_index i     ON i.indexrelid = ci.oid
JOIN pg_catalog.pg_class ct    ON ct.oid = i.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid = ct.relnamespace

-- Per-index system constants and fillfactor.
CROSS JOIN LATERAL (
    SELECT
        current_setting('block_size')::numeric AS bs,
        CASE -- MAXALIGN: 4 on 32bits, 8 on 64bits (and mingw32 ?)
            WHEN version() ~ 'mingw32'::text
              OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64'::text THEN 8
            ELSE 4
        END AS maxalign,
        24 AS pagehdr,     -- per page header, fixed size: 24 for 8.3 and after
        16 AS pageopqdata, -- per page btree opaque data
        COALESCE(
            substring(array_to_string(ci.reloptions, ' '::text) FROM 'fillfactor=([0-9]+)')::smallint::integer,
            90
        ) AS fillfactor
) c

-- Aggregate the per-column statistics for this index, expanding the index columns
-- through a LATERAL generate_series rather than a SELECT-list set-returning function.
CROSS JOIN LATERAL (
    SELECT
        max(CASE WHEN COALESCE(a1.atttypid, a2.atttypid) = 'pg_catalog.name'::regtype THEN 1 ELSE 0 END) > 0 AS is_na,
        /* per tuple header: add IndexAttributeBitMapData if some cols are null-able */
        CASE WHEN max(COALESCE(s_t.null_frac, s_x.null_frac, 0::real)) = 0::double precision
            THEN 2 -- IndexTupleData size
            ELSE 2 + (32 + 8 - 1) / 8 -- IndexTupleData size + IndexAttributeBitMapData size
        END AS index_tuple_hdr_bm,
        /* data len: we remove null values, saving space, using their fractional part from stats */
        sum((1::double precision - COALESCE(s_t.null_frac, s_x.null_frac, 0::real))
            * COALESCE(s_t.avg_width, s_x.avg_width, 1024)::double precision) AS nulldatawidth
    FROM generate_series(1, i.indnatts::integer) AS gs(attpos)
    LEFT JOIN pg_catalog.pg_attribute a1
           ON (string_to_array(textin(int2vectorout(i.indkey)), ' '::text)::integer[])[gs.attpos] <> 0
          AND a1.attrelid = i.indrelid
          AND a1.attnum   = (string_to_array(textin(int2vectorout(i.indkey)), ' '::text)::integer[])[gs.attpos]
    LEFT JOIN pg_catalog.pg_attribute a2
           ON (string_to_array(textin(int2vectorout(i.indkey)), ' '::text)::integer[])[gs.attpos] = 0
          AND a2.attrelid = ci.oid
          AND a2.attnum   = gs.attpos
    LEFT JOIN pg_catalog.pg_stats s_t
           ON s_t.schemaname = n.nspname
          AND s_t.tablename  = ct.relname
          AND s_t.attname    = a1.attname
    LEFT JOIN pg_catalog.pg_stats s_x
           ON s_x.schemaname = n.nspname
          AND s_x.tablename  = ci.relname
          AND s_x.attname    = a2.attname
) agg

-- Index tuple header width, aligned on MAXALIGN.
CROSS JOIN LATERAL (
    SELECT
        (
            (agg.index_tuple_hdr_bm + c.maxalign
             - CASE -- Add padding to the index tuple header to align on MAXALIGN
                 WHEN (agg.index_tuple_hdr_bm % c.maxalign) = 0 THEN c.maxalign
                 ELSE agg.index_tuple_hdr_bm % c.maxalign
               END)::double precision
          + agg.nulldatawidth
          + c.maxalign::double precision
          - CASE -- Add padding to the data to align on MAXALIGN
              WHEN agg.nulldatawidth = 0::double precision THEN 0
              WHEN (agg.nulldatawidth::integer % c.maxalign) = 0 THEN c.maxalign
              ELSE agg.nulldatawidth::integer % c.maxalign
            END::double precision
        )::numeric AS nulldatahdrwidth
) hdr

-- Estimated number of pages, with and without the fillfactor applied.
CROSS JOIN LATERAL (
    SELECT
        agg.is_na,
        COALESCE(
            1::double precision + ceil(
                ci.reltuples / floor(
                    (c.bs - c.pageopqdata::numeric - c.pagehdr::numeric)::double precision
                    / (4::numeric + hdr.nulldatahdrwidth)::double precision
                )
            ),
            0::double precision
        ) AS est_pages,
        COALESCE(
            1::double precision + ceil(
                ci.reltuples / floor(
                    ((c.bs - c.pageopqdata::numeric - c.pagehdr::numeric) * c.fillfactor::numeric)::double precision
                    / (100::double precision * (4::numeric + hdr.nulldatahdrwidth)::double precision)
                )
            ),
            0::double precision
        ) AS est_pages_ff
) bloat

WHERE ci.relkind = 'i'
  AND ci.relam = (SELECT oid FROM pg_am WHERE amname = 'btree'::name)
  AND ci.relpages > 0
ORDER BY n.nspname, ct.relname, ci.relname;
