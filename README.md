# midiot
A midi keyboard learning application

## Build

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate        # creates Midiot.xcodeproj from project.yml
open Midiot.xcodeproj    # then Run
```

Run the package tests with `swift test` inside `MidiotKit/`.

## Documentation

- [Requirements](docs/REQUIREMENTS.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Milestone 1 plan](docs/MILESTONE-1.md)
