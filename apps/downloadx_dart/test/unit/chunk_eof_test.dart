import 'dart:typed_data';

import 'package:downloadx/downloadx.dart';
import 'package:test/test.dart';

import '../helpers/mock_io.dart';

void main() {
  for (final streaming in [false, true]) {
    test('short ${streaming ? 'stream' : 'buffer'} retries from written bytes', () async {
      final io = _ShortIo(streaming: streaming);
      final chunk = _chunk(io);
      await chunk.run();
      expect(chunk.status, ChunkStatus.completed);
      expect(chunk.downloadedBytes, 128);
      expect(io.ranges, ['bytes=0-127', 'bytes=32-127']);
      expect(io.files['/file.part'], deterministicBytes(128));
    });
    test('empty ${streaming ? 'stream' : 'buffer'} exhausts retry budget', () async {
      final io = _ShortIo(streaming: streaming, empty: true);
      final chunk = _chunk(io);
      await chunk.run();
      expect(chunk.status, ChunkStatus.failed);
      expect(chunk.downloadedBytes, 0);
      expect(io.ranges.length, 3);
    });
  }
}

Chunk _chunk(_ShortIo io) => Chunk(ChunkParams(id: 'c0', downloadId: 'd',
  url: 'https://h/file.bin', targetFilePath: '/file.part', offset: 0, length: 128,
  initialDownloadedBytes: 0, acceptsRanges: true, global: _Config(io),
  emitter: EventEmitter(), medianSpeedRef: () => 0));

class _ShortIo extends MockIo {
  _ShortIo({required this.streaming, this.empty = false});
  final bool streaming;
  final bool empty;
  final ranges = <String>[];
  @override
  Future<FetchResponse> fetch(String url, [FetchInit? init]) async {
    final range = init!.headers!['Range']!;
    ranges.add(range);
    final start = int.parse(RegExp(r'bytes=(\d+)').firstMatch(range)!.group(1)!);
    final data = deterministicBytes(128);
    return MockResponse(status: 206, statusText: 'Partial Content',
      headers: MapFetchHeaders({'content-range':'bytes $start-127/128', 'content-length':'${128-start}'}),
      bodyBytes: empty ? Uint8List(0) : Uint8List.sublistView(data, start, ranges.length == 1 ? 32 : 128),
      streaming: streaming);
  }
}

class _Config implements DownloadConfig {
  _Config(this.io);
  @override final DownloadxIo io;
  @override int get maxRetries => 2;
  @override int get retryDelay => 1;
  @override num get retryBackoff => 1;
  @override int get speedSampleWindow => 500;
  @override int get requestTimeout => 5000;
  @override Map<String,String> get headers => const {};
}
