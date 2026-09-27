-- ============================================================================
-- NextRead
-- 01_staging_and_cleaning.sql
--
-- Purpose:
-- Clean and standardize the Goodbooks-10k source tables before analytical use.
-- The staging layer preserves the source structure while removing known data
-- quality issues, enforcing keys, and creating reliable relationships.
--
-- Source schema: raw
-- Output schema: staging
-- ============================================================================


-- ============================================================================
-- 1. BOOKS
-- Grain: One row per book_id
--
-- Cleaning:
--   • Retain historically valid negative publication years.
--   • Remove publication years beyond the analytical period.
--   • Preserve source attributes used later for analysis and reporting.
-- ============================================================================

DROP TABLE IF EXISTS staging.stg_books CASCADE;

CREATE TABLE staging.stg_books AS
SELECT
    book_id,
    goodreads_book_id,
    best_book_id,
    work_id,
    books_count,
    isbn,
    isbn13,
    authors,

    CASE
        WHEN original_publication_year <= 2026
            THEN original_publication_year
        ELSE NULL
    END AS original_publication_year,

    original_title,
    title,
    language_code,
    average_rating,
    ratings_count,
    work_ratings_count,
    work_text_reviews_count,
    ratings_1,
    ratings_2,
    ratings_3,
    ratings_4,
    ratings_5,
    image_url,
    small_image_url

FROM raw.books;


ALTER TABLE staging.stg_books
    ADD CONSTRAINT stg_books_pkey
    PRIMARY KEY (book_id);


ALTER TABLE staging.stg_books
    ADD CONSTRAINT uq_stg_books_goodreads_book_id
    UNIQUE (goodreads_book_id);


-- ============================================================================
-- 2. RATINGS
-- Grain: One reader-book rating
--
-- DISTINCT protects the analytical layer from duplicate source observations.
-- ============================================================================

DROP TABLE IF EXISTS staging.stg_ratings CASCADE;

CREATE TABLE staging.stg_ratings AS
SELECT DISTINCT
    user_id,
    book_id,
    rating
FROM raw.ratings
WHERE user_id IS NOT NULL
  AND book_id IS NOT NULL
  AND rating BETWEEN 1 AND 5;


ALTER TABLE staging.stg_ratings
    ADD CONSTRAINT fk_stg_ratings_book
    FOREIGN KEY (book_id)
    REFERENCES staging.stg_books(book_id);


-- ============================================================================
-- 3. TAGS
-- Grain: One row per tag_id
-- ============================================================================

DROP TABLE IF EXISTS staging.stg_tags CASCADE;

CREATE TABLE staging.stg_tags AS
SELECT DISTINCT
    tag_id,
    tag_name
FROM raw.tags
WHERE tag_id IS NOT NULL
  AND tag_name IS NOT NULL;


ALTER TABLE staging.stg_tags
    ADD CONSTRAINT stg_tags_pkey
    PRIMARY KEY (tag_id);


-- ============================================================================
-- 4. BOOK TAGS
-- Grain: One goodreads_book_id + tag_id combination
--
-- Known source issues:
--   • Duplicate book/tag combinations
--   • Six records with negative tag counts
--
-- Duplicate combinations are consolidated and invalid negative counts removed.
-- ============================================================================

DROP TABLE IF EXISTS staging.stg_book_tags CASCADE;

CREATE TABLE staging.stg_book_tags AS
SELECT
    goodreads_book_id,
    tag_id,
    SUM(count) AS count
FROM raw.book_tags
WHERE count >= 0
GROUP BY
    goodreads_book_id,
    tag_id;


ALTER TABLE staging.stg_book_tags
    ADD CONSTRAINT stg_book_tags_pkey
    PRIMARY KEY (goodreads_book_id, tag_id);


ALTER TABLE staging.stg_book_tags
    ADD CONSTRAINT fk_stg_book_tags_book
    FOREIGN KEY (goodreads_book_id)
    REFERENCES staging.stg_books(goodreads_book_id);


ALTER TABLE staging.stg_book_tags
    ADD CONSTRAINT fk_stg_book_tags_tag
    FOREIGN KEY (tag_id)
    REFERENCES staging.stg_tags(tag_id);


ALTER TABLE staging.stg_book_tags
    ADD CONSTRAINT chk_stg_book_tags_count
    CHECK (count >= 0);


-- ============================================================================
-- 5. TO-READ
-- Grain: One user-book relationship
-- ============================================================================

DROP TABLE IF EXISTS staging.stg_to_read CASCADE;

CREATE TABLE staging.stg_to_read AS
SELECT DISTINCT
    user_id,
    book_id
FROM raw.to_read
WHERE user_id IS NOT NULL
  AND book_id IS NOT NULL;


ALTER TABLE staging.stg_to_read
    ADD CONSTRAINT fk_stg_to_read_book
    FOREIGN KEY (book_id)
    REFERENCES staging.stg_books(book_id);


-- ============================================================================
-- 6. DATA QUALITY CHECKS
-- These queries document the validation performed after staging.
-- ============================================================================


-- Row counts
SELECT 'books' AS table_name, COUNT(*) AS row_count
FROM staging.stg_books

UNION ALL

SELECT 'ratings', COUNT(*)
FROM staging.stg_ratings

UNION ALL

SELECT 'tags', COUNT(*)
FROM staging.stg_tags

UNION ALL

SELECT 'book_tags', COUNT(*)
FROM staging.stg_book_tags

UNION ALL

SELECT 'to_read', COUNT(*)
FROM staging.stg_to_read;


-- Confirm book IDs are unique
SELECT
    book_id,
    COUNT(*)
FROM staging.stg_books
GROUP BY book_id
HAVING COUNT(*) > 1;


-- Confirm book-tag combinations are unique
SELECT
    goodreads_book_id,
    tag_id,
    COUNT(*)
FROM staging.stg_book_tags
GROUP BY
    goodreads_book_id,
    tag_id
HAVING COUNT(*) > 1;


-- Confirm no negative tag counts remain
SELECT COUNT(*) AS negative_tag_counts
FROM staging.stg_book_tags
WHERE count < 0;


-- Validate source rating distribution
SELECT
    rating,
    COUNT(*) AS ratings
FROM staging.stg_ratings
GROUP BY rating
ORDER BY rating;


-- Validate that Goodreads aggregate rating counts reconcile
SELECT COUNT(*) AS rating_count_mismatches
FROM staging.stg_books
WHERE work_ratings_count <>
      COALESCE(ratings_1, 0)
    + COALESCE(ratings_2, 0)
    + COALESCE(ratings_3, 0)
    + COALESCE(ratings_4, 0)
    + COALESCE(ratings_5, 0);


-- Review publication-year range after cleaning
SELECT
    MIN(original_publication_year) AS earliest_publication_year,
    MAX(original_publication_year) AS latest_publication_year
FROM staging.stg_books;