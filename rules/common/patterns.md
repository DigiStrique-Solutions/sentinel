# Common Patterns

## Skeleton Projects

When implementing new functionality:
1. Search for battle-tested skeleton projects
2. Use parallel agents to evaluate options:
   - Security assessment
   - Extensibility analysis
   - Relevance scoring
   - Implementation planning
3. Clone best match as foundation
4. Iterate within proven structure

## Design Patterns

### Repository Pattern

Encapsulate data access behind a consistent interface:
- Define standard operations: `findAll`, `findById`, `create`, `update`, `delete`
- Concrete implementations handle storage details (database, API, file, etc.)
- Business logic depends on the abstract interface, not the storage mechanism
- Enables easy swapping of data sources and simplifies testing with mocks

### API Response Format

Use a consistent envelope for all API responses:
- Include a success/status indicator
- Include the data payload (nullable on error)
- Include an error message field (nullable on success)
- Include metadata for paginated responses (total, page, limit)

### Error Handling Pattern

Use structured error types instead of generic exceptions:
- Define domain-specific error classes/types
- Include error codes for programmatic handling
- Include human-readable messages for display
- Propagate context (what operation failed, with what input)

### Configuration Pattern

- Load configuration from environment variables
- Validate all required config at startup (fail fast)
- Use typed configuration objects, not raw strings
- Provide sensible defaults where appropriate
- Never mix configuration with business logic
