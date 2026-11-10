# Dart download identity, completeness and crash-progress hardening

Base: tag `dart-v0.3.0`. Branch `fix-dart-download-integrity` on <https://github.com/p0g-stack/downloadx>; no pull request.

## Changes

1. Seed split IDs above the maximum restored numeric suffix, not just chunk count. Normal engine-produced layouts already retain completed chunks and restore safely: a regression against unmodified 0.3.0 passed split → pause/persist → restore → split for four different completion orders. The fix hardens sparse/custom layouts supplied through the public MetaFile API; it is not a claim that normal 0.3.0 IDs collide.
2. Add configurable periodic metadata persistence for long-running chunks (`DownloadXConfig.metaPersistInterval`, default 1000 milliseconds, zero disables). Serialize full metadata write+rename operations across timer/completion/pause/finalization, and allow at most one timer-originated persistence in flight. `GlobalConfig` implementers need to supply the new getter.
3. Treat early EOF of a finite chunk as retryable. Streaming and buffered responses both retry from already-written bytes; repeated empty bodies fail after the configured retry budget. Unknown-length streams and intentionally shortened split chunks retain their existing behavior.
4. Before writing a response, check Content-Range coordinates and total against the request/probe, Content-Length when present, and the pinned strong ETag (including refusal when missing). Request coordinates are captured before fetch so an in-flight split does not reject a valid original response. Cancel rejected response bodies. HLS segment resources must not inherit a playlist's validators.
5. Apply the current runner limit to normal downloads too, including restored layouts with more unfinished chunks than the new target. Leave overflow chunks unstarted, so their request/idle timers do not run in a browser queue. Donated chunks use the same launch path. A regression restores eight unfinished chunks under a two-request host limit, streams each range longer than the idle timeout, forces further splitting, and completes with no retries or overflow.

## Host storage contract

Periodic persistence does not itself guarantee that downloaded bytes survived a page/worker crash. A custom DownloadxIo must commit/flush preceding positional writes before publishing the corresponding sidecar snapshot. FileSystemWritableFileStream stages writes until close; reopening with keepExistingData may copy the whole file, so adapters should checkpoint those transactions less frequently than cheap OPFS SyncAccessHandle.flush checkpoints. This belongs in the adapter, not the scheduler.

## Application responsibilities

The engine now owns periodic snapshots, chunk IDs, finite-body completeness and logical-response validation. A positional adapter still commits bytes before metadata publication. flasher_web also retains its catalog-size pin, strong ETag across link refreshes, and final SHA-256 read-back. Its logical engine requests span multiple physical 8 MiB HTTP requests, so the actual HTTP source must still validate each physical response's Content-Range, length and ETag; validating synthetic logical headers cannot replace that boundary. The ordered service-worker destination uses a bounded FIFO rather than staging a multi-gigabyte OTA in quota-limited OPFS.

## Validation

`cd apps/downloadx_dart && dart analyze && dart test`: analyzer clean; all 160 tests passed. The earlier split/persist/restore/split regression against unmodified 0.3.0 also passed all four completion orders.
