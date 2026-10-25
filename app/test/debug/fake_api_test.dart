import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/api/library.dart' show topTracks;
import 'package:vehicoule/bridge/api/playback.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/bridge/player.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/debug/library.dart';

void main() {
  test('fake api records calls and streams player commands', () async {
    final api = FakeApi();
    RustLib.initMock(api: api);
    addTearDown(RustLib.dispose);

    final got = <PlayerCommand>[];
    final sub = playerCommands().listen(got.add);
    addTearDown(sub.cancel);
    api.commands.add(const PlayerCommand.clearNext());
    await Future<void>.delayed(Duration.zero);
    expect(got, [const PlayerCommand.clearNext()]);

    playerEvent(e: const PlayerEvent.ended(entry: 'e1'));
    final now = await nowPlaying().first;
    expect(now.track, sampleTracks.first);
    final queue = await queueStates().first;
    expect(queue.current, sampleTracks.first);
    expect(queue.upcoming.map((u) => u.track), sampleTracks.skip(1));

    // Anything else is recorded, then refused by name.
    expect(
      topTracks,
      throwsA(
        isA<UnimplementedError>().having(
          (e) => e.message,
          'message',
          'crateApiLibraryTopTracks',
        ),
      ),
    );
    expect(api.calls.map((c) => c.memberName), [
      #crateApiPlaybackPlayerCommands,
      #crateApiPlaybackPlayerEvent,
      #crateApiPlaybackNowPlaying,
      #crateApiPlaybackQueueStates,
      #crateApiLibraryTopTracks,
    ]);
    expect(
      api.calls[1].namedArguments[#e],
      const PlayerEvent.ended(entry: 'e1'),
    );
  });
}
