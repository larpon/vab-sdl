module main

import os

type SDLConfigType = SDL3Config | SDL2Config | SDL2ImageConfig | SDL2MixerConfig | SDL2TTFConfig

@[noinit]
struct SDLSource {
	root    string // root of the SDL source distribution
	version string
}

fn (ss &SDLSource) path_android_project() !string {
	return os.join_path(ss.root, 'android-project')
}

fn (ss &SDLSource) path_android_base_files() !string {
	return os.join_path(ss.path_android_project()!, 'app', 'src', 'main')
}

fn (ss &SDLSource) path_android_java_sources() !string {
	return os.join_path(ss.path_android_base_files()!, 'java')
}

fn SDLSource.make(sdl_src_path string) !SDLSource {
	root := sdl_src_path.trim_right('/\\')
	if !os.is_dir(root) {
		return error('${@STRUCT}.${@FN}:${@LINE}: "${sdl_src_path}" is not a directory')
	}

	mut hint_major := 0
	if os.is_file(os.join_path(root, 'README-SDL.txt')) {
		hint_major = 2
	} else if os.is_file(os.join_path(root, 'README.md')) {
		hint_major = 3
	} else {
		return error('${@STRUCT}.${@FN}:${@LINE}: could not identify "${sdl_src_path}" as an SDL source root (missing README-SDL.txt (SDL2) or README.md (SDL3)')
	}

	if hint_major == 0 {
		return error('${@STRUCT}.${@FN}:${@LINE}: could not identify "${sdl_src_path}" as an SDL source root (no SDL version hint was found')
	}

	sdl_version_h := if hint_major == 2 {
		os.join_path(root, 'include', 'SDL_version.h')
	} else {
		os.join_path(root, 'include', 'SDL3', 'SDL_version.h')
	}
	if !os.is_file(sdl_version_h) {
		return error('${@STRUCT}.${@FN}:${@LINE}: could not find file "${sdl_version_h}" to indentify SDL\'s version')
	}
	sdl_version_h_lines := os.read_lines(sdl_version_h) or {
		return error('${@STRUCT}.${@FN}:${@LINE}: could not read lines in file "${sdl_version_h}" to indentify SDL\'s version (${err})')
	}
	mut v_major := 0
	mut v_minor := 0
	mut v_patch := 0
	for line in sdl_version_h_lines {
		if line.contains('#define') {
			if line.contains('SDL_MAJOR_VERSION') {
				v_major = line.all_after('SDL_MAJOR_VERSION').trim_space().int()
			}
			if line.contains('SDL_MINOR_VERSION') {
				v_minor = line.all_after('SDL_MINOR_VERSION').trim_space().int()
			}
			if line.contains('SDL_PATCHLEVEL') {
				v_patch = line.all_after('SDL_PATCHLEVEL').trim_space().int()
			} else if line.contains('SDL_MICRO_VERSION') {
				v_patch = line.all_after('SDL_MICRO_VERSION').trim_space().int()
			}
		}
	}
	if v_major == 0 && v_minor == 0 {
		return error('${@STRUCT}.${@FN}:${@LINE}: could not determine SDL\'s version from file "${sdl_version_h}" (obtained so far: ${v_major}.${v_minor}.${v_patch})')
	}
	return SDLSource{
		root:    root
		version: '${v_major}.${v_minor}.${v_patch}'
	}
}

fn collect_flat_ext(path string, mut files []string, ext string) {
	ls := os.ls(path) or { panic(err) }
	for file in ls {
		if file.ends_with(ext) {
			files << os.join_path(path.trim_string_right(os.path_separator), file)
		}
	}
}

fn libcpufeatures_node(cpuf_root string, abo AndroidBuildOptions) !&Node {
	arch := abo.arch

	mut a_build := new_node('cpufeatures', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('cpufeatures', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add('includes', as_heap(
		id:   cpuf_root
		note: 'C header include'
		tags: [
			'c',
			'include',
		]
	))

	mut sources := []string{}
	sources << [
		os.join_path(cpuf_root, 'cpu-features.c'),
	]
	for source in sources {
		o_build.add('sources', as_heap(id: source, note: 'C source', tags: ['c', 'source', 'file']))
	}

	mut flags := ['-Wall', '-Wextra', '-Werror']
	for flag in flags {
		o_build.add('flags', as_heap(
			id:   flag
			note: 'build flag'
			tags: ['c', 'cpp', 'flag', 'warning']
		))
	}
	flags.clear()

	a_build.add('dependencies', &o_build.Node)
	return &a_build.Node
}
