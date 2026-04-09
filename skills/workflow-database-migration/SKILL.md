---
name: sentinel-workflow-database-migration
description: Safe database schema migration workflow — generate, review, apply, test. Use whenever the user says "add a migration", "schema change", "new column", "alter table", "create table", "rename column", "drop column", "alembic", "prisma migrate", "knex migrate", "makemigrations", or otherwise signals a schema change — even if they don't explicitly say "workflow". Enforces that migrations are generated via the tool (never hand-edited), rollback paths are verified, and schema changes are tested end-to-end before deploy. Four steps — create, review, apply, test.
workflow: true
workflow-steps: 4
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
paths: "migrations/** **/migrations/** **/*.sql db/**"
---

# Database Migration Workflow

Creating and applying database schema changes safely.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start database-migration)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## 1. Create Migration

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Create Migration"
```

Generate a migration using your migration tool:

```bash
# Alembic (Python/SQLAlchemy)
alembic revision --autogenerate -m "description_of_change"

# Prisma (TypeScript)
npx prisma migrate dev --name description_of_change

# Knex (TypeScript)
npx knex migrate:make description_of_change

# Django
python manage.py makemigrations --name description_of_change
```

- [ ] Review the generated migration file
- [ ] Verify the `upgrade` / `up` function matches your intended changes
- [ ] Verify the `downgrade` / `down` function correctly reverses the changes

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-create.md` with the migration file path and a summary of the generated upgrade/downgrade functions.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-create.md"
```

## 2. Review Migration

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Review Migration"
```

Common issues to check:
- [ ] Table/column names match the ORM model
- [ ] Nullable fields are correctly specified
- [ ] Default values are set where needed
- [ ] Foreign keys reference correct tables
- [ ] Indexes are added for frequently queried columns
- [ ] No data loss in the rollback path

**Write an artifact**: `artifacts/step-2-review.md` listing each check and any findings or corrections made.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-review.md"
```

## 3. Apply Migration

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Apply Migration"
```

```bash
# Alembic
alembic upgrade head

# Prisma
npx prisma migrate deploy

# Knex
npx knex migrate:latest

# Django
python manage.py migrate
```

- [ ] Migration applies without errors
- [ ] Verify the schema change in the database

**Write an artifact**: `artifacts/step-3-apply.md` with the migration tool output and a snapshot of the new schema state.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-apply.md"
```

## 4. Test

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Test"
```

- [ ] Existing tests still pass (ORM models must match DB schema)
- [ ] New entity/column is accessible via your ORM
- [ ] Rollback works (downgrade one step, then re-upgrade)
- [ ] Re-upgrade works cleanly

**Write an artifact**: `artifacts/step-4-test.md` with test output, rollback/re-upgrade results, and ORM sanity-check output.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-test.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## Important Notes

- Always use your migration tool -- never modify the database schema manually
- Keep migrations small and focused -- one logical change per migration
- For column renames: use `ALTER COLUMN`, not drop + create (preserves data)
- For data migrations: use raw SQL in the migration file, not ORM queries
- Test rollback before deploying -- you may need it in production
- Consider the impact on running applications during migration (zero-downtime concerns)

#workflow #database #migration
