from pathlib import Path

import pandas as pd


DATA_PATH = Path("data/ingest/reader_clustering_features.csv")


# Load the SQL-engineered reader features.
df = pd.read_csv(DATA_PATH)


print("\n=== DATASET SHAPE ===")
print(df.shape)


print("\n=== FIRST FIVE ROWS ===")
print(df.head())


print("\n=== DATA TYPES ===")
print(df.dtypes)


print("\n=== MISSING VALUES ===")
missing = pd.DataFrame({
    "missing_count": df.isna().sum(),
    "missing_percent": (df.isna().mean() * 100).round(2)
})

print(
    missing[missing["missing_count"] > 0]
    .sort_values("missing_count", ascending=False)
)


print("\n=== NUMERIC SUMMARY ===")
print(df.describe().T)