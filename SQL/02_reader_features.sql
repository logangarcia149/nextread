-- ============================================================================
-- NextRead
-- 02_reader_features.sql
--
-- Purpose:
-- Build reader-level behavioral and preference features used for segmentation.
--
-- Source schema: staging
-- Output schema: intermediate
-- ============================================================================


-- ============================================================================
-- 1. READER RATING BEHAVIOR
-- Grain: One row per user_id
--
-- Captures how each reader tends to rate books overall.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_reader_rating_behavior CASCADE;

CREATE TABLE intermediate.int_reader_rating_behavior AS
SELECT
    user_id,
    COUNT(*) AS rating_count,
    AVG(rating)::numeric(6,3) AS average_rating,
    STDDEV_SAMP(rating)::numeric(6,3) AS rating_stddev,
    AVG(CASE WHEN rating >= 4 THEN 1.0 ELSE 0.0 END)::numeric(6,4)
        AS high_rating_share
FROM staging.stg_ratings
GROUP BY user_id;


-- ============================================================================
-- 2. NORMALIZED READER RATINGS
-- Grain: One row per user-book rating
--
-- Normalization adjusts for differences in rating generosity.
-- A positive deviation means the reader rated the book above their own average.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_reader_ratings_normalized CASCADE;

CREATE TABLE intermediate.int_reader_ratings_normalized AS
SELECT
    r.user_id,
    r.book_id,
    r.rating,
    rb.average_rating AS reader_average_rating,
    (r.rating - rb.average_rating)::numeric(6,3) AS rating_deviation
FROM staging.stg_ratings r
JOIN intermediate.int_reader_rating_behavior rb
  ON rb.user_id = r.user_id;


-- ============================================================================
-- 3. BOOK GENRES
-- Grain: One goodreads_book_id + genre_name
--
-- Maps books to analytical genres using the cleaned tag relationships.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_book_genres CASCADE;

CREATE TABLE intermediate.int_book_genres AS
SELECT
    bt.goodreads_book_id,
    t.tag_name AS genre_name,
    bt.count AS genre_tag_count,

    SUM(bt.count) OVER (
        PARTITION BY bt.goodreads_book_id
    ) AS total_genre_tag_count,

    (
        bt.count::numeric
        /
        NULLIF(
            SUM(bt.count) OVER (
                PARTITION BY bt.goodreads_book_id
            ),
            0
        )
    )::numeric(8,6) AS genre_share

FROM staging.stg_book_tags bt
JOIN staging.stg_tags t
  ON t.tag_id = bt.tag_id

WHERE t.tag_name IN (
    'adventure',
    'childrens',
    'classics',
    'contemporary',
    'dystopian',
    'fantasy',
    'graphic-novels',
    'historical-fiction',
    'history',
    'horror',
    'humor',
    'mystery',
    'nonfiction',
    'paranormal',
    'romance',
    'science-fiction',
    'thriller',
    'young-adult'
);


-- ============================================================================
-- 4. READER GENRE PREFERENCES
-- Grain: One user_id + genre_name
--
-- Preference score is based on how readers rate books within each genre
-- relative to their own normal rating behavior.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_reader_preferences CASCADE;

CREATE TABLE intermediate.int_reader_preferences AS
SELECT
    rrn.user_id,
    bg.genre_name,

    COUNT(*) AS genre_rating_count,

    AVG(rrn.rating)::numeric(6,3) AS genre_average_rating,

    AVG(rrn.rating_deviation)::numeric(6,3) AS preference_score

FROM intermediate.int_reader_ratings_normalized rrn

JOIN staging.stg_books b
  ON b.book_id = rrn.book_id

JOIN intermediate.int_book_genres bg
  ON bg.goodreads_book_id = b.goodreads_book_id

GROUP BY
    rrn.user_id,
    bg.genre_name;


-- ============================================================================
-- 5. READER SEGMENT FEATURES
-- Grain: One row per user_id
--
-- Combines behavior metrics with broader preference characteristics.
-- ============================================================================

DROP TABLE IF EXISTS intermediate.int_reader_segment_features CASCADE;

CREATE TABLE intermediate.int_reader_segment_features AS
SELECT
    rb.user_id,
    rb.rating_count,
    rb.average_rating,
    rb.rating_stddev,
    rb.high_rating_share,

    (
        MAX(rp.preference_score)
        -
        MIN(rp.preference_score)
    )::numeric(6,3) AS preference_spread

FROM intermediate.int_reader_rating_behavior rb

LEFT JOIN intermediate.int_reader_preferences rp
  ON rp.user_id = rb.user_id

GROUP BY
    rb.user_id,
    rb.rating_count,
    rb.average_rating,
    rb.rating_stddev,
    rb.high_rating_share;


-- ============================================================================
-- 6. QA CHECKS
-- ============================================================================


-- Number of readers
SELECT COUNT(*) AS readers
FROM intermediate.int_reader_segment_features;


-- Confirm one row per reader
SELECT
    user_id,
    COUNT(*)
FROM intermediate.int_reader_segment_features
GROUP BY user_id
HAVING COUNT(*) > 1;


-- Review behavior ranges
SELECT
    MIN(rating_count) AS min_ratings,
    AVG(rating_count)::numeric(10,2) AS avg_ratings,
    MAX(rating_count) AS max_ratings,

    MIN(average_rating) AS min_avg_rating,
    AVG(average_rating)::numeric(6,3) AS overall_avg_reader_rating,
    MAX(average_rating) AS max_avg_rating

FROM intermediate.int_reader_segment_features;


-- Review strongest average genre preferences
SELECT
    genre_name,
    AVG(preference_score)::numeric(6,3) AS avg_preference_score,
    COUNT(DISTINCT user_id) AS readers
FROM intermediate.int_reader_preferences
GROUP BY genre_name
ORDER BY avg_preference_score DESC;