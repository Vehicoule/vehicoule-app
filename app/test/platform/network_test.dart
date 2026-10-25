import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/platform/network.dart';

import 'player_test.dart' show settle;

class _Connectivity implements Connectivity {
  var now = [ConnectivityResult.none];
  final changes = StreamController<List<ConnectivityResult>>.broadcast(
    sync: true,
  );

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => now;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => changes.stream;
}

void main() {
  test('network exposes online and calls setOnline', () async {
    final api = FakeApi();
    RustLib.initMock(api: api);
    addTearDown(RustLib.dispose);

    final c = _Connectivity();
    final n = Network(c)..start();
    await settle();
    expect(n.online.value, isFalse);

    c.changes.add([ConnectivityResult.wifi]);
    await settle();
    expect(n.online.value, isTrue);
    // Same state, another interface: nothing new for the core.
    c.changes.add([ConnectivityResult.wifi, ConnectivityResult.vpn]);
    await settle();
    c.changes.add([ConnectivityResult.none]);
    await settle();
    expect(n.online.value, isFalse);

    expect(
      [
        for (final call in api.calls)
          if (call.memberName == #crateApiAppSetOnline)
            call.namedArguments[#online],
      ],
      [false, true, false],
    );
  });
}
