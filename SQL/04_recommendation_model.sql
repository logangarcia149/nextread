-- ============================================================================
-- NextRead
-- 04_recommendation_model.sql
--
-- Purpose:
-- Identify books that perform unusually well within each reader segment and
-- rank the strongest candidates for recommendation.
--
-- Output:
--   intermediate.int_segment_book_performance
--   intermediate.int_strong_segment_book_candidates
--   intermediate.int_segment_recommendation_scores
--   mart.segment_recommendations
-- ============================================================================


-- ============================================================================
-- 1. SEGMENT-BOOK PERFORMANCE
-- Grain: One reader segment + book
--
-- Reader-normalized ratings are used so naturally generous or selective
-- raters do not distort segment performance.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_segment_book_performance CASCADE;

CREATE TABLE intermediate.int_segment_book_performance AS

WITH segment_stats AS (
    SELECT
        rs.cluster_id,
        rs.segment_name,
        rrn.book_id,

        COUNT(*) AS segment_rating_count,
        AVG(rrn.rating)::numeric(6,3) AS segment_average_rating,

        AVG(
            CASE WHEN rrn.rating >= 4 THEN 1.0 ELSE 0.0 END
        )::numeric(8,6) AS segment_high_rating_share,

        AVG(rrn.rating_deviation)::numeric(8,6)
            AS segment_average_rating_deviation

    FROM intermediate.int_reader_ratings_normalized rrn

    JOIN mart.reader_segments rs
      ON rs.user_id = rrn.user_id

    GROUP BY
        rs.cluster_id,
        rs.segment_name,
        rrn.book_id
),

overall_stats AS (
    SELECT
        book_id,

        COUNT(*) AS overall_rating_count,
        AVG(rating)::numeric(6,3) AS overall_average_rating,

        AVG(
            CASE WHEN rating >= 4 THEN 1.0 ELSE 0.0 END
        )::numeric(8,6) AS overall_high_rating_share,

        AVG(rating_deviation)::numeric(8,6)
            AS overall_average_rating_deviation

    FROM intermediate.int_reader_ratings_normalized

    GROUP BY book_id
)

SELECT
    ss.book_id,
    b.title,

    ss.cluster_id,
    ss.segment_name,

    ss.segment_rating_count,
    ss.segment_average_rating,
    ss.segment_high_rating_share,
    ss.segment_average_rating_deviation,

    os.overall_rating_count,
    os.overall_average_rating,
    os.overall_high_rating_share,
    os.overall_average_rating_deviation,

    (
        ss.segment_average_rating
        - os.overall_average_rating
    )::numeric(8,6) AS rating_lift,

    (
        ss.segment_high_rating_share
        - os.overall_high_rating_share
    )::numeric(8,6) AS high_rating_share_lift,

    (
        ss.segment_average_rating_deviation
        - os.overall_average_rating_deviation
    )::numeric(8,6) AS normalized_affinity_lift

FROM segment_stats ss

JOIN overall_stats os
  ON os.book_id = ss.book_id

JOIN staging.stg_books b
  ON b.book_id = ss.book_id;


-- ============================================================================
-- 2. STRONG RECOMMENDATION CANDIDATES
--
-- Candidate logic:
--   • At least 75 ratings from readers in the segment
--   • Positive normalized segment performance
--   • Positive segment-specific affinity
--   • At or above the segment median for:
--       - high-rating share
--       - normalized rating deviation
--       - affinity lift
--
-- Segment-relative thresholds prevent one global cutoff from favoring groups
-- with naturally different rating behavior.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_strong_segment_book_candidates CASCADE;

CREATE TABLE intermediate.int_strong_segment_book_candidates AS

WITH eligible_candidates AS (
    SELECT *
    FROM intermediate.int_segment_book_performance
    WHERE segment_rating_count >= 50
      AND segment_average_rating_deviation > 0
      AND normalized_affinity_lift > 0
),

