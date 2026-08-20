from pathlib import Path
import sys

import duckdb


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python src/run_sql.py <sql_file>")

    sql_path = Path(sys.argv[1])

    if not sql_path.exists():
        raise FileNotFoundError(f"SQL file not found: {sql_path}")

    sql_text = sql_path.read_text(encoding="utf-8")

    statements = [
        statement.strip()
        for statement in sql_text.split(";")
        if statement.strip()
    ]

    con = duckdb.connect()

    for i, statement in enumerate(statements, start=1):
        print(f"\n--- Statement {i} ---")

        result = con.sql(statement)

        if result is not None:
            result.show()


if __name__ == "__main__":
    main()