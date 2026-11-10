import 'dart:async';
import 'dart:convert';

import 'package:downloadx/downloadx.dart';
import 'package:test/test.dart';

import '../helpers/mock_io.dart';

void main() {
  for (final interval in [0, 10]) {
    test('periodic metadata interval $interval checkpoints a running chunk', () async {
      const url = 'https://h/file.bin';
      final io = _ObservedIo();
      final gate = Completer<void>();
      final firstWrite = Completer<void>();
      io.fetcher.route(url, MockRoute(body: deterministicBytes(4096), etag: '"v1"', streamChunkSize: 64));
      io.fetchHook = (url, init, proceed) async {
        final response = await proceed();
        return init?.method == 'HEAD' ? response : _HoldingResponse(response, gate.future);
      };
      final manager = DownloadX(DownloadXConfig(io: io,
        targetPath: '/downloads', cachePath: '/cache', targetChunkCount: 1,
        metaPersistInterval: interval));
      final download = await manager.addUrl(url, const DownloadOptions(id: 'stable'));
      download.emitter.onType<ChunkProgressEvent>((event) {
        if (!firstWrite.isCompleted) firstWrite.complete();
      });
      final running = download.start();
      try {
        await firstWrite.future.timeout(const Duration(seconds: 2));
        if (interval > 0) {
          await io.persistedProgress.future.timeout(const Duration(seconds: 2));
          final meta = await loadMeta(io, const MetaLocator(dir: '/cache', id: 'stable'));
          expect(meta!.chunks.single.downloadedBytes, 64);
          expect(meta.state, DownloadState.paused);
          expect(download.state, DownloadState.downloading);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(io.persistedProgress.isCompleted, isFalse);
        }
      } finally {
        download.pause();
        gate.complete();
        await running;
      }
      expect(download.state, DownloadState.paused);
      final meta = await loadMeta(io, const MetaLocator(dir: '/cache', id: 'stable'));
      expect(meta!.chunks.single.downloadedBytes, 64);
    });
  }
}

class _ObservedIo extends MockIo {
  final persistedProgress = Completer<void>();
  @override
  Future<void> rename(String from, String to) async {
    await super.rename(from, to);
    if (!to.endsWith(metaExt)) return;
    final meta = jsonDecode(utf8.decode(files[to]!)) as Map;
    final chunks = meta['chunks'] as List;
    if (!persistedProgress.isCompleted && chunks.any((c) => (c['downloadedBytes'] as num) > 0)) {
      persistedProgress.complete();
    }
  }
}

class _HoldingResponse implements FetchResponse {
  _HoldingResponse(this.inner, this.release);
  final FetchResponse inner;
  final Future<void> release;
  @override
  Stream<List<int>> get body async* {
    await for (final bytes in inner.body!) {
      yield bytes;
      await release;
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
