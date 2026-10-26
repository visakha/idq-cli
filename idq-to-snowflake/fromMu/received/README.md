# TRS Compare API (v5.4.0)

Copy Oracle IDQ data to Snowflake, run the Snowflake ETL, and compare
IDQ targets against Snowflake targets by domain, dimension and spine.

**Read `USER_GUIDE.md` first** — it covers the one-time DDL step, the
daily operator flow, SSO authentication, the four missing Oracle
objects, and how to read a compare verdict.

## How this code is written (v3)

Spring MVC Rest + Spring Data JDBC, translated pythonically — not
Java in Python:

- **Repositories** (`app/repositories/`): `OracleRepository`,
  `SnowflakeRepository`, `RunRepository` — explicit, typed methods
  for the operations the job needs. No derived queries, no generic
  CRUD, no ORM, no session. One repository serves all 49 tables,
  parameterised by an explicit `Table` object.
- **Named SQL constants** (`app/repositories/queries.py`): fixed
  statements (`TRUNCATE`, `USE SCHEMA`, `CALL`, health `SELECT 1`)
  as module-level constants imported by name — not a properties
  file looked up by string key. Per-table queries stay as Core
  statements in the repositories, because they are dynamic.
- **Injected dependencies** (`app/api/dependencies.py`): routes
  declare repositories with `Annotated[Repo, Depends(get_repo)]`;
  services take repositories as arguments. Repositories are built
  from engine factories and connect only on first use, so a dry run
  or plain `/health` never touches a database.
- **Services are orchestration only** (`app/services/`): business
  rules, no SQL, no connections — testable with fake repositories.
- **Pydantic only** for models; **explicit table definitions** in
  `app/domain/tables.py`, generated once from the Oracle DDL
  (`scripts/generate_tables.py`) and checked in — never reflected
  from a live database.

Quick start:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill it in
uvicorn app.main:app --reload
pytest tests/ -q
```

Endpoints: `POST /runs/copy`, `POST /runs/etl`, `POST /runs/compare`,
`GET /runs`, `GET /runs/{run_id}`, `GET /config/tables`, `GET /health`.
Docs at `http://localhost:8000/docs`.
