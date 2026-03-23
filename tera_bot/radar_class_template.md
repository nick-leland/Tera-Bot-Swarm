# RadarClient Class Design Overview

## Purpose

Own the ZMQ SUB socket and always expose the **freshest parsed snapshot** of radar state with minimal latency and no backlog.

---

## Responsibilities

* Connect to `tcp://host:port`, subscribe to a topic (often `""`).
* Receive JSON frames, parse them into dictionaries, and keep **only the latest**.
* Tolerate publisher restarts, malformed frames, and network gaps.
* Provide a simple, thread-safe read API for consumers.

---

## Core API (Synchronous Version)

| Method                                                                                                                                          | Description                                                 |                                       |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------- |
| `__init__(endpoint: str, topic: bytes = b"", *, conflate=True, rcv_hwm=1, rcv_timeout_ms=500, reconnect_ivl_ms=200, reconnect_ivl_max_ms=2000)` | Initialize client and socket configuration.                 |                                       |
| `start() -> RadarClient`                                                                                                                        | Spin up a background thread to begin receiving.             |                                       |
| `stop() -> None`                                                                                                                                | Stop the thread and close the socket.                       |                                       |
| `latest() -> dict                                                                                                                               | None`                                                       | Return the most recent good snapshot. |
| `updates(poll_interval: float = 0.01)`                                                                                                          | Optional generator that yields when a new snapshot arrives. |                                       |

---

## Internal State

* `_ctx`: `zmq.Context`
* `_sock`: `zmq.Socket`
* `_running`: `bool`
* `_thread`: `Thread | None`
* `_lock`: `RLock` (protects shared state)
* `_latest`: `dict | None` (last successfully parsed snapshot)
* `_last_seen_monotonic`: `float` (for health checks)
* `_recv_count`, `_drop_count`, `_malformed_count`: basic metrics

---

## Socket Options

| Option                               | Purpose                                    |
| ------------------------------------ | ------------------------------------------ |
| `SUBSCRIBE = topic`                  | Sets topic filter.                         |
| `CONFLATE = 1`                       | Ensures latest-only behavior (no backlog). |
| `RCVHWM = 1`                         | Limits buffering.                          |
| `RCVTIMEO = rcv_timeout_ms`          | Prevents indefinite blocking.              |
| `RECONNECT_IVL`, `RECONNECT_IVL_MAX` | Improves reconnect behavior.               |

---

## Receive Loop Behavior

1. Poll with timeout and check socket readiness.
2. On readiness:

   * Call `recv_string(NOBLOCK)`
   * Attempt `json.loads()`
   * If successful, store under lock and increment counters.
3. On timeout: continue quietly.
4. On parse errors: increment `_malformed_count`, retain last good snapshot.
5. Update `_last_seen_monotonic` after each valid receive.

---

## Thread Safety & Data Handling

* **Option A (Simple):** Return the same dict, documented as read-only.
* **Option B (Safer):** Return a shallow copy.
* **Option C (Immutable):** Use a frozen or mapping-proxy representation.

---

## Health & Diagnostics

* `healthy(max_silence_s: float = 2.0) -> bool` — check last message freshness.
* `stats() -> dict` — returns `{recv_count, drop_count, malformed_count, last_seen_ts}`.

---

## Error Handling & Shutdown

* Never raise during steady-state receive; log and continue.
* On `stop()`:

  * Set `_running = False`
  * Join thread
  * Close socket safely
* Guard against double `start()` or `stop()` calls.

---

## Observability

* Minimal debug logs for connection and first message.
* Rate-limited trace logs for malformed or dropped packets.

---

## Testing Hooks

* Allow injection of:

  * Custom endpoint (e.g., `inproc://test`)
  * Socket factory for feeding test data
* Deterministic `updates()` by tracking object identity or message counter.

---

## Async Variant

* Replace background thread with `zmq.asyncio` loop.
* Use `asyncio.Queue(maxsize=1)` to preserve “latest-only” semantics.
* Expose async versions of `start()` and `updates()`.

---

## Configurable Parameters

* Endpoint and topic
* Conflate flag (default: on)
* High-water mark (`hwm`)
* Timeout and reconnect intervals
* Optional JSON validation toggle (off by default)

---

## Failure Modes & Guardrails

* **Publisher down:** Return previous snapshot or `None`; mark unhealthy after delay.
* **Message bursts:** `CONFLATE` + `HWM=1` prevent memory growth.
* **Malformed spam:** Count errors and backoff logging to avoid console spam.

---

## Summary

`RadarClient` isolates all network complexity from your control logic.
It guarantees:

* Always the freshest frame
* Thread-safe, non-blocking reads
* Predictable shutdown and reconnect behavior
* Clean hooks for logging, testing, and async evolution
