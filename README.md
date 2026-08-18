# JPush Disable
After noticing some suspicious network traffic from the Farlight 84 game on my iPad and some research into the suspected SDK's included in the game's application, I created a simple Theos/Substrate tweak that prevents the embedded Jiguang/Aurora Mobile JCore and JPush SDK
from initialising, collecting data, or opening its reporting transports.

The tweak is currently set for 'Roothide' jailbreak compatibility injecting into Farlight 84.

Just change the target application's bundle identifier in the plist to what ever application you want to Silence.

## Who is Jiguang?
Chinese tech company Jiguang who is responsible for the JPush series of spyware, was found to have facilitated a robot toy manufacturer using there JPush library to secretly track and spy on children ([ftc.gov News Article](https://www.ftc.gov/news-events/news/press-releases/2025/09/ftc-takes-action-against-robot-toy-maker-allowing-collection-childrens-data-without-parental-consent)). 

Research by Reardon, Joel et al. in 2020 showed Jiguang’s SDK invasively monitors app users, collecting GPS locations, device identifiers, and app installation data, even when the app is not in use. This data is transmitted over UDP sockets with misused cryptography, making it vulnerable to eavesdropping. ([Link to the pdf](https://www.semanticscholar.org/paper/JPush-Away-Your-Privacy%3A-A-Case-Study-of-Jiguang%E2%80%99s-Reardon-Good/b2a87a558a49a13a66286bd3502ca03f23baa56f)) Reardon, Joel et al. “JPush Away Your Privacy: A Case Study of Jiguang’s Android SDK.” (2020).

## Build

```sh
make clean package
```

The Makefile selects `THEOS_PACKAGE_SCHEME=roothide`, change it to '=rootless' for rootless jailbreak support.

## Behaviour

At startup, the tweak replaces JPush telemetry action methods with no-op implementations using `MSHookMessageEx`, skipping methods with floating-point or structure return values.
