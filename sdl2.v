module main

import os
import semver
import vab.android.ndk

struct SDL2Config {
	abo AndroidBuildOptions
	src SDLSource
}

fn libsdl2_node(config SDL2Config) !&Node {
	err_sig := @MOD + '.' + @FN

	abo := config.abo
	arch := abo.arch
	root := config.src.root
	version := config.src.version

	wip_not_supported := ['2.0.8', '2.0.9', '2.0.10', '2.0.12'] // GOAL: all 2.x in supported_sdl_versions
	if version in wip_not_supported {
		return error('${err_sig}: versions ${wip_not_supported} is currently *not* supported (or WIP). Try with a newer version of SDL2"')
	}

	if version !in supported_sdl_versions {
		return error('${err_sig}: only versions ${supported_sdl_versions} is currently supported (not "${version}")')
	}

	sem_version := semver.from(version) or {
		return error('${err_sig}: could not convert SDL2 version ${version} to semantic version (semver)')
	}

	// TODO: check these from https://wiki.libsdl.org/SDL2/Android
	// >=12 for SDL < 2.0.8
	// >=19 for SDL >= 2.0.8
	// >=26 for SDL >= 2.0.16
	// >=31 for SDL >= 2.0.18

	mut lib := new_node('SDL2', .build_dynamic_lib, arch, ['cpp'])

	if arch == 'armeabi-v7a' {
		lib.Node.tags << 'use-v7a-as-armeabi'
	}
	lib.attach_data(abo: abo)

	includes := os.join_path(root, 'include')

	lib.add_export('includes', includes, ['c', 'cpp'])!

	mut o_build := new_node('SDL2', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add_include(includes, ['c', 'cpp'])!

	src := os.join_path(root, 'src')

	mut collect_paths := [src]
	if sem_version.satisfies('>=2.0.14') {
		collect_paths << os.join_path(src, 'joystick', 'virtual')
		collect_paths << os.join_path(src, 'locale')
		collect_paths << os.join_path(src, 'locale', 'android')
		collect_paths << os.join_path(src, 'misc')
		collect_paths << os.join_path(src, 'misc', 'android')
	}
	if sem_version.satisfies('>=2.0.16') {
		collect_paths << os.join_path(src, 'audio', 'aaudio')
		collect_paths << os.join_path(src, 'render', 'vitagxm')
	}
	collect_paths << [
		os.join_path(src, 'audio'),
		os.join_path(src, 'audio', 'android'),
		os.join_path(src, 'audio', 'dummy'),
		os.join_path(src, 'audio', 'openslES'),
		os.join_path(src, 'core', 'android'),
		os.join_path(src, 'cpuinfo'),
		os.join_path(src, 'dynapi'),
		os.join_path(src, 'events'),
		os.join_path(src, 'file'),
		os.join_path(src, 'haptic'),
		os.join_path(src, 'haptic', 'android'),
		os.join_path(src, 'hidapi'),
		os.join_path(src, 'joystick'),
		os.join_path(src, 'joystick', 'android'),
		os.join_path(src, 'joystick', 'hidapi'),
		os.join_path(src, 'loadso', 'dlopen'),
		os.join_path(src, 'power'),
		os.join_path(src, 'power', 'android'),
		os.join_path(src, 'filesystem', 'android'),
		os.join_path(src, 'sensor'),
		os.join_path(src, 'sensor', 'android'),
		// Render
		os.join_path(src, 'render'),
		os.join_path(src, 'render', 'direct3d'),
		os.join_path(src, 'render', 'direct3d11'),
		os.join_path(src, 'render', 'metal'),
		os.join_path(src, 'render', 'opengl'),
		os.join_path(src, 'render', 'opengles'),
		os.join_path(src, 'render', 'opengles2'),
		os.join_path(src, 'render', 'psp'),
		os.join_path(src, 'render', 'software'),
		//
		os.join_path(src, 'stdlib'),
		os.join_path(src, 'thread'),
		os.join_path(src, 'thread', 'pthread'),
		os.join_path(src, 'timer'),
		os.join_path(src, 'timer', 'unix'),
		os.join_path(src, 'video'),
		os.join_path(src, 'video', 'android'),
		os.join_path(src, 'video', 'yuv2rgb'),
		os.join_path(src, 'test'),
	]
	mut collect_cpp_paths := []string{}

	if sem_version.satisfies('>=2.0.18') {
		if abo.verbosity > 1 {
			eprintln('Adding ${os.join_path(src, 'hidapi', 'android')} to C++ source collecting')
		}
		collect_cpp_paths << os.join_path(src, 'hidapi', 'android')
	}

	// Collect source files
	mut c_files := []string{}
	mut c_arm_files := []string{}
	mut cpp_files := []string{}

	// Collect C files
	for collect_path in collect_paths {
		collect_flat_ext(collect_path, mut c_files, '.c')
	}
	// Collect C files that should compiled as arm (not thumb)
	c_arm_files << [
		os.join_path(src, 'atomic', 'SDL_atomic.c'),
		os.join_path(src, 'atomic', 'SDL_spinlock.c'),
	]
	// Collect C++ files
	for collect_path in collect_cpp_paths {
		collect_flat_ext(collect_path, mut cpp_files, '.cpp')
	}

	for source in c_files {
		o_build.add_source(source, ['c'])!
	}

	for source in c_arm_files {
		o_build.add_source(source, ['c', 'arm'])!
	}

	for source in cpp_files {
		o_build.add_source(source, ['cpp'])!
	}

	mut flags := ['-Wall', '-Wextra', '-Wdocumentation', '-Wdocumentation-unknown-command',
		'-Wmissing-prototypes', '-Wunreachable-code-break', '-Wunneeded-internal-declaration',
		'-Wmissing-variable-declarations', '-Wfloat-conversion', '-Wshorten-64-to-32',
		'-Wunreachable-code-return', '-Wshift-sign-overflow', '-Wstrict-prototypes',
		'-Wkeyword-macro']
	// SDL/JNI specifics that aren't fixed yet
	flags << '-Wno-unused-parameter -Wno-sign-compare'.split(' ')

	for flag in flags {
		o_build.add_flag(flag, ['c', 'cpp'])!
	}
	flags.clear()

	flags << '-DGL_GLEXT_PROTOTYPES'
	for flag in flags {
		o_build.add_flag(flag, ['c', 'cpp'])!
	}
	flags.clear()

	// TODO sokol mess it is GLESv3 now, old: flags << '-ldl -lGLESv1_CM -lGLESv2 -lOpenSLES -llog -landroid'.split(' ')
	flags << '-ldl -lGLESv1_CM -lGLESv3 -lOpenSLES -llog -landroid'.split(' ')
	for flag in flags {
		lib.add_flag(flag, [])!
	}

	lib.add('dependencies', &o_build.Node)

	// cpu-features
	cpu_features_root := os.join_path(ndk.root_version(abo.ndk_version), 'sources', 'android',
		'cpufeatures')

	lib.add_link_lib('cpufeatures', .@static, arch, [])!

	o_build.add_include(cpu_features_root, ['c', 'cpp'])!

	cpuf_build := libcpufeatures_node(cpu_features_root, abo)!

	lib.add('dependencies', cpuf_build)

	if sem_version.satisfies('<=2.0.16') {
		lib.add_link_lib('hidapi', .dynamic, arch, [])!

		hidapi_build := libhidapi_node(config)!

		// Add lib's includes to SDL2's C -> .o build
		if hidapi_o_build := hidapi_build.find_nearest(id: 'hidapi', tags: ['o', 'build', '${arch}']) {
			if hidapi_includes := hidapi_o_build.items['includes'] {
				for hidapi_include_node in hidapi_includes {
					o_build.add_include(hidapi_include_node.id, ['c', 'cpp'])!
				}
			}
		}

		lib.add('dependencies', hidapi_build)
	}

	return &lib.Node
}

fn libhidapi_node(config SDL2Config) !&Node {
	err_sig := @MOD + '.' + @FN

	abo := config.abo
	arch := abo.arch
	root := config.src.root
	version := config.src.version

	sem_version := semver.from(version) or {
		return error('${err_sig}: could not convert SDL2 version ${version} to semantic version (semver)')
	}

	if !sem_version.satisfies('<=2.0.16') {
		return error('${err_sig}: only versions <= 2.0.16 is currently supported (not "${version}")')
	}

	hidapi_root := os.join_path(root, 'src', 'hidapi')
	libhidapi_android_src := os.join_path(hidapi_root, 'android')

	mut so_build := new_node('hidapi', .build_dynamic_lib, arch, [])
	so_build.attach_data(abo: abo)

	mut o_build := new_node('hidapi', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	so_build.add('dependencies', &o_build.Node)

	// o_build.add_flag('-Wno-duplicate-decl-specifier',['c','cpp'])!

	includes := [
		os.join_path(hidapi_root, 'hidapi'),
	]

	for include in includes {
		o_build.add_include(include, ['c', 'cpp'])!
	}

	mut sources := []string{}
	sources << [
		os.join_path(libhidapi_android_src, 'hid.cpp'),
	]
	// mut flags := []string{}
	// flags << '-DANDROID_STL=c++_shared'
	// for flag in flags {
	// 	o_build.add_flag(flag, ['c', 'cpp'])!
	// }
	mut ldflags := ['-llog', '-lstdc++']
	for flag in ldflags {
		so_build.add_flag(flag, ['c', 'cpp'])!
	}

	for source in sources {
		o_build.add_source(source, ['c', 'cpp'])!
	}
	sources.clear()

	return &so_build.Node
}
