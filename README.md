# HelloWorldObjC

This is a minimal Objective-C outerframe app that can be deployed to a static web server.

It includes:

- A standalone Xcode project that builds `HelloWorldObjC.bundle`
- Objective-C versions of the `OuterframeContentLibrary` and `OuterframeAppConnection` protocols
- C-native socket message definitions, encoders, callbacks, and host helpers for browser-content communication
- A Python script that generates the `.outer` descriptor
- A Python script that serves the generated site locally with the right MIME type for `.outer`

The `Vendor/OuterframeC/*.h` APIs are intentionally plain C: opaque handles, callbacks, enums, structs, and caller-managed buffers. Objective-C is only used where it is natural for macOS integration, such as the principal bundle class and `CALayer`/AppKit drawing code in `Frontend/`.

## Build

From this directory:

```bash
./build_site.sh
```

That produces a ready-to-upload static site in `build/site/`:

- `hello-world.outer`
- `binaries/HelloWorldObjC/index.html`
- `binaries/HelloWorldObjC/macos-arm`
- `binaries/HelloWorldObjC/macos-x86`

If you want the raw build command, `build_site.sh` runs `xcodebuild` against `HelloWorldObjC.xcodeproj` and then archives the built bundle with `aa`.

By default, the generated `.outer` file points at `/binaries/HelloWorldObjC`, so the uploaded site is intended to live at the web server root. If you want to host it under a subpath, set `BINARY_URL_PATH` when building:

```bash
BINARY_URL_PATH=/demo/binaries/HelloWorldObjC ./build_site.sh
```

## Local testing

Build the site, then serve it locally:

```bash
python3 Scripts/serve_site.py --root build/site --port 8025
```

Then open this URL in Outer Loop:

```text
http://127.0.0.1:8025/hello-world.outer
```

## Renaming This Template

If you copy this folder and rename it, update these places together:

- `HelloWorldObjC.xcodeproj`
- `Frontend/HelloWorldObjCContent.m`
- `build_site.sh`
- `README.md`
