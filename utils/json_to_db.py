"""
Convert JSON notes file into SQLite database
@date 2024.Sep.5
"""

import json
import argparse
import sqlite3
from pandas import DataFrame


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-j', '--json', help="Source JSON file path")
    parser.add_argument('-o', '--out', help="Output SQLite DB file path")
    return parser.parse_args()


def read_json(json_fname:str):
    records = list()
    json_d = json.loads(open(json_fname).read())
    record_id = 0
    for section, notes in json_d.items():
        for note in notes:
            records.append({
              "recordId": record_id,
              "section": section,
              "noteId": None,
              "note": note,
            })
            record_id += 1
    return records


def open_or_create_db(db_fname):
    con = sqlite3.connect(db_fname)
    cur = con.cursor()
    create_sql = """
        CREATE TABLE IF NOT EXISTS notes (
          recordId INT PRIMARY KEY NOT NULL,
          section TEXT,
          noteId INT,
          note TEXT
        );"""
    r = cur.execute(create_sql)
    con.commit()
    return con


def to_sqlite(records:list, db_con:sqlite3.Connection):
    df = DataFrame.from_records(records)
    df.to_sql('notes', db_con, if_exists='append', index=False)


if __name__ == "__main__":
    args = parse_args()
    db = open_or_create_db(args.out)
    to_sqlite(read_json(args.json), db)
