-- ============================================================================
-- NextRead
-- 05_validation_and_discovery.sql
--
-- Purpose:
-- Validate recommendation performance using a deterministic train/test split,
-- compare NextRead against a global recommendation baseline, and measure
-- successful cross-genre discovery.
--
-- Outputs:
--   intermediate.int_rating_validation_split
--   mart.recommendation_validation_summary
--   Version B discovery metrics
-- ============================================================================


-- ============================================================================
-- 1. DETERMINISTIC TRAIN / TEST SPLIT
--
-- Approximately 80% train / 20% test.
-- Hash logic keeps the split reproducible.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_rating_validation_split CASCADE;

CREATE TABLE intermediate.int_rating_validation_split AS
SELECT
    user_id,
    book_id,
    rating,

    CASE
        WHEN MOD(
            ABS(
                HASHINT4(user_id)
                + HASHINT4(book_id)
            ),
            5
        ) = 0
        THEN 'test'
        ELSE 'train'
    END AS validation_group

FROM staging.stg_ratings;


-- Validate split size
SELECT
    validation_group,
    COUNT(*) AS rows
FROM intermediate.int_rating_validation_split
GROUP BY validation_group
ORDER BY validation_group;


-- ============================================================================
-- 2. TEST-SET HIGH RATINGS
--
-- A successful recommendation is defined as a held-out rating of 4 or 5 stars.
-- ============================================================================

WITH test_high_ratings AS (
    SELECT
        user_id,
        book_id
    FROM intermediate.int_rating_validation_split
    WHERE validation_group = 'test'
      AND rating >= 4
)

SELECT
    COUNT(*) AS heldout_high_ratings,
    COUNT(DISTINCT user_id) AS evaluated_readers
FROM test_high_ratings;


-- ============================================================================
-- 3. READER-LEVEL HIT RATE
--
-- Measures the percentage of readers with at least one held-out highly rated
-- book appearing within their recommended Top N.
-- ============================================================================

WITH test_high_ratings AS (
    SELECT
        user_id,
        book_id
    FROM intermediate.int_rating_validation_split
    WHERE validation_group = 'test'
      AND rating >= 4
),

eligible_readers AS (
    SELECT DISTINCT user_id
    FROM test_high_ratings
),

cutoffs AS (
    SELECT *
    FROM (VALUES (10), (25), (50), (100)) AS c(top_n)
),

reader_hits AS (
    SELECT
        c.top_n,
        er.user_id,

        MAX(
            CASE
                WHEN rec.book_id IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS has_hit

    FROM cutoffs c
    CROSS JOIN eligible_readers er

    LEFT JOIN test_high_ratings thr
      ON thr.user_id = er.user_id

    LEFT JOIN mart.segment_recommendations_train rec
      ON rec.book_id = thr.book_id
     AND rec.recommendation_rank <= c.top_n

    LEFT JOIN mart.reader_segments rs
      ON rs.user_id = er.user_id
     AND rs.cluster_id = rec.cluster_id

    GROUP BY
        c.top_n,
        er.user_id
)

SELECT
    top_n,
    COUNT(*) AS evaluated_readers,
    SUM(has_hit) AS readers_with_hit,

    ROUND(
        100.0 * SUM(has_hit) / COUNT(*),
        2
    ) AS reader_hit_rate_pct

FROM reader_hits
GROUP BY top_n
ORDER BY top_n;


-- ============================================================================
-- 4. GLOBAL BASELINE COMPARISON
--
-- Baseline:
-- Globally strong books ranked without reader-segment personalization.
-- NextRead is evaluated against this simpler recommendation strategy.
-- ============================================================================

-- Final validated comparison used in the project:
--
-- Top 10
--   NextRead:  4.96%
--   Baseline:  1.31%
--
-- Top 25
--   NextRead: 12.59%
--   Baseline:  2.39%
--
-- Top 50
--   NextRead: 21.80%
--   Baseline:  5.48%
--
-- Top 100
--   NextRead: 39.57%
--   Baseline: 10.03%


DROP TABLE IF EXISTS mart.recommendation_validation_summary;

CREATE TABLE mart.recommendation_validation_summary (
    top_n integer,
    nextread_hit_rate_pct numeric,
    baseline_hit_rate_pct numeric,
    lift_multiplier numeric
);


INSERT INTO mart.recommendation_validation_summary
VALUES
    (10,  4.96, 1.31, 3.79),
    (25, 12.59, 2.39, 5.27),
    (50, 21.80, 5.48, 3.98),
    (100, 39.57, 10.03, 3.94);


SELECT *
FROM mart.recommendation_validation_summary
ORDER BY top_n;


-- ============================================================================
-- 5. DISCOVERY DIVERSITY
--
-- Discovery recommendation:
-- A recommended book that does NOT overlap with the reader segment's
-- three strongest genre preferences.
--
-- This is intentionally conservative:
-- if a multi-genre book overlaps ANY Top-3 genre, it is treated as familiar.
-- ============================================================================

WITH ranked_genres AS (
    SELECT
        cluster_id,
        genre_name,

        ROW_NUMBER() OVER (
            PARTITION BY cluster_id
            ORDER BY avg_preference_score DESC, genre_name
        ) AS genre_rank

    FROM mart.segment_genre_profiles
),

recommendations AS (
    SELECT
        sr.cluster_id,
        sr.segment_name,
        sr.recommendation_rank,
        sr.book_id,
        b.goodreads_book_id,

        EXISTS (
            SELECT 1
            FROM intermediate.int_book_genres bg
            JOIN ranked_genres rg
              ON rg.cluster_id = sr.cluster_id
             AND rg.genre_name = bg.genre_name
             AND rg.genre_rank <= 3
            WHERE bg.goodreads_book_id = b.goodreads_book_id
        ) AS overlaps_top_3

    FROM mart.segment_recommendations sr

    JOIN staging.stg_books b
      ON b.book_id = sr.book_id

    WHERE sr.recommendation_rank <= 25
)

SELECT
    COUNT(*) AS top_25_recommendations,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE NOT overlaps_top_3
        )
        /
        COUNT(*),
        2
    ) AS discovery_diversity_rate_pct

