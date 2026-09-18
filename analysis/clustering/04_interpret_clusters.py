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
# 2. Select clustering features
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
# 3. Impute missing genre preferences
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
# 5. Candidate K values
# --------------------------------------------------

candidate_k_values = [3, 4, 5, 7]


for k in candidate_k_values:

    print(f"\n{'=' * 70}")
    print(f"K = {k}")
    print(f"{'=' * 70}")

    model = KMeans(
        n_clusters=k,
        random_state=42,
        n_init="auto"
    )

    labels = model.fit_predict(X_scaled)


    # ----------------------------------------------
    # Cluster assignments
    # ----------------------------------------------

    clustered = df[["user_id"]].copy()

    clustered["cluster"] = labels


    # ----------------------------------------------
    # Cluster sizes
    # ----------------------------------------------

    cluster_sizes = (
        clustered["cluster"]
        .value_counts()
        .sort_index()
        .rename("reader_count")
    )

    cluster_percent = (
        cluster_sizes
        / len(clustered)
        * 100
    ).round(2)

    size_summary = pd.DataFrame({
        "reader_count": cluster_sizes,
        "percent_of_readers": cluster_percent
    })

    print("\n--- CLUSTER SIZES ---")
    print(size_summary)


    # ----------------------------------------------
    # Convert standardized centers back to
    # original feature units
    # ----------------------------------------------

    centers_original = scaler.inverse_transform(
        model.cluster_centers_
    )

    centers_df = pd.DataFrame(
        centers_original,
        columns=feature_columns
    )

    centers_df.index.name = "cluster"


    # ----------------------------------------------
    # Behavioral features
    # ----------------------------------------------

    behavioral_columns = [
        "ratings_count",
        "average_rating",
        "rating_stddev",
        "high_rating_share",
        "preference_spread",
    ]

    print("\n--- BEHAVIORAL CENTERS ---")
    print(
        centers_df[behavioral_columns]
        .round(3)
    )


    # ----------------------------------------------
    # Genre preference centers
    # ----------------------------------------------

    print("\n--- GENRE PREFERENCE CENTERS ---")

    print(
        centers_df[genre_columns]
        .round(3)
        .T
    )


    # ----------------------------------------------
    # Save output
    # ----------------------------------------------

    size_summary.to_csv(
        OUTPUT_DIR / f"k{k}_cluster_sizes.csv"
    )

    centers_df.to_csv(
        OUTPUT_DIR / f"k{k}_cluster_centers.csv"
    )

    clustered.to_csv(
        OUTPUT_DIR / f"k{k}_reader_assignments.csv",
        index=False
    )


print("\nFinished cluster interpretation.")