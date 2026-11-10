import 'dart:async';

import 'package:downloadx/downloadx.dart';
import 'package:test/test.dart';

import '../helpers/mock_io.dart';

void main() {
  test('restored chunks wait unstarted and split within the current limit',
      () async {
    const url = 'https://h/file.bin';
    final io = MockIo();
    final body = deterministicBytes(8192);
    io.fetcher
        .route(url, MockRoute(body: body, etag: '"v1"', streamChunkSize: 64));
    DownloadX manager(int limit) => DownloadX(DownloadXConfig(
          io: io,
          targetPath: '/downloads',
          cachePath: '/cache',
          targetChunkCount: limit,
          minChunkSize: 64,
          requestTimeout: 150,
          maxRetries: 0,
        ));

    final original = await manager(8).addUrl(
      url,
      const DownloadOptions(id: 'limited', targetChunkCount: 8),
    );
    original.emitter.onType<ChunkProgressEvent>((_) => original.pause());
    await original.start();
    expect(original.state, DownloadState.paused);
    final saved =
        await loadMeta(io, const MetaLocator(dir: '/cache', id: 'limited'));
    expect(saved!.chunks.length, 8);
    expect(
        saved.chunks.where((c) => c.status != ChunkStatus.completed).length, 8);

    var active = 0;
    var peak = 0;
    var overflow = 0;
    io.fetchHook = (url, init, proceed) async {
      if (init?.method == 'HEAD') return proceed();
      active++;
      if (active > peak) peak = active;
      if (active > 2) {
        active--;
        overflow++;
        throw StateError('host only has two request slots');
      }
      final response = await proceed();
      final start = int.parse(RegExp(r'bytes=(\d+)')
          .firstMatch(init!.headers!['Range']!)!
          .group(1)!);
      return _ActiveBody(response, start >= 7168 ? 40 : 20, () => active--);
    };
    final restoredManager = manager(2);
    await restoredManager.restoreFromCache();
    final restored = restoredManager.getDownload('limited')!;
    // A current transport policy overrides a persisted per-download target.
    restored.setTargetChunkCount(2);
    var splits = 0;
    restored.emitter.onType<ChunkSplitEvent>((_) => splits++);
    await restored.start().timeout(const Duration(seconds: 10));
    // A running range lasts well over the 150 ms idle timeout; every body
    // chunk arrives before it, while the other six chunks wait unstarted.
    expect(restored.state, DownloadState.completed);
    expect(overflow, 0);
    expect(peak, 2);
    expect(active, 0);
    expect(splits, greaterThan(0));
    expect(io.files['/downloads/file.bin'], body);
    expect(restored.getChunkSnapshots().every((c) => c.retries == 0), isTrue);
  });
}

class _ActiveBody implements FetchResponse {
  _ActiveBody(this.inner, this.delay, this.release);
  final FetchResponse inner;
  final int delay;
  final void Function() release;
  @override
  Stream<List<int>>? get body => _body(inner.body!);
  Stream<List<int>> _body(Stream<List<int>> stream) async* {
    try {
      await for (final bytes in stream) {
        await Future<void>.delayed(Duration(milliseconds: delay));
        yield bytes;
      }
    } finally {
      release();
    }
  }

  @override
  FetchHeaders get headers => inner.headers;
  @override
  int get status => inner.status;
  @override
  String get statusText => inner.statusText;
  @override
  bool get ok => inner.ok;
  @override
  String? get url => inner.url;
  @override
  Future<List<int>> bytes() => inner.bytes();
  @override
  Future<String> text() => inner.text();
}
