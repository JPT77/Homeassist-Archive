#!/usr/bin/env python3

from pathlib import Path
import shutil
import logging

import paramiko
import pandas as pd

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SSH_HOST = "homeassistant"
SSH_USER = "root"
SSH_KEY = Path.home() / ".ssh/id_ed25519"

PG_HOST = "localhost"
PG_USER = "homeassist"
PG_PW = "homeassist"

REMOTE_DIR = "/share/export"

INCOMING = Path("/opt/homeassist/incoming")
ARCHIVE = Path("/opt/homeassist/archive")

INCOMING.mkdir(parents=True, exist_ok=True)
ARCHIVE.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)


# -----------------------------------------------------------------------------

def download_missing_files():

    transport = paramiko.Transport((SSH_HOST, 22))
    transport.connect(
        username=SSH_USER,
        pkey=paramiko.Ed25519Key.from_private_key_file(str(SSH_KEY))
    )

    sftp = paramiko.SFTPClient.from_transport(transport)

    downloaded = []

    for entry in sftp.listdir_attr(REMOTE_DIR):

        if not entry.filename.startswith("statistics"):
            continue

        local = INCOMING / entry.filename

        if local.exists():
            continue

        remote = f"{REMOTE_DIR}/{entry.filename}"

        logging.info("Downloading %s", entry.filename)

        sftp.get(remote, str(local))

        downloaded.append(local)

    sftp.close()
    transport.close()

    return downloaded


# -----------------------------------------------------------------------------

def import_parquet(file: Path):

    logging.info("Importing %s", file.name)

    df = pd.read_parquet(file)

    #
    # TODO:
    #
    # insert into PostgreSQL
    #
    # ON CONFLICT DO NOTHING
    #

    logging.info("Imported %d rows", len(df))


# -----------------------------------------------------------------------------

def main():

    download_missing_files()

    for file in sorted(INCOMING.glob("statistics*.parquet")):

        try:

            import_parquet(file)

            shutil.move(
                file,
                ARCHIVE / file.name
            )

            logging.info("Archived %s", file.name)

        except Exception:

            logging.exception(
                "Import failed for %s",
                file.name
            )


# -----------------------------------------------------------------------------

if __name__ == "__main__":

    main()
