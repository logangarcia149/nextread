from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score
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
# 3. Impute missing genre preference values
# --------------------------------------------------

genre_columns = [
    column
    for column in feature_columns
    if column.startswith("pref_")
]

X[genre_columns] = X[genre_columns].fillna(0)


# --------------------------------------------------
# 4. Standardize features
# --------------------------------------------------

scaler = StandardScaler()

X_scaled = scaler.fit_transform(X)


# --------------------------------------------------
# 5. Evaluate K = 2 through 10
# --------------------------------------------------

results = []

for k in range(2, 11):

    print(f"\nRunning K-Means with k={k}...")

    model = KMeans(
        n_clusters=k,
        random_state=42,
        n_init="auto"
    )

    cluster_labels = model.fit_predict(X_scaled)

    inertia = model.inertia_

    # Full silhouette calculation is expensive for
    # 53,424 readers, so use a reproducible sample.
    silhouette = silhouette_score(
        X_scaled,
        cluster_labels,
        sample_size=10000,
        random_state=42
    )

    cluster_sizes = pd.Series(cluster_labels).value_counts()

    smallest_cluster = cluster_sizes.min()
    largest_cluster = cluster_sizes.max()

    results.append({
        "k": k,
        "inertia": inertia,
        "silhouette_score": silhouette,
        "smallest_cluster": smallest_cluster,
        "largest_cluster": largest_cluster,
    })

    print(f"Inertia: {inertia:,.2f}")
    print(f"Silhouette: {silhouette:.4f}")
    print(f"Smallest cluster: {smallest_cluster:,}")
    print(f"Largest cluster: {largest_cluster:,}")


# --------------------------------------------------
# 6. Save evaluation results
# --------------------------------------------------

results_df = pd.DataFrame(results)

results_df.to_csv(
    OUTPUT_DIR / "kmeans_evaluation.csv",
    index=False
)


print("\n=== K-MEANS EVALUATION ===")
print(results_df)


# --------------------------------------------------
# 7. Plot inertia / elbow curve
# --------------------------------------------------

plt.figure(figsize=(8, 5))

plt.plot(
    results_df["k"],
    results_df["inertia"],
    marker="o"
)

plt.xlabel("Number of Clusters (K)")
plt.ylabel("Inertia")
plt.title("K-Means Elbow Curve")

plt.tight_layout()

plt.savefig(
    OUTPUT_DIR / "kmeans_elbow.png",
    dpi=150
)

plt.close()


# --------------------------------------------------
# 8. Plot silhouette scores
# --------------------------------------------------

plt.figure(figsize=(8, 5))

plt.plot(
    results_df["k"],
    results_df["silhouette_score"],
    marker="o"
)

plt.xlabel("Number of Clusters (K)")
plt.ylabel("Silhouette Score")
plt.title("K-Means Silhouette Scores")

plt.tight_layout()

plt.savefig(
    OUTPUT_DIR / "kmeans_silhouette.png",
    dpi=150
)

plt.close()


print("\nSaved results to:")
print(OUTPUT_DIR)