# JPush Disable

A Theos/Substrate tweak for the RootHide bootstrap targeting iOS 15.6. It
neutralizes Objective-C methods belonging to the embedded Jiguang/Aurora
Mobile JCore and JPush SDK before the application begins normal execution.

The filter currently injects only into
`com.farlightgames.farlight84.iosglobal`. Change `JPushDisable.plist` if the
target application's bundle identifier differs.

## Build

Use the RootHide fork of Theos, then run:

```sh
make clean package
```

The Makefile selects `THEOS_PACKAGE_SCHEME=roothide`, an iOS 15.6 deployment
target, and both arm64 and arm64e slices.

## Behaviour

`JiguangClassNames.inc` records the 275 Jiguang Objective-C classes found across
the `SolarlandClient-aug26.h`, `SolarlandClient-aug26OBJC.h`, and
`SolarlandClient-aug26.c` IDA Pro 9 exports. At process startup, the tweak
matches runtime classes against that list and replaces every method declared by
those classes and their metaclasses. Scalar and object methods return zero
directly. Aggregate and uncommon return types go through Objective-C forwarding,
which returns a zero value of the size specified by `NSInvocation`. A dyld image
callback repeats the scan after later image loads, including methods added or
replaced by categories. It does not hook unrelated application classes or
networking.

Blocking SDK setup also disables JPush-delivered push notifications and any app
feature that directly depends on JCore/JPush. The tweak cannot undo work that a
Jiguang `+load` method or native static initializer completed before injection,
and it cannot interpose native C/C++ entry points that are not Objective-C
methods.

## Verification

Run `python3 -m unittest tests/test_jiguang_coverage.py`. The tests compare the
class list with all three IDA exports and compile a small Objective-C runtime
test for the supported return types.
