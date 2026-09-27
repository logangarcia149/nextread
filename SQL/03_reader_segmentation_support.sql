-- ============================================================================
-- NextRead
-- 03_reader_segmentation_support.sql
--
-- Purpose:
-- Prepare the final reader-level feature table used for clustering.
--
-- Grain: One row per reader
-- Output: intermediate.int_reader_clustering_features
-- ============================================================================


-- ============================================================================
-- 1. BUILD CLUSTERING FEATURE TABLE
--
-- Five reader-behavior features are combined with 18 genre-preference
-- features. Missing genre preferences are set to zero.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_reader_clustering_features CASCADE;

CREATE TABLE intermediate.int_reader_clustering_features AS

SELECT
    rsf.user_id,

    -- Reader behavior
    rsf.rating_count,
    rsf.average_rating,
    rsf.rating_stddev,
    rsf.high_rating_share,
    rsf.preference_spread,

    -- Genre preference features
    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Adventure'),
        0
    ) AS adventure_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Children''s'),
        0
    ) AS childrens_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Classics'),
        0
    ) AS classics_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Contemporary'),
        0
    ) AS contemporary_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Dystopian'),
        0
    ) AS dystopian_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Fantasy'),
        0
    ) AS fantasy_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Graphic Novels'),
        0
    ) AS graphic_novels_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Historical Fiction'),
        0
    ) AS historical_fiction_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'History'),
        0
    ) AS history_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Horror'),
        0
    ) AS horror_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Humor'),
        0
    ) AS humor_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Mystery'),
        0
    ) AS mystery_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Nonfiction'),
        0
    ) AS nonfiction_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Paranormal'),
        0
    ) AS paranormal_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Romance'),
        0
    ) AS romance_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Science Fiction'),
        0
    ) AS science_fiction_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Thriller'),
        0
    ) AS thriller_preference,

    COALESCE(
        MAX(rp.preference_score)
        FILTER (WHERE rp.genre_name = 'Young Adult'),
        0
    ) AS young_adult_preference

FROM intermediate.int_reader_segment_features rsf

LEFT JOIN intermediate.int_reader_preferences rp
    ON rp.user_id = rsf.user_id

GROUP BY
    rsf.user_id,
    rsf.rating_count,
    rsf.average_rating,
    rsf.rating_stddev,
    rsf.high_rating_share,
    rsf.preference_spread;


-- ============================================================================
-- 2. QA CHECKS
-- ============================================================================


-- Expected: 53,424 readers
SELECT COUNT(*) AS reader_count
FROM intermediate.int_reader_clustering_features;


-- Confirm one row per reader
SELECT
    user_id,
    COUNT(*)
FROM intermediate.int_reader_clustering_features
GROUP BY user_id
HAVING COUNT(*) > 1;


-- Confirm no missing feature values
SELECT COUNT(*) AS rows_with_missing_features
FROM intermediate.int_reader_clustering_features
WHERE rating_count IS NULL
   OR average_rating IS NULL
   OR rating_stddev IS NULL
   OR high_rating_share IS NULL
   OR preference_spread IS NULL
   OR adventure_preference IS NULL
   OR childrens_preference IS NULL
   OR classics_preference IS NULL
   OR contemporary_preference IS NULL
   OR dystopian_preference IS NULL
   OR fantasy_preference IS NULL
   OR graphic_novels_preference IS NULL
   OR historical_fiction_preference IS NULL
   OR history_preference IS NULL
   OR horror_preference IS NULL
   OR humor_preference IS NULL
   OR mystery_preference IS NULL
   OR nonfiction_preference IS NULL
   OR paranormal_preference IS NULL
   OR romance_preference IS NULL
   OR science_fiction_preference IS NULL
   OR thriller_preference IS NULL
   OR young_adult_preference IS NULL;


-- Review feature ranges before Python standardization
SELECT
    MIN(rating_count) AS min_rating_count,
    MAX(rating_count) AS max_rating_count,
    MIN(average_rating) AS min_average_rating,
    MAX(average_rating) AS max_average_rating,
    MIN(preference_spread) AS min_preference_spread,
    MAX(preference_spread) AS max_preference_spread
FROM intermediate.int_reader_clustering_features;