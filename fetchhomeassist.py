#!/usr/bin/env python3

from pathlib import Path
from datetime import datetime, timezone
import shutil
import logging
import os
import paramiko
import pandas as pd
from sqlalchemy import create_engine, text

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SSH_HOST = "homeassistant"
SSH_USER = "root"
SSH_KEY = Path.home() / ".ssh/id_ed25519"
REMOTE_DIR = "/share/export"

BASE_DIR = Path("/opt/homeassist")
INCOMING_DIR = BASE_DIR / "incoming"
ARCHIVE_DIR = BASE_DIR / "archive"

INCOMING_DIR.mkdir(parents=True, exist_ok=True)
ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)

PG_USER = os.environ.get("PG_USER", "homeassist")
PG_HOST = os.environ.get("PG_HOST", "localhost")
PG_PW = os.environ["PG_PW"]

DB_URL = f"postgresql+psycopg2://{PG_USER}:{PG_PW}@{PG_HOST}/homeassist"

# -----------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)


engine = create_engine(
    DB_URL,
    pool_pre_ping=True,
    echo=False
)


# -----------------------------------------------------------------------------
# Download from Home Assistant
# -----------------------------------------------------------------------------

def download_files():

    logging.info("Connecting to Home Assistant")
    transport = paramiko.Transport((SSH_HOST, 22))
    transport.connect(
        username=SSH_USER,
        pkey=paramiko.Ed25519Key.from_private_key_file(str(SSH_KEY))
    )

    sftp = paramiko.SFTPClient.from_transport(transport)
    downloaded = []

    for file in sftp.listdir(REMOTE_DIR):

        if not file.startswith("statistics"):
            logging.info("%s skipped, not statistics",file)
            continue

        if not file.endswith(".parquet"):
            logging.info("%s skipped, not PARQUET",file)
            continue

        local = INCOMING_DIR / file
        if local.exists():
            logging.info("%s already downloaded",file)
            continue

        logging.info("Downloading %s", file)

        sftp.get(f"{REMOTE_DIR}/{file}", str(local))
        downloaded.append(local)

    sftp.close()
    transport.close()

    return downloaded


# -----------------------------------------------------------------------------
# Import
# -----------------------------------------------------------------------------

def already_imported(filename):
    sql = "SELECT 1 FROM import_history WHERE filename = :filename"
    with engine.connect() as conn:
        return conn.execute(
            text(sql),
            {"filename": filename}
        ).first() is not None

def get_or_create_meta(conn, row):
    statistic_id = row["statistic_id"]

    result = conn.execute(
        text("""
            SELECT id
            FROM statistics_meta
            WHERE statistic_id = :statistic_id
        """),
        {"statistic_id": statistic_id}
    ).first()

    if result:
        return result.id

    result = conn.execute(
        text("""
            INSERT INTO statistics_meta
            (
                statistic_id,
                source,
                unit_of_measurement,
                has_mean,
                has_sum,
                name
            )
            VALUES
            (
                :statistic_id,
                :source,
                :unit_of_measurement,
                :has_mean,
                :has_sum,
                :name
            )
            RETURNING id
        """),
        {
            "statistic_id": statistic_id,
            "source": row.get("source"),
            "unit_of_measurement": row.get("unit_of_measurement"),
            "has_mean": row.get("has_mean"),
            "has_sum": row.get("has_sum"),
            "name": row.get("name"),
        }
    ).first()

    return result.id

def import_parquet(file: Path):
    logging.info("Importing %s", file.name)

    if already_imported(file.name):
        logging.info("%s already imported",file.name)
        return False

    df = pd.read_parquet(file)

    if "statistic_id" not in df.columns:
        raise ValueError(
            f"{file.name} enthält keine Spalte 'statistic_id'"
        )

    # -------------------------------------------------------------------------
    # Convert timestamps
    # -------------------------------------------------------------------------

    if "start_ts" in df.columns:

        df["start_at"] = pd.to_datetime(
            df["start_ts"],
            unit="s",
            utc=True
        )


    if "created_ts" in df.columns:

        df["created_at"] = pd.to_datetime(
            df["created_ts"],
            unit="s",
            utc=True
        )


    if "last_reset_ts" in df.columns:

        df["last_reset_at"] = pd.to_datetime(
            df["last_reset_ts"],
            unit="s",
            utc=True
        )


    # remove HA internal fields

    drop_columns = [
        "id",
        "created",
        "start",
        "last_reset",
        "start_ts",
        "created_ts",
        "last_reset_ts"
    ]

    df.drop(
        columns=[
            c for c in drop_columns
            if c in df.columns
        ],
        inplace=True
    )

    rows = len(df)

    try:
        with engine.begin() as conn:

            meta_ids = {}

            for statistic_id, group in df.groupby("statistic_id"):
                meta_ids[statistic_id] = get_or_create_meta(
                    conn,
                    group.iloc[0]
                )

                df["metadata_id"] = df["statistic_id"].map(meta_ids)

            df["metadata_id"] = (
                df["statistic_id"].map(meta_ids)
            )

            # Kontrolle: keine fehlenden Zuordnungen
            if df["metadata_id"].isna().any():
                missing = (
                    df.loc[
                        df["metadata_id"].isna(),
                        "statistic_id"
                    ]
                    .unique()
                    .tolist()
                )

                raise ValueError(
                    f"Keine Meta-ID für statistic_id: {missing}"
                )


            drop_columns = [
                "id",
                "created",
                "start",
                "last_reset",

                "created_ts",
                "last_reset_ts",

                # Diese Felder gehören zu statistics_meta
                "source",
                "unit_of_measurement",
                "has_mean",
                "has_sum",
                "name",
            ]

            df.drop(
                columns=[
                    c for c in drop_columns
                    if c in df.columns
                ],
                inplace=True
            )

            df.to_sql(
                "statistics_short_term",
                conn,
                if_exists="append",
                index=False,
                method="multi",
                chunksize=5000
            )

            conn.execute(
                text("""
                INSERT INTO import_history
                (
                    filename,
                    rows_imported
                )
                VALUES
                (
                    :filename,
                    :rows
                )
                """),
                {
                    "filename": file.name,
                    "rows": rows
                }
            )

        logging.info("Imported %s rows from %s", rows, file.name)
        return True

    except Exception:
        logging.exception("Import failed: %s", file.name)
        return False

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main():

    logging.info(
        "Starting Home Assistant archive import"
    )

    download_files()

    for file in sorted(INCOMING_DIR.glob("statistics*.parquet")):
        try:
            if import_parquet(file):
                shutil.move(
                    file,
                    ARCHIVE_DIR / file.name
                )
                logging.info("Archived %s", file.name)
        except Exception:
            logging.exception("Import failed for %s", file.name)

    logging.info("Finished")

if __name__ == "__main__":
    main()
