# JPush Disable

A Theos/Substrate tweak for the RootHide bootstrap targeting iOS 15.6. It
prevents the embedded Jiguang/Aurora Mobile JCore and JPush SDK
from initializing, collecting data, or opening its reporting transports.

The filter currently injects only into `com.farlightgames.farlight`. Change
`JPushDisable.plist` if the target application's bundle identifier differs.

## Build

Use the RootHide fork of Theos, then run:

```sh
make clean package
```

The Makefile selects `THEOS_PACKAGE_SCHEME=roothide`, an iOS 15.6 deployment
target, and both arm64 and arm64e slices.

## Behaviour

At process startup the tweak enumerates Objective-C classes owned by JPush,
JCore, and JCommon. It uses `MSHookMessageEx` to replace telemetry action
methods (setup, registration, collection, tracking, reporting, upload, socket
connection, and related actions) with type-compatible no-op implementations.
Unrelated application networking is not hooked.

Blocking SDK setup also disables JPush-delivered push notifications and any app
feature that directly depends on JCore/JPush. Method names with floating-point
or structure return values are intentionally skipped because substituting those
with a generic ARM64 implementation would be unsafe.