segment_thresholds AS (
    SELECT
        cluster_id,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY segment_high_rating_share)
            AS median_high_rating_share,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY segment_average_rating_deviation)
            AS median_rating_deviation,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY normalized_affinity_lift)
            AS median_affinity_lift

    FROM eligible_candidates
    GROUP BY cluster_id
)

SELECT
    c.*
FROM eligible_candidates c

JOIN segment_thresholds t
  ON t.cluster_id = c.cluster_id

WHERE c.segment_rating_count >= 75

  AND c.segment_high_rating_share
      >= t.median_high_rating_share

  AND c.segment_average_rating_deviation
      >= t.median_rating_deviation

  AND c.normalized_affinity_lift
      >= t.median_affinity_lift;


-- ============================================================================
-- 3. RECOMMENDATION SCORING
--
-- Recommendation strength combines:
--   50% absolute satisfaction within the reader segment
--   50% segment-specific affinity
--
-- Rating count is used as an evidence threshold, not as a popularity bonus.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_segment_recommendation_scores CASCADE;

CREATE TABLE intermediate.int_segment_recommendation_scores AS

WITH scored AS (
    SELECT
        c.*,

        PERCENT_RANK() OVER (
            PARTITION BY cluster_id
            ORDER BY segment_high_rating_share
        ) AS high_rating_percentile,

        PERCENT_RANK() OVER (
            PARTITION BY cluster_id
            ORDER BY normalized_affinity_lift
        ) AS affinity_percentile

    FROM intermediate.int_strong_segment_book_candidates c
)

SELECT
    *,

    (
        0.50 * high_rating_percentile
        +
        0.50 * affinity_percentile
    )::numeric(8,6) AS recommendation_score

FROM scored;


-- ============================================================================
-- 4. FINAL SEGMENT RECOMMENDATIONS
-- Grain: One reader segment + recommended book
--
-- Recommendations are ranked independently within each reader segment.
-- ============================================================================

DROP TABLE IF EXISTS mart.segment_recommendations CASCADE;

CREATE TABLE mart.segment_recommendations AS

SELECT
    cluster_id,
    segment_name,

    ROW_NUMBER() OVER (
        PARTITION BY cluster_id

        ORDER BY
            recommendation_score DESC,
            segment_high_rating_share DESC,
            normalized_affinity_lift DESC,
            segment_rating_count DESC,
            book_id
    ) AS recommendation_rank,

    book_id,
    title,

    recommendation_score,

    segment_rating_count,
    segment_average_rating,
    segment_high_rating_share,
    segment_average_rating_deviation,
    normalized_affinity_lift,

    high_rating_percentile,
    affinity_percentile

FROM intermediate.int_segment_recommendation_scores;


-- ============================================================================
-- 5. QA / MODEL REVIEW
-- ============================================================================


-- Recommendation candidates by reader segment
SELECT
    cluster_id,
    segment_name,
    COUNT(*) AS recommendation_candidates
FROM mart.segment_recommendations
GROUP BY
    cluster_id,
    segment_name
ORDER BY cluster_id;


-- Review the Top 10 recommendations for each segment
SELECT
    cluster_id,
    segment_name,
    recommendation_rank,
    title,
    recommendation_score,
    segment_high_rating_share,
    normalized_affinity_lift,
    segment_rating_count
FROM mart.segment_recommendations
WHERE recommendation_rank <= 10
ORDER BY
    cluster_id,
    recommendation_rank;


-- Confirm no duplicate book rankings within a segment
SELECT
    cluster_id,
    book_id,
    COUNT(*)
FROM mart.segment_recommendations
GROUP BY
    cluster_id,
    book_id
HAVING COUNT(*) > 1;


-- Final recommendation inventory
SELECT
    COUNT(*) AS total_recommendations,
    MIN(recommendation_rank) AS minimum_rank,
    MAX(recommendation_rank) AS maximum_rank
FROM mart.segment_recommendations;