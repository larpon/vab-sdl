# vab-sdl

Extends [`vab`](https://github.com/vlang/vab) to support compiling V applications that use [`vlang/sdl`](https://github.com/vlang/sdl).

`vab-sdl` can be used standalone or as an [*extra command*](https://github.com/vlang/vab/blob/master/docs/docs.md#extending-vab)
for [`vlang/vab`](https://github.com/vlang/vab/).

Any issues about this extra command should be reported to this project,
not to the `v` or `vab` projects.

## Features

`vab-sdl` is pure V software that can download and compile SDL2 for Android from source
using *only* the Android NDK provided compilers (in parallel).
That means you do not need to use `cmake`, `gradle` or anything else in order to
compile and run V source code that does `import sdl` on Android. Because of this
build times is greatly improved in contrast to SDL2's own solution that is
based on `gradle` and `ndk-build`.

## Prerequisites

* An application or example that import [`vlang/sdl`](https://github.com/vlang/sdl).
* A ***working*** install of the [`vab`](https://github.com/vlang/vab/) command-line tool compiled with `-d vab_allow_extra_commands`.

To compile `vab` with the *extra command* feature you can build `vab` like in this example:
```bash
v -d vab_allow_extra_commands ~/.vmodules/vab
```

Make sure you read the section about [extending `vab`](https://github.com/vlang/vab/blob/master/docs/docs.md#extending-vab) in `vab`'s documentation.

## Install

### `vab` extra command

To install and make this extra command available as "`vab sdl`" run the following:
```bash
vab install extra larpon/vab-sdl
vab doctor # Should show a section with installed extra commands where `vab-sdl` should show.
```

### Standalone
To install as a standalone tool:
 ```bash
 git clone https://github.com/larpon/vab-sdl.git
 v ./vab-sdl && cd ./vab-sdl
 ./vab-sdl -h # or ./vab-sdl doctor
 ```

## Usage

Once `vab-sdl` is installed you can test it with:
```bash
vab sdl ~/.vmodules/sdl/examples/tvintris -o /tmp/tvintris.apk
```

... or if used as standalone tool:
```bash
./vab-sdl ~/.vmodules/sdl/examples/tvintris -o /tmp/tvintris.apk
```

The first time the above command is run it will download all needed SDL2 dependencies
(including SDL2_image, SDL2_mixer and/or SDL2_ttf) to a cache location
and then *build each dependency specifically for Android* without invoking anything
but the Android NDK compilers and tools. When it has built the dependencies it will
package the SDL2 based application into an APK package using the SDL2 source's own
main activity (`SDLActivity`). Since `vab-sdl` is basically just a modified
reimplementation of `vab`'s main function `vab.v` it can be used as just like
`vab` itself. That means you can pass the same flags to `vab-sdl` as you can pass
to `vab` - this includes the `run` command for easy running and testing of apps.

Example:
```bash
vab sdl run ~/.vmodules/sdl/examples/tvintris
```

## Good To Know

* `vab-sdl` ships it's own modules for building SDL2 from source.
* As a convenience `vab-sdl` wraps *most* of `vab`'s existing functionality, if
  something is missing or broken please open an issue with this project.
* Run `vab sdl doctor` to see the state of the tool.
* Run `vab sdl -h` for an overview of how to invoke the tool.
