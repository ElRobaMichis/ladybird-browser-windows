# Ladybird Browser for Windows (unofficial builds)

[![Windows Build](https://github.com/ElRobaMichis/ladybird-browser-windows/actions/workflows/build-windows.yml/badge.svg)](https://github.com/ElRobaMichis/ladybird-browser-windows/actions/workflows/build-windows.yml)
[![Latest release](https://img.shields.io/github/v/release/ElRobaMichis/ladybird-browser-windows?label=download)](https://github.com/ElRobaMichis/ladybird-browser-windows/releases/latest)

Unofficial, automated Windows x64 builds of the [Ladybird](https://ladybird.org) web browser, compiled from the
upstream source code with GitHub Actions.

The official Ladybird alpha is available for macOS and Linux only. Ladybird's source code already contains an
experimental native Windows port, and this repository builds it, so you can try Ladybird on Windows 10 and 11 without
setting up a build environment.

> [!WARNING]
> **These are not official Ladybird releases.** They are not made, endorsed or supported by the Ladybird Browser
> Initiative. Ladybird does not support Windows yet, so expect crashes and missing features.
> Please report Windows-specific problems [here](../../issues), not to the Ladybird project.

## Download

| Channel | Source | Where |
|---|---|---|
| **Alpha** (recommended) | Official Ladybird release tags | [Latest release](../../releases/latest) |
| **Nightly** | Latest upstream `master` | [Pre-releases](../../releases) |

1. Download the `.zip` file from a release.
2. Extract it anywhere.
3. Run `bin\Ladybird.exe`.

No installation is needed. The builds do not update themselves; download a newer release to update.

## Verifying a download

Every release links to the workflow run that built it, and ships with:

- `SHA256SUMS.txt`, the checksum of the package.
- A signed [build provenance attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations),
  which proves the file was produced by this repository's workflow on GitHub's servers:

  ```
  gh attestation verify <file>.zip --repo ElRobaMichis/ladybird-browser-windows
  ```

## How the builds are made

Everything happens in public, in [`.github/workflows/build-windows.yml`](.github/workflows/build-windows.yml):

1. The workflow checks [LadybirdBrowser/ladybird](https://github.com/LadybirdBrowser/ladybird) for a new release,
   or for new commits on `master`.
2. It checks out that exact upstream commit and applies the small Windows fixes in [`patches/`](patches). Each patch
   describes what it changes and why. There are no other changes to the source code.
3. It builds it with the same toolchain as Ladybird's own Windows CI: clang-cl, the MSVC libraries, vcpkg for the
   third-party libraries, and the Qt user interface.
4. [`package-windows.ps1`](.github/scripts/package-windows.ps1) packages the browser with the libraries, Qt plugins
   and runtime it needs, plus all license files.
5. The package is published as a GitHub release with its checksum and attestation.

The only build options that differ from a default Ladybird build are a portable CPU baseline and a disabled update
check. The update check would point to official releases, which have no Windows version.

The package also differs from a plain build in two ways:

- It includes Mozilla's list of trusted root certificates (`bin\cacert.pem`, from
  [curl.se](https://curl.se/docs/caextract.html)). Ladybird trusts it in addition to the Windows certificate store,
  which often lacks root certificates that Windows only installs on first use.
- Its programs are marked as Windows GUI applications, so the browser runs without a console window.

## Building it yourself

Follow Ladybird's [build instructions](https://github.com/LadybirdBrowser/ladybird/blob/master/Documentation/BuildInstructionsLadybird.md#windows).
The workflow in this repository is a working, step-by-step reference for a native Windows build.

## License and trademarks

- The scripts and workflows in this repository are licensed under the [MIT License](LICENSE).
- Ladybird is licensed under the [BSD 2-Clause License](https://github.com/LadybirdBrowser/ladybird/blob/master/LICENSE).
  Each package contains a `licenses` folder with the licenses of Ladybird and of every bundled library. Some of these
  libraries, such as Qt and FFmpeg, are licensed under the LGPL and are dynamically linked.
- The Ladybird name and logo are trademarks of the Ladybird Browser Initiative. These builds follow its
  [trademark policy](https://ladybird.org/trademark/) for third-party builds: they state who made them and that they
  are not official releases.
