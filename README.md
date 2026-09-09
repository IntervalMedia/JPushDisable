# JPush Disable
After noticing some suspicious network traffic from the Farlight 84 game on my iPad and some research into the suspected SDK's included in the game's application, I created a simple Theos/Substrate tweak that prevents the embedded Jiguang/Aurora Mobile JCore and JPush SDK
from initialising, collecting data, or opening its reporting transports.

A Theos/Substrate tweak for the RootHide bootstrap targeting iOS 15.6. It
neutralizes Objective-C methods belonging to the embedded Jiguang/Aurora
Mobile JCore and JPush SDK before the application begins normal execution.

The filter currently injects only into
`com.farlightgames.farlight84.iosglobal`. Change `JPushDisable.plist` if the
target application's bundle identifier differs.

## Who is Jiguang?
Chinese technology company Jiguang develops the JPush SDK. In 2025, the US
Federal Trade Commission alleged that a robot-toy manufacturer allowed the SDK
to collect children's precise geolocation data without parental consent
([FTC news release](https://www.ftc.gov/news-events/news/press-releases/2025/09/ftc-takes-action-against-robot-toy-maker-allowing-collection-childrens-data-without-parental-consent)).

Research published in 2020 also examined Jiguang's collection of location,
device-identifier, and installed-app data, including its UDP transport and
cryptography: Reardon, Joel et al., *JPush Away Your Privacy: A Case Study of
Jiguang's Android SDK* ([paper record](https://www.semanticscholar.org/paper/JPush-Away-Your-Privacy%3A-A-Case-Study-of-Jiguang%E2%80%99s-Reardon-Good/b2a87a558a49a13a66286bd3502ca03f23baa56f)).

## Build

Requires Theos to build.
Clone or download this repo and edit the .plist file to include your target application id.
The Makefile selects `THEOS_PACKAGE_SCHEME=roothide`, change it to '=rootless' for rootless jailbreak support.

```sh
make clean package
```

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
