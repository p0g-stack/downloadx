# Dart download identity, completeness and crash-progress hardening

Base: tag `dart-v0.3.0`. Local branch `fix-dart-download-integrity`; not pushed.

## Changes

1. Seed split IDs above the maximum restored numeric suffix, not just chunk count. Normal engine-produced layouts already retain completed chunks and restore safely: a regression against unmodified 0.3.0 passed split → pause/persist → restore → split for four different completion orders. The fix hardens sparse/custom layouts supplied through the public MetaFile API; it is not a claim that normal 0.3.0 IDs collide.
2. Add configurable periodic metadata persistence for long-running chunks (`DownloadXConfig.metaPersistInterval`, default 1000 milliseconds, zero disables). Serialize full metadata write+rename operations across timer/completion/pause/finalization, and allow at most one timer-originated persistence in flight. `GlobalConfig` implementers need to supply the new getter.
3. Treat early EOF of a finite chunk as retryable. Streaming and buffered responses both retry from already-written bytes; repeated empty bodies fail after the configured retry budget. Unknown-length streams and intentionally shortened split chunks retain their existing behavior.
4. Before writing a response, check Content-Range coordinates and total against the request/probe, Content-Length when present, and the pinned strong ETag (including refusal when missing). Request coordinates are captured before fetch so an in-flight split does not reject a valid original response. Cancel rejected response bodies. HLS segment resources must not inherit a playlist's validators.

## Host storage contract

Periodic persistence does not itself guarantee that downloaded bytes survived a page/worker crash. A custom DownloadxIo must commit/flush preceding positional writes before publishing the corresponding sidecar snapshot. FileSystemWritableFileStream stages writes until close; reopening with keepExistingData may copy the whole file, so adapters should checkpoint those transactions less frequently than cheap OPFS SyncAccessHandle.flush checkpoints. This belongs in the adapter, not the scheduler.

## Application workarounds while using published 0.3.0

flasher_web uses strict bounded HTTP reads below the engine (per-response ETag/Content-Range/length checks), public getChunkSnapshots/persistMeta on chunk/progress events, and durable storage checkpoints before sidecar publication. It requires a strong ETag for parallel/resumed downloads; without one it uses a fresh single-connection download. Final SHA-256 is a bounded disk read-back pass. Its ordered service-worker destination uses a bounded FIFO of shared-reader ranges rather than staging a multi-gigabyte OTA in quota-limited OPFS.

## Validation

`cd apps/downloadx_dart && dart analyze && dart test`: analyzer clean; all 159 tests passed. The earlier split/persist/restore/split regression against unmodified 0.3.0 also passed all four completion orders. No push or pull request publication has been performed.
