from pathlib import Path

import pandas as pd
from sklearn.preprocessing import StandardScaler


DATA_PATH = Path("data/ingest/reader_clustering_features.csv")


# --------------------------------------------------
# 1. Load data
# --------------------------------------------------

df = pd.read_csv(DATA_PATH)


# Preserve user_id separately.
# It identifies a reader but should NOT be used
# as a clustering feature.
user_ids = df["user_id"].copy()


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
# 3. Inspect missingness before imputation
# --------------------------------------------------

print("\n=== MISSING VALUES BEFORE IMPUTATION ===")
print(
    X.isna().sum()[X.isna().sum() > 0]
    .sort_values(ascending=False)
)


# --------------------------------------------------
# 4. Impute missing genre preferences
# --------------------------------------------------

genre_columns = [
    column
    for column in feature_columns
    if column.startswith("pref_")
]

X[genre_columns] = X[genre_columns].fillna(0)


# --------------------------------------------------
# 5. Confirm no missing values remain
# --------------------------------------------------

print("\n=== TOTAL MISSING VALUES AFTER IMPUTATION ===")
print(X.isna().sum().sum())


# --------------------------------------------------
# 6. Standardize features
# --------------------------------------------------

scaler = StandardScaler()

X_scaled = scaler.fit_transform(X)


# Convert scaled data back to a DataFrame so
# the column names remain visible.
X_scaled_df = pd.DataFrame(
    X_scaled,
    columns=feature_columns
)


# --------------------------------------------------
# 7. Validate scaling
# --------------------------------------------------

print("\n=== SCALED FEATURE MEANS ===")
print(X_scaled_df.mean().round(3))


print("\n=== SCALED FEATURE STANDARD DEVIATIONS ===")
print(X_scaled_df.std(ddof=0).round(3))


print("\n=== SCALED DATA SHAPE ===")
print(X_scaled_df.shape)


print("\n=== FIRST FIVE SCALED ROWS ===")
print(X_scaled_df.head())