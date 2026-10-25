// Writes the frame timings of integration_test/perf_test.dart to
// build/perf_timings.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data != null) {
      await writeResponseData(data, testOutputFilename: 'perf_timings');
    }
  },
);
