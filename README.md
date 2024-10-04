# vab-sdl

Extends [`vab`](https://github.com/vlang/vab) to support compiling V applications that use [`vlang/sdl`](https://github.com/vlang/sdl).

`vab-sdl` is an [*extra command*](https://github.com/vlang/vab/blob/master/docs/docs.md#extending-vab) for [`vlang/vab`](https://github.com/vlang/vab/) (also works as a standalone tool).

## Features

`vab-sdl` is pure V software that can download and compile SDL2 from source using *only*
the Android NDK provided compilers.
That means you do not need to have `cmake`, `gradle` or anything else installed in order to
compile and run V source code that does `import sdl` on Android.

It makes development of SDL2-based V applications on Android a little more fun ;)

## Prerequisites

* An application or example that import [`vlang/sdl`](https://github.com/vlang/sdl).
* A ***working*** install of the [`vab`](https://github.com/vlang/vab/) command-line tool compiled with `-d vab_allow_extra_commands`.

To compile `vab` with the *extra command* feature you can build `vab` like in this example:
```bash
v -d vab_allow_extra_commands ~/.vmodules/vab
```

Make sure you read the section about [extending `vab`](https://github.com/vlang/vab/blob/master/docs/docs.md#extending-vab) in `vab`'s documentation.

## Install

To install and make this extra command available as "`vab sdl`" run the following:
```bash
vab install extra larpon/vab-sdl
vab doctor # Should show a section with installed extra commands where `vab-sdl` should show.
```

## Usage

Once `vab-sdl` is installed you can test it with:
```bash
vab sdl ~/.vmodules/sdl/examples/basic_window -o /tmp/sdl_app.apk
```
## Good To Know

* `vab-sdl` is relatively new and still has rough edges.
* Currently support for `sdl.image` and `sdl.mixer` is still WIP.
* As a convenience `vab-sdl` wraps *most* of `vab`'s existing functionality, but not *all*.
* Run `vab sdl doctor` to see the state of the tool.
* Run `vab sdl -h` for an overview of how to invoke the tool.
