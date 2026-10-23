Please ignore this folder, which is just glue to build Rust with Flutter.

`cargokit/build_tool/lib/src/cargo.dart` is patched (`CrateInfo.libName` reads `[lib] name`): `flutter_rust_bridge_codegen integrate` overwrites it.
