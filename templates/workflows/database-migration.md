# Database Migration Workflow

Creating and applying database schema changes safely.

## 1. Create Migration

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

## 2. Review Migration

Common issues to check:
- [ ] Table/column names match the ORM model
- [ ] Nullable fields are correctly specified
- [ ] Default values are set where needed
- [ ] Foreign keys reference correct tables
- [ ] Indexes are added for frequently queried columns
- [ ] No data loss in the rollback path

## 3. Apply Migration

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

## 4. Test

- [ ] Existing tests still pass (ORM models must match DB schema)
- [ ] New entity/column is accessible via your ORM
- [ ] Rollback works (downgrade one step, then re-upgrade)
- [ ] Re-upgrade works cleanly

## Important Notes

- Always use your migration tool -- never modify the database schema manually
- Keep migrations small and focused -- one logical change per migration
- For column renames: use `ALTER COLUMN`, not drop + create (preserves data)
- For data migrations: use raw SQL in the migration file, not ORM queries
- Test rollback before deploying -- you may need it in production
- Consider the impact on running applications during migration (zero-downtime concerns)

#workflow #database #migration
