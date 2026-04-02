# Async Generator Ordering

Events emitted from async generators can share the same millisecond timestamp. Sorting by timestamp does NOT guarantee order.

## What Goes Wrong

When multiple events are yielded in quick succession from an async generator, `time.time()` or `Date.now()` can return identical values. Any code that sorts events by timestamp to reconstruct order will intermittently produce wrong results.

## How to Avoid

- Use a monotonically increasing sequence number instead of timestamps for ordering
- If timestamps are needed for display, keep a separate `sequence_id` for ordering
- Never assume timestamps are unique — two events CAN share a millisecond

## Discovered

YYYY-MM-DD during investigation of out-of-order event delivery.
