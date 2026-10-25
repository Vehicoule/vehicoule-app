/// `vehicoule://` links (add-source, later now-playing), from Android's intent filter and
/// macOS's `CFBundleURLTypes`. Routes subscribe (Task 7, Task 10).
library;

import 'package:app_links/app_links.dart';

/// Each link once: app_links keeps the launch link for the first listener and shares one
/// platform subscription between listeners.
Stream<Uri> links() =>
    AppLinks().uriLinkStream.where((u) => u.scheme == 'vehicoule');
