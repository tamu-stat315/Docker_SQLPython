"""Verify Python packages, database contents, and student privileges."""

from __future__ import annotations

import importlib
import json
import os
import platform
import subprocess
import sys

from sqlalchemy import text

from stat315_db import engine


EXPECTED_COUNTS = {
    "closest_dealerships": 44_533,
    "countries": 0,
    "customer_sales": 50_000,
    "customer_survey": 32,
    "customers": 50_000,
    "dealerships": 20,
    "emails": 418_158,
    "products": 12,
    "public_transportation_by_zip": 15_412,
    "sales": 37_711,
    "salespeople": 300,
    "top_cities_data": 20,
    "customer_search": 50_000,
    "customer_survey_search": 32,
}

REQUIRED_IMPORTS = (
    "dask",
    "dask_ml",
    "duckdb",
    "graphviz",
    "ipykernel",
    "jupyterlab",
    "matplotlib",
    "nbconvert",
    "notebook",
    "numpy",
    "pandas",
    "psycopg",
    "pyarrow",
    "pytest",
    "scipy",
    "seaborn",
    "sklearn",
    "sqlalchemy",
    "statsmodels",
)


def verify_scientific_stack() -> None:
    """Exercise compiled wheels and common course-library integrations."""

    import dask.array as da
    import duckdb
    import matplotlib
    import numpy as np
    import pandas as pd
    import pyarrow as pa
    import statsmodels.api as sm
    from dask_ml.preprocessing import StandardScaler
    from sklearn.linear_model import LinearRegression

    matplotlib.use("Agg")
    from matplotlib import pyplot as plt

    values = np.array([[1.0, 2.0], [3.0, 5.0], [5.0, 8.0]])
    frame = pd.DataFrame(values, columns=["x", "y"])
    if frame["x"].sum() != 9.0:
        raise SystemExit("NumPy/pandas smoke test failed")

    dask_values = da.from_array(values, chunks=(2, 2))
    scaled = StandardScaler().fit_transform(dask_values).compute()
    np.testing.assert_allclose(scaled.mean(axis=0), 0.0, atol=1e-12)

    sklearn_model = LinearRegression().fit(values[:, :1], values[:, 1])
    np.testing.assert_allclose(sklearn_model.predict([[7.0]]), [11.0])

    statsmodels_result = sm.OLS(values[:, 1], sm.add_constant(values[:, 0])).fit()
    np.testing.assert_allclose(statsmodels_result.predict([1.0, 7.0]), 11.0)

    duckdb_total = duckdb.sql("SELECT sum(i) FROM range(6) AS t(i)").fetchone()[0]
    if duckdb_total != 15:
        raise SystemExit("DuckDB smoke test failed")

    arrow_table = pa.Table.from_pandas(frame)
    if arrow_table.num_rows != 3:
        raise SystemExit("PyArrow smoke test failed")

    figure, axis = plt.subplots()
    axis.plot(frame["x"], frame["y"])
    figure.savefig("/tmp/stat315-matplotlib-smoke.png")
    plt.close(figure)

    subprocess.run(
        ["dot", "-V"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> None:
    if sys.version_info[:2] != (3, 14):
        raise SystemExit(f"Expected Python 3.14, found {sys.version.split()[0]}")

    versions = {}
    for module_name in REQUIRED_IMPORTS:
        module = importlib.import_module(module_name)
        versions[module_name] = getattr(module, "__version__", "installed")

    verify_scientific_stack()

    expected_dataset = os.environ.get(
        "STAT315_DATASET_VERSION", "2026-fall-pg18-seed1"
    )

    with engine.begin() as connection:
        current_user = connection.execute(text("SELECT current_user")).scalar_one()
        if current_user != "stat315_student":
            raise SystemExit(f"Expected stat315_student, connected as {current_user}")

        server_version = connection.execute(
            text("SELECT current_setting('server_version_num')::integer")
        ).scalar_one()
        if not 180_000 <= server_version < 190_000:
            raise SystemExit(f"Expected PostgreSQL 18, found {server_version}")

        dataset_version = connection.execute(
            text(
                "SELECT dataset_version "
                "FROM course_meta.environment_release"
            )
        ).scalar_one()
        if dataset_version != expected_dataset:
            raise SystemExit(
                f"Expected dataset {expected_dataset}, found {dataset_version}"
            )

        for relation, expected_count in EXPECTED_COUNTS.items():
            actual_count = connection.execute(
                text(f'SELECT count(*) FROM public."{relation}"')
            ).scalar_one()
            if actual_count != expected_count:
                raise SystemExit(
                    f"{relation}: expected {expected_count}, found {actual_count}"
                )

        extensions = set(
            connection.execute(
                text(
                    "SELECT extname FROM pg_extension "
                    "WHERE extname IN ('cube', 'earthdistance')"
                )
            ).scalars()
        )
        if extensions != {"cube", "earthdistance"}:
            raise SystemExit(f"Missing database extensions: {extensions}")

        can_create_public = connection.execute(
            text(
                "SELECT has_schema_privilege("
                "current_user, 'public', 'CREATE')"
            )
        ).scalar_one()
        if can_create_public:
            raise SystemExit("Student role unexpectedly has CREATE on public")

        connection.execute(
            text(
                "CREATE TABLE IF NOT EXISTS "
                "student_work._environment_check (value integer)"
            )
        )
        connection.execute(text("DROP TABLE student_work._environment_check"))

    print(
        json.dumps(
            {
                "database": "passed",
                "dataset": expected_dataset,
                "machine": platform.machine(),
                "packages": versions,
                "python": sys.version.split()[0],
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
