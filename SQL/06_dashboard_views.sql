-- ============================================================================
-- NextRead
-- 06_dashboard_views.sql
--
-- Purpose:
-- Create the final Tableau-facing views used by the public NextRead dashboard.
--
-- Outputs:
--   mart.dashboard_vb_reader_profiles
--   mart.dashboard_vb_recommendations
-- ============================================================================


-- ============================================================================
-- 1. READER PROFILES
-- Grain: One row per reader type
--
-- Public-facing fields only:
--   • Reader type name
--   • Reader type description
--   • Top 3 genres
-- ============================================================================

CREATE OR REPLACE VIEW mart.dashboard_vb_reader_profiles AS

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

top_genres AS (
    SELECT
        cluster_id,

        STRING_AGG(
            genre_name,
            ', '
            ORDER BY genre_rank
        ) AS top_genres

    FROM ranked_genres

    WHERE genre_rank <= 3

    GROUP BY cluster_id
)

SELECT
    sp.cluster_id,
    sp.display_name AS reader_type,
    sp.display_description AS reader_type_description,
    tg.top_genres

FROM mart.segment_profiles sp

LEFT JOIN top_genres tg
  ON tg.cluster_id = sp.cluster_id

ORDER BY sp.cluster_id;


-- ============================================================================
-- 2. RECOMMENDATIONS
-- Grain: One reader type + recommended book
--
-- The view contains the fields needed by Tableau while keeping the dashboard
-- itself nontechnical and public-facing.
-- ============================================================================

DROP VIEW IF EXISTS mart.dashboard_vb_recommendations;

CREATE VIEW mart.dashboard_vb_recommendations AS

WITH ranked_genres AS (
    SELECT
        cluster_id,
        genre_name,

        ROW_NUMBER() OVER (
            PARTITION BY cluster_id
            ORDER BY avg_preference_score DESC, genre_name
        ) AS genre_rank

    FROM mart.segment_genre_profiles
)

SELECT
    sr.cluster_id,

    sp.display_name AS reader_type,
    sp.display_description AS reader_type_description,

    sr.recommendation_rank,
    sr.book_id,
    sr.title,
    b.authors,

    sr.recommendation_score,
    sr.segment_high_rating_share,
    sr.normalized_affinity_lift,
    sr.segment_rating_count,

    CASE
        WHEN EXISTS (
            SELECT 1

            FROM intermediate.int_book_genres bg

            JOIN ranked_genres rg
              ON rg.cluster_id = sr.cluster_id
             AND rg.genre_name = bg.genre_name
             AND rg.genre_rank <= 3

            WHERE bg.goodreads_book_id = b.goodreads_book_id
        )

        THEN 'Familiar'
        ELSE 'Discovery'

    END AS recommendation_type

FROM mart.segment_recommendations sr

JOIN mart.segment_profiles sp
  ON sp.cluster_id = sr.cluster_id

JOIN staging.stg_books b
  ON b.book_id = sr.book_id;


-- ============================================================================
-- 3. QA CHECKS
-- ============================================================================


-- Confirm five public reader types
SELECT
    cluster_id,
    reader_type,
    top_genres
FROM mart.dashboard_vb_reader_profiles
ORDER BY cluster_id;


-- Confirm recommendation inventory by reader type
SELECT
    reader_type,
    COUNT(*) AS recommendations,
    MIN(recommendation_rank) AS first_rank,
    MAX(recommendation_rank) AS final_rank
FROM mart.dashboard_vb_recommendations
GROUP BY reader_type
ORDER BY reader_type;


-- Review Top 5 recommendations for each reader type
SELECT
    reader_type,
    recommendation_rank,
    title,
    authors,
    recommendation_type
FROM mart.dashboard_vb_recommendations
WHERE recommendation_rank <= 5
ORDER BY
    cluster_id,
    recommendation_rank;


-- Confirm every recommendation has a public reader type
SELECT COUNT(*) AS missing_reader_types
FROM mart.dashboard_vb_recommendations
WHERE reader_type IS NULL;


-- Confirm every recommendation has a title
SELECT COUNT(*) AS missing_titles
FROM mart.dashboard_vb_recommendations
WHERE title IS NULL;