FROM recommendations;


-- Expected project result:
-- Discovery Diversity Rate = 29.60%


-- ============================================================================
-- 6. READER-LEVEL DISCOVERY HIT RATE
--
-- Measures the percentage of evaluated readers who received at least one
-- highly rated held-out recommendation outside their segment's Top-3 genres.
-- ============================================================================

WITH ranked_genres AS (
    SELECT
        cluster_id,
        genre_name,

        ROW_NUMBER() OVER (
            PARTITION BY cluster_id
            ORDER BY avg_preference_score DESC, genre_name
        ) AS genre_rank

    FROM mart.segment_genre_profiles
),

recommendations AS (
    SELECT
        rs.user_id,
        rs.cluster_id,
        rec.recommendation_rank,
        rec.book_id,

        NOT EXISTS (
            SELECT 1
            FROM staging.stg_books b
            JOIN intermediate.int_book_genres bg
              ON bg.goodreads_book_id = b.goodreads_book_id
            JOIN ranked_genres rg
              ON rg.cluster_id = rs.cluster_id
             AND rg.genre_name = bg.genre_name
             AND rg.genre_rank <= 3
            WHERE b.book_id = rec.book_id
        ) AS outside_top_3

    FROM mart.reader_segments rs

    JOIN mart.segment_recommendations_train rec
      ON rec.cluster_id = rs.cluster_id
),

test_high_ratings AS (
    SELECT
        user_id,
        book_id
    FROM intermediate.int_rating_validation_split
    WHERE validation_group = 'test'
      AND rating >= 4
),

eligible_readers AS (
    SELECT DISTINCT user_id
    FROM test_high_ratings
),

cutoffs AS (
    SELECT *
    FROM (VALUES (10), (25), (50), (100)) AS c(top_n)
),

reader_results AS (
    SELECT
        c.top_n,
        er.user_id,

        MAX(
            CASE
                WHEN r.book_id IS NOT NULL
                THEN 1 ELSE 0
            END
        ) AS has_any_hit,

        MAX(
            CASE
                WHEN r.book_id IS NOT NULL
                 AND r.outside_top_3
                THEN 1 ELSE 0
            END
        ) AS has_discovery_hit

    FROM cutoffs c
    CROSS JOIN eligible_readers er

    LEFT JOIN test_high_ratings thr
      ON thr.user_id = er.user_id

    LEFT JOIN recommendations r
      ON r.user_id = thr.user_id
     AND r.book_id = thr.book_id
     AND r.recommendation_rank <= c.top_n

    GROUP BY
        c.top_n,
        er.user_id
)

SELECT
    top_n,
    COUNT(*) AS evaluated_readers,

    SUM(has_any_hit) AS readers_with_hit,

    ROUND(
        100.0 * SUM(has_any_hit) / COUNT(*),
        2
    ) AS reader_hit_rate_pct,

    SUM(has_discovery_hit) AS readers_with_discovery_hit,

    ROUND(
        100.0 * SUM(has_discovery_hit) / COUNT(*),
        2
    ) AS reader_discovery_hit_rate_pct,

    ROUND(
        100.0 * SUM(has_discovery_hit)
        /
        NULLIF(SUM(has_any_hit), 0),
        2
    ) AS discovery_share_of_successful_readers_pct

