import 'dart:async';

import 'package:downloadx/downloadx.dart';
import 'package:test/test.dart';

import '../helpers/mock_io.dart';

void main() {
  for (final sparse in [false, true]) {
  for (var fast = 0; fast < 4; fast++) {
    test('split/restore/split keeps IDs unique (fast=$fast, sparse=$sparse)', () async {
      const url = 'https://h/file.bin';
      final io = MockIo();
      final body = deterministicBytes(16384);
      io.fetcher.route(url, MockRoute(body: body, etag: '"v1"', streamChunkSize: 64));
      io.fetchHook = (url, init, proceed) async {
        final response = await proceed();
        final range = init?.headers?['Range'];
        final start = range == null ? null : int.parse(RegExp(r'bytes=(\d+)').firstMatch(range)!.group(1)!);
        if (start == null) return response;
        return _Delayed(response, (start ~/ 4096) == fast ? 0 : 2);
      };
      DownloadX manager() => DownloadX(DownloadXConfig(
        io: io, targetPath: '/downloads', cachePath: '/cache',
        targetChunkCount: 4, minChunkSize: 64, maxRetries: 0,
      ));
      final firstManager = manager();
      final first = await firstManager.addUrl(url, const DownloadOptions(id: 'stable'));
      var firstSplits = 0;
      var pauseScheduled = false;
      void unique(Download download) {
        final ids = download.getChunkSnapshots().map((c) => c.id).toList();
        expect(ids.toSet().length, ids.length);
      }
      first.emitter.onType<ChunkSplitEvent>((event) {
        firstSplits++;
        unique(first);
        if (!pauseScheduled) {
          pauseScheduled = true;
          scheduleMicrotask(first.pause);
        }
      });
      await first.start().timeout(const Duration(seconds: 10));
      expect(first.state, DownloadState.paused);
      expect(firstSplits, greaterThan(0));
      final saved = await loadMeta(io, const MetaLocator(dir: '/cache', id: 'stable'));
      expect(saved, isNotNull);
      expect(saved!.chunks.where((c) => c.status == ChunkStatus.completed), isNotEmpty,
          reason: 'completed chunks remain in the persisted layout');
      expect(saved.chunks.length, first.getChunkSnapshots().length);
      if (sparse) {
        final count = saved.chunks.length;
        saved.chunks = [
          for (var i = 0; i < count; i++)
            ChunkSnapshot.fromJson({
              ...saved.chunks[i].toJson(),
              'id': 'stable-c${i + count}',
            }),
        ];
        await persistMeta(io, const MetaLocator(dir: '/cache', id: 'stable'), saved);
      }
      final restoredManager = manager();
      await restoredManager.restoreFromCache();
      final restored = restoredManager.getDownload('stable')!;
      var laterSplits = 0;
      restored.emitter.onType<ChunkSplitEvent>((event) {
        laterSplits++;
        unique(restored);
      });
      await restored.start().timeout(const Duration(seconds: 10));
      expect(restored.state, DownloadState.completed);
      expect(laterSplits, greaterThan(0));
      unique(restored);
      expect(io.files['/downloads/file.bin'], body);
    });
  }
  }
}

class _Delayed implements FetchResponse {
  _Delayed(this.inner, this.delay);
  final FetchResponse inner;
  final int delay;
  @override
  Stream<List<int>>? get body => inner.body?.asyncMap((bytes) async {
    if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
    return bytes;
  });
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
