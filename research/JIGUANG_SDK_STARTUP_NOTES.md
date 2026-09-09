# Jiguang SDK startup notes

This note separates published integration requirements from hypotheses about the
IDA-derived class inventory. It is not evidence that any Jiguang class is safe
to run wholesale.

## Published integration facts

- JPush's iOS integration guide describes JCore as a required companion binary
  for JPush and tells integrators to link both the JPush and JCore
  XCFrameworks. It also lists Foundation, UIKit, Security, UserNotifications,
  and networking frameworks used by the SDK: [JPush iOS integration guide](https://docs.jiguang.cn/en/jpush/client/iOS/ios_guide_new).
- The quick-start path initializes the SDK from the application launch path,
  registers for remote notifications, and later passes the APNs device token to
  JPush: [iOS quick start](https://docs.jiguang.cn/jpush/quickstart/iOS_quick).
- Current API documentation describes `turnOffPush:` as pausing JPush
  connections, reconnects, and data reporting, while `turnOnPush` restores
  those capabilities. This confirms that connection/reporting is a distinct
  runtime subsystem rather than mere object construction: [iOS API guide](https://docs.jiguang.cn/en/jpush/client/iOS/ios_api).
- The official GitHub release notes currently identify JPush iOS 6.2.2 and a
  minimum JCore 5.5.1 dependency. Version skew is therefore a plausible cause
  of behavior differences between the published SDK and this app's embedded
  binary: [JPush releases](https://github.com/jpush/jpush-sdk/releases).

## Cross-reference to this binary's inventory

The IDA exports identify 275 classes. The most relevant groups are:

- `JPUSHService`, `JPUSHClientController`, notification/token/tag-alias
  controllers: public JPush setup and push behavior.
- `JCOREService`, `JCOREServiceController`, `JCORENetworkController`,
  `JCOREConnectManager`, socket/channel/request classes: transport and
  reconnect behavior.
- `JCORERegister`, `JCORESDKControl`, `JCOREClientInfo`, and
  `JCOREDecoder`: registration/control and request/response support. A Jiguang
  community linker report independently shows `JPUSHClientController` and
  `JPUSHService` referencing JCORE transport, logger, decoder, cache, and
  client-info classes, including `JCORETcpObject`, `JCOREConnectManager`,
  `JCOREService`, `JCOREDecoder`, `JCORELogger`, `JCOREClientInfo`, and
  `JCOREThread`: [community linker report](https://community.jiguang.cn/question/424398).
- `JCOREDataControl` contains switches for model, OS version, resolution,
  language, operator, Wi-Fi, cell, GPS, and app-list data in the exported
  layout. `JCommon*` crash/report/paste/app-list classes and `JGInforCollectionAuth*`
  are therefore high-risk collection/reporting candidates and should remain
  blocked during launch compatibility work.

## Current incremental policy

The first change does **not** allow any Jiguang class to execute wholesale. It
preserves only Objective-C lifecycle/runtime plumbing (`init*`, object identity,
copy/release, and common singleton accessors). SDK action methods, collection,
transport, logging, registration, and reporting methods remain neutralized.

This is intentionally narrower than allowing `JCOREService` or
`JCORERegister`; those classes are directly associated with connection and
registration behavior and should only be admitted after a device crash log
identifies a specific required selector.

## Evidence still needed

The local tests cannot reproduce a device launch. The next probe needs the
earliest crash/termination record from a launch with the tweak enabled,
including exception type, terminating selector/class, and the last
`[JPushDisable]` log line. Without that artifact, enabling whole classes would
be guesswork and could silently reopen telemetry or network reporting.
