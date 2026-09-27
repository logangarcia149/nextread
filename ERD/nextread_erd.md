# NextRead Entity Relationship Diagram

```mermaid
erDiagram

    STG_BOOKS {
        int book_id PK
        int goodreads_book_id UK
        text title
        text authors
        numeric average_rating
    }

    STG_RATINGS {
        int user_id
        int book_id FK
        int rating
    }

    STG_TAGS {
        int tag_id PK
        text tag_name
    }

    STG_BOOK_TAGS {
        int goodreads_book_id FK
        int tag_id FK
        bigint count
    }

    INT_BOOK_GENRES {
        int goodreads_book_id FK
        text genre_name
        numeric genre_share
    }

    INT_READER_FEATURES {
        int user_id
        numeric average_rating
        numeric rating_stddev
        numeric high_rating_share
        numeric preference_spread
    }

    READER_SEGMENTS {
        int user_id PK
        int cluster_id
        text segment_name
    }

    SEGMENT_PROFILES {
        int cluster_id
        text display_name
        text display_description
    }

    SEGMENT_BOOK_PERFORMANCE {
        int cluster_id
        int book_id FK
        numeric high_rating_share
        numeric normalized_affinity_lift
    }

    SEGMENT_RECOMMENDATIONS {
        int cluster_id
        int book_id FK
        bigint recommendation_rank
        numeric recommendation_score
    }

    DASHBOARD_RECOMMENDATIONS {
        int cluster_id
        int book_id
        text reader_type
        text title
        text authors
        text recommendation_type
    }

    STG_BOOKS ||--o{ STG_RATINGS : receives
    STG_BOOKS ||--o{ STG_BOOK_TAGS : tagged
    STG_TAGS ||--o{ STG_BOOK_TAGS : defines
    STG_BOOK_TAGS ||--o{ INT_BOOK_GENRES : produces

    STG_RATINGS ||--o{ INT_READER_FEATURES : summarizes
    INT_READER_FEATURES ||--|| READER_SEGMENTS : classified_as

    READER_SEGMENTS ||--o{ SEGMENT_BOOK_PERFORMANCE : evaluates
    STG_BOOKS ||--o{ SEGMENT_BOOK_PERFORMANCE : measured_for

    SEGMENT_BOOK_PERFORMANCE ||--o{ SEGMENT_RECOMMENDATIONS : ranked_into
    SEGMENT_PROFILES ||--o{ SEGMENT_RECOMMENDATIONS : describes

    SEGMENT_RECOMMENDATIONS ||--o{ DASHBOARD_RECOMMENDATIONS : publishes
    STG_BOOKS ||--o{ DASHBOARD_RECOMMENDATIONS : enriches