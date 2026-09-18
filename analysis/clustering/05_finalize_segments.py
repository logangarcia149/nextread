from pathlib import Path

import pandas as pd
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler


DATA_PATH = Path("data/ingest/reader_clustering_features.csv")
OUTPUT_DIR = Path("analysis/clustering/output")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


# --------------------------------------------------
# 1. Load data
# --------------------------------------------------

df = pd.read_csv(DATA_PATH)


# --------------------------------------------------
# 2. Define clustering features
# --------------------------------------------------

feature_columns = [
    "ratings_count",
    "average_rating",
    "rating_stddev",
    "high_rating_share",
    "preference_spread",

    "pref_fantasy",
    "pref_science_fiction",
    "pref_young_adult",
    "pref_romance",
    "pref_mystery",
    "pref_thriller",
    "pref_horror",
    "pref_historical_fiction",
    "pref_nonfiction",
    "pref_history",
    "pref_childrens",
    "pref_graphic_novels",
    "pref_contemporary",
    "pref_classics",
    "pref_adventure",
    "pref_humor",
    "pref_paranormal",
    "pref_dystopian",
]


X = df[feature_columns].copy()


# --------------------------------------------------
# 3. Impute missing genre-preference values
# --------------------------------------------------

genre_columns = [
    column
    for column in feature_columns
    if column.startswith("pref_")
]

X[genre_columns] = X[genre_columns].fillna(0)


# --------------------------------------------------
# 4. Standardize
# --------------------------------------------------

scaler = StandardScaler()

X_scaled = scaler.fit_transform(X)


# --------------------------------------------------
# 5. Fit selected K=5 model
# --------------------------------------------------

model = KMeans(
    n_clusters=5,
    random_state=42,
    n_init="auto"
)

cluster_labels = model.fit_predict(X_scaled)


# --------------------------------------------------
# 6. Assign business-readable segment names
# --------------------------------------------------

segment_names = {
    0: "Visual & Youth-Leaning",
    1: "Broadly Positive",
    2: "Selective Broad Readers",
    3: "Speculative-Leaning",
    4: "History & Nonfiction-Leaning",
}


# --------------------------------------------------
# 7. Create reader assignment table
# --------------------------------------------------

assignments = pd.DataFrame({
    "user_id": df["user_id"],
    "cluster_id": cluster_labels
})

assignments["segment_name"] = (
    assignments["cluster_id"]
    .map(segment_names)
)


# --------------------------------------------------
# 8. Validate assignments
# --------------------------------------------------

print("\n=== SEGMENT COUNTS ===")

segment_summary = (
    assignments
    .groupby(
        ["cluster_id", "segment_name"],
        as_index=False
    )
    .agg(
        reader_count=("user_id", "count")
    )
)

segment_summary["percent_of_readers"] = (
    segment_summary["reader_count"]
    / len(assignments)
    * 100
).round(2)

print(segment_summary)


print("\n=== VALIDATION ===")

print(
    "Total readers:",
    len(assignments)
)

print(
    "Unique readers:",
    assignments["user_id"].nunique()
)

print(
    "Missing segment names:",
    assignments["segment_name"].isna().sum()
)


# --------------------------------------------------
# 9. Save assignments
# --------------------------------------------------

assignments.to_csv(
    OUTPUT_DIR / "reader_segments_k5.csv",
    index=False
)

segment_summary.to_csv(
    OUTPUT_DIR / "reader_segment_summary_k5.csv",
    index=False
)


print("\nFiles saved:")
print(OUTPUT_DIR / "reader_segments_k5.csv")
print(OUTPUT_DIR / "reader_segment_summary_k5.csv")