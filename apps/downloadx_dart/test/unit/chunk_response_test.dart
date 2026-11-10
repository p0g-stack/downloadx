import 'dart:typed_data';

import 'package:downloadx/downloadx.dart';
import 'package:test/test.dart';

import '../helpers/mock_io.dart';

void main() {
  final defaults = <String, String?>{
    'content-range': 'bytes 32-95/128', 'content-length': '64', 'etag': '"v1"',
  };
  final badHeaders = <Map<String, String?>>[
    {'content-range': null},
    {'content-range': 'bytes 0-63/128'},
    {'content-range': 'bytes 32-94/128'},
    {'content-range': 'bytes 32-95/256'},
    {'content-range': 'bytes 32-95/*'},
    {'content-length': '63'},
    {'content-length': 'invalid'},
    {'etag': '"v2"'},
    {'etag': null},
    {'etag': 'W/"v1"'},
  ];
  test('matching range, resource length and ETag are accepted', () async {
    final io = _ResponseIo(defaults);
    final chunk = _chunk(io);
    await chunk.run();
    expect(chunk.status, ChunkStatus.completed);
    expect(io.files['/file.part']!.sublist(32), deterministicBytes(128).sublist(32, 96));
  });
  for (final bad in badHeaders) {
    test('rejects response headers before writing: $bad', () async {
      final io = _ResponseIo({...defaults, ...bad});
      final chunk = _chunk(io);
      await chunk.run();
      expect(chunk.status, ChunkStatus.failed);
      expect(chunk.downloadedBytes, 0);
      expect(io.files.containsKey('/file.part'), isFalse);
    });
  }
}

Chunk _chunk(_ResponseIo io) => Chunk(ChunkParams(id: 'c0', downloadId: 'd',
  url: 'https://h/file.bin', targetFilePath: '/file.part', offset: 32, length: 64,
  totalSize: 128, etag: '"v1"', initialDownloadedBytes: 0,
  acceptsRanges: true, global: _Config(io), emitter: EventEmitter(), medianSpeedRef: () => 0));

class _ResponseIo extends MockIo {
  _ResponseIo(this.responseHeaders);
  final Map<String, String?> responseHeaders;
  @override
  Future<FetchResponse> fetch(String url, [FetchInit? init]) async => MockResponse(
    status: 206, statusText: 'Partial Content',
    headers: MapFetchHeaders({for (final e in responseHeaders.entries) if (e.value != null) e.key: e.value!}),
    bodyBytes: Uint8List.sublistView(deterministicBytes(128), 32, 96));
}

class _Config implements DownloadConfig {
  _Config(this.io);
  @override final DownloadxIo io;
  @override int get maxRetries => 0;
  @override int get retryDelay => 1;
  @override num get retryBackoff => 1;
  @override int get speedSampleWindow => 500;
  @override int get requestTimeout => 5000;
  @override Map<String,String> get headers => const {};
}