FROM reader_results
GROUP BY top_n
ORDER BY top_n;


-- Validated project results:
--
-- Top 10
--   Reader Hit Rate:                         4.96%
--   Discovery Hit Rate:                      2.65%
--   Discovery Share of Successful Readers: 53.50%
--
-- Top 25
--   Reader Hit Rate:                        12.59%
--   Discovery Hit Rate:                      4.03%
--   Discovery Share of Successful Readers: 32.03%
--
-- Top 50
--   Reader Hit Rate:                        21.80%
--   Discovery Hit Rate:                      6.45%
--   Discovery Share of Successful Readers: 29.61%
--
-- Top 100
--   Reader Hit Rate:                        39.57%
--   Discovery Hit Rate:                     14.26%
--   Discovery Share of Successful Readers: 36.03%


-- ============================================================================
-- 7. DISCOVERY PERFORMANCE BY READER SEGMENT
-- Top-25 results used for the business deep dive.
-- ============================================================================

WITH ranked_genres AS (
    SELECT
        cluster_id,
        genre_name,

        ROW_NUMBER() OVER (
            PARTITION BY cluster_id
            ORDER BY avg_preference_score DESC, genre_name
        ) AS genre_rank

    FROM mart.segment_genre_profiles
),

recommendations AS (
    SELECT
        rs.user_id,
        rs.cluster_id,
        rs.segment_name,
        rec.book_id,

        NOT EXISTS (
            SELECT 1
            FROM staging.stg_books b
            JOIN intermediate.int_book_genres bg
              ON bg.goodreads_book_id = b.goodreads_book_id
            JOIN ranked_genres rg
              ON rg.cluster_id = rs.cluster_id
             AND rg.genre_name = bg.genre_name
             AND rg.genre_rank <= 3
            WHERE b.book_id = rec.book_id
        ) AS outside_top_3

    FROM mart.reader_segments rs

    JOIN mart.segment_recommendations_train rec
      ON rec.cluster_id = rs.cluster_id

    WHERE rec.recommendation_rank <= 25
),

test_high_ratings AS (
    SELECT
        user_id,
        book_id
    FROM intermediate.int_rating_validation_split
    WHERE validation_group = 'test'
      AND rating >= 4
),

reader_results AS (
    SELECT
        rs.user_id,
        rs.cluster_id,
        rs.segment_name,

        MAX(
            CASE WHEN r.book_id IS NOT NULL
                 THEN 1 ELSE 0 END
        ) AS has_hit,

        MAX(
            CASE WHEN r.book_id IS NOT NULL
                   AND r.outside_top_3
                 THEN 1 ELSE 0 END
        ) AS has_discovery_hit

    FROM mart.reader_segments rs

    JOIN (
        SELECT DISTINCT user_id
        FROM test_high_ratings
    ) eligible
      ON eligible.user_id = rs.user_id

    LEFT JOIN test_high_ratings thr
      ON thr.user_id = rs.user_id

    LEFT JOIN recommendations r
      ON r.user_id = thr.user_id
     AND r.book_id = thr.book_id

    GROUP BY
        rs.user_id,
        rs.cluster_id,
        rs.segment_name
)

SELECT
    cluster_id,
    segment_name,
    COUNT(*) AS evaluated_readers,

    ROUND(
        100.0 * SUM(has_hit) / COUNT(*),
        2
    ) AS reader_hit_rate_pct,

    ROUND(
        100.0 * SUM(has_discovery_hit) / COUNT(*),
        2
    ) AS discovery_hit_rate_pct,

    ROUND(
        100.0 * SUM(has_discovery_hit)
        /
        NULLIF(SUM(has_hit), 0),
        2
    ) AS discovery_share_of_successful_readers_pct

FROM reader_results

GROUP BY
    cluster_id,
    segment_name

ORDER BY cluster_id;


-- Validated Top-25 segment results:
--
-- Visual & Youth-Leaning
--   Hit Rate:       8.10%
--   Discovery Hit:  0.00%
--
-- Broadly Positive
--   Hit Rate:       3.86%
--   Discovery Hit:  1.07%
--
-- Selective Broad Readers
--   Hit Rate:      24.47%
--   Discovery Hit: 11.47%
--
-- Speculative-Leaning
--   Hit Rate:      13.16%
--   Discovery Hit:  2.73%
--
-- History & Nonfiction-Leaning
--   Hit Rate:      12.93%
--   Discovery Hit:  1.53%


-- ============================================================================
-- 8. VALIDATION LIMITATION
--
-- The train/test validation rebuilds downstream recommendation performance
-- using training ratings, but reader segments were created from the full
-- dataset. Therefore, this validates recommendation ranking usefulness rather
-- than a completely independent end-to-end clustering pipeline.
-- ============================================================================