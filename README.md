<img style="display:inline-block;" src="LOGO.png" alt="KBPulse" width="100" height="100">

# KBPulse
Pulse the backlight on your Mac keyboard

<a href="https://www.youtube.com/watch?v=0plJtiXuT0U">Demo</a>

## Compatibility
KBPulse should work on any MacBook running a version of macOS that has CoreBrightness.framework. I've confirmed that CoreBrightness exists in 10.13+, and probably even before then.

I have personally tested this on a 2020 M1 MacBook Pro 13" with Touch Bar. But CoreBrightness is a very abstract high-level framework and I'm willing to bet it works with *every* MacBook regardless of hardware.

## Installation
Build and install from the command line:

```sh
make run
```

`make run` builds the app and the embedded `kbpulse` CLI, signs the bundle
ad-hoc, installs the bundle of this machine into `/Applications` and launches
it. `make test` runs the test suite, `make verify` checks both bundles and
their embedded CLIs, and `make app` writes `build/KBPulse-arm64.app` and
`build/KBPulse-x86_64.app`.

KBPulse ships one bundle per architecture: `arm64` for Apple silicon and
`x86_64` for Intel. `make app-arm` and `make app-intel` build one of them.

## Building
The private header files are already included for you. You can also open
`KBPulse.xcodeproj` in Xcode and press Cmd-R or click Run.

You can open the build products folder and copy the binary to a directory of
your choice instead of using `make install`.

## Running
The embedded `kbpulse` CLI uses the same themes directory as the app:
`~/Library/Application Support/KBPulse`.

```sh
$ kbpulse list
$ kbpulse validate <file>
$ kbpulse set <profile>
$ kbpulse flash
$ kbpulse off
```

Run `kbpulse` with no command to animate `Yawn.json` directly.

## Releases
Cut a release with the shared target:

```sh
make release VERSION=1.2.3
git push origin main v1.2.3
```

`make release` moves `[Unreleased]` in `CHANGELOG.md` to the version, runs the
tests, builds and verifies the artifacts, commits the bump and creates the
annotated tag. It never pushes. Pushing the tag starts
`.github/workflows/release.yml`, which publishes
`KBPulse-<version>-arm64.dmg`, `KBPulse-<version>-x86_64.dmg` and
`checksums.txt`. Builds are ad-hoc signed and not notarized.

`checksums.txt` holds one line per disk image, in the shape that
`shasum -a 256 -c checksums.txt` verifies.

This checkout's `origin` is the upstream repository, which is not where a fork
publishes. Add your fork as a remote and name it on the release:

```sh
make release VERSION=1.2.3 REMOTE=fork
```

The target then prints `git push fork main` and `git push fork v1.2.3`.

## Configuration
Configuration files (.json) are stored in `~/Library/Application Support/KBPulse`. Yawn.json is the default theme. Copy it to make your own.
The array of animations is not limited to two animations. You can add as many as you want!

### Yawn.json
```json
{
  "Author" : "EthanRDoesMC",
  "Version" : "1.0.0",
  "Homepage" : "https:\/\/ethanrdoesmc.com\/",
  "Preview Image URL" : " ",
  "Animations" : [
    {
      "Description" : "Fades the keyboard to full brightness",
      "Name" : "Fade In",
      "Fade Duration" : 2500,
      "Brightness" : 1,
      "Delay" : 0
    },
    {
      "Description" : "Fades the keyboard to off",
      "Name" : "Fade Out",
      "Fade Duration" : 2500,
      "Brightness" : 0,
      "Delay" : 0
    }
  ],
  "Name" : "Yawn (default)",
  "Description" : "A calm, breath-like animation that somewhat resembles the sleep indicator on older MacBooks."
}
```
