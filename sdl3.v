module main

import os
// import semver
import vab.android.ndk

struct SDL3Config {
	abo AndroidBuildOptions
	src SDLSource
}

fn libsdl3_node(config SDL3Config) !&Node {
	err_sig := @MOD + '.' + @FN

	abo := config.abo
	arch := abo.arch
	root := config.src.root
	version := config.src.version

	if version !in supported_sdl_versions {
		return error('${err_sig}: only versions ${supported_sdl_versions} is currently supported (not "${version}")')
	}

	// sem_version := semver.from(version) or {
	// 	return error('${err_sig}: could not convert SDL3 version ${version} to semantic version (semver)')
	// }

	// TODO: check these from time to time https://wiki.libsdl.org/SDL3/Android
	// >=31 for SDL > 3.2.0
	mut lib := new_node('SDL3', .build_dynamic_lib, arch, ['cpp'])

	if arch == 'armeabi-v7a' {
		lib.Node.tags << 'use-v7a-as-armeabi'
	}
	lib.attach_data(abo: abo)

	includes := os.join_path(root, 'include')

	build_config_headers := os.join_path(root, 'include', 'build_config')
	// build_config_generic_header := os.join_path(build_config_headers,'SDL_build_config.h')
	// build_config_android_header := os.join_path(build_config_headers,'SDL_build_config_android.h')
	// os.cp(build_config_generic_header,os.join_path(root,'include','SDL3',os.file_name(build_config_generic_header)))!
	// os.cp(build_config_android_header,os.join_path(root,'include','SDL3',os.file_name(build_config_android_header)))!

	lib.add_export('includes', includes, ['c', 'cpp'])!

	mut o_build := new_node('SDL3', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add_include(includes, ['c', 'cpp'])!
	o_build.add_include(os.join_path(root, 'src'), ['c', 'cpp'])!
	// o_build.add_include(os.join_path(includes,'SDL3'), ['c', 'cpp'])!
	o_build.add_include(build_config_headers, ['c', 'cpp'])!

	src := os.join_path(root, 'src')

	mut collect_paths := [src]
	collect_paths << [
		// os.join_path(src, 'atomic'), // See below
		os.join_path(src, 'audio'),
		os.join_path(src, 'audio', 'aaudio'),
		os.join_path(src, 'audio', 'dummy'),
		os.join_path(src, 'audio', 'openslES'),
		os.join_path(src, 'camera'),
		os.join_path(src, 'camera', 'android'),
		os.join_path(src, 'core'),
		os.join_path(src, 'core', 'android'),
		os.join_path(src, 'cpuinfo'),
		os.join_path(src, 'dialog'),
		os.join_path(src, 'dialog', 'android'),
		os.join_path(src, 'dynapi'),
		os.join_path(src, 'events'),
		os.join_path(src, 'filesystem'),
		os.join_path(src, 'filesystem', 'android'),
		os.join_path(src, 'filesystem', 'posix'),
		os.join_path(src, 'gpu'),
		os.join_path(src, 'gpu', 'vulkan'),
		os.join_path(src, 'haptic'),
		os.join_path(src, 'haptic', 'android'),
		os.join_path(src, 'hidapi'),
		os.join_path(src, 'hidapi', 'android'),
		os.join_path(src, 'io'),
		os.join_path(src, 'io', 'io_uring'),
		os.join_path(src, 'io', 'generic'),
		os.join_path(src, 'joystick'),
		os.join_path(src, 'joystick', 'android'),
		os.join_path(src, 'joystick', 'virtual'),
		os.join_path(src, 'joystick', 'hidapi'),
		os.join_path(src, 'libm'),
		os.join_path(src, 'loadso', 'dlopen'),
		os.join_path(src, 'locale'),
		os.join_path(src, 'locale', 'android'),
		// os.join_path(src, 'locale','dummy'),
		os.join_path(src, 'main'),
		os.join_path(src, 'main', 'generic'),
		os.join_path(src, 'misc'),
		os.join_path(src, 'misc', 'android'),
		os.join_path(src, 'power'),
		os.join_path(src, 'power', 'android'),
		// os.join_path(src, 'process'),
		// os.join_path(src, 'process', 'posix'),
		// Render
		os.join_path(src, 'render'),
		// os.join_path(src, 'render', 'direct3d'),
		// os.join_path(src, 'render', 'direct3d11'),
		// os.join_path(src, 'render', 'direct3d12'),
		// os.join_path(src, 'render', 'metal'),
		os.join_path(src, 'render', 'gpu'),
		os.join_path(src, 'render', 'vulkan'),
		os.join_path(src, 'render', 'opengl'),
		os.join_path(src, 'render', 'opengles2'),
		// os.join_path(src, 'render', 'psp'),
		os.join_path(src, 'render', 'software'),
		//
		os.join_path(src, 'sensor'),
		os.join_path(src, 'sensor', 'android'),
		os.join_path(src, 'stdlib'),
		os.join_path(src, 'storage'),
		os.join_path(src, 'storage', 'generic'),
		os.join_path(src, 'thread'),
		os.join_path(src, 'thread', 'generic'),
		os.join_path(src, 'thread', 'pthread'),
		os.join_path(src, 'time'),
		os.join_path(src, 'time', 'unix'),
		os.join_path(src, 'timer'),
		os.join_path(src, 'timer', 'unix'),
		os.join_path(src, 'tray'),
		os.join_path(src, 'tray', 'unix'),
		os.join_path(src, 'tray', 'dummy'),
		os.join_path(src, 'video'),
		os.join_path(src, 'video', 'android'),
		os.join_path(src, 'video', 'dummy'),
		os.join_path(src, 'video', 'khronos', 'vulkan'),
		os.join_path(src, 'video', 'khronos', 'vk_video'),
		os.join_path(src, 'video', 'khronos', 'KHR'),
		os.join_path(src, 'video', 'khronos', 'GLES3'),
		os.join_path(src, 'video', 'khronos', 'GLES2'),
		os.join_path(src, 'video', 'khronos', 'EGL'),
		os.join_path(src, 'video', 'yuv2rgb'),
		os.join_path(src, 'video', 'offscreen'),
		// os.join_path(src, 'test'),
	]
	mut collect_cpp_paths := []string{}

	if abo.verbosity > 1 {
		eprintln('Adding ${os.join_path(src, 'hidapi', 'android')} to C++ source collecting')
	}
	collect_cpp_paths << os.join_path(src, 'hidapi', 'android')

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
	// flags << '-Wno-unused-parameter -Wno-sign-compare'.split(' ')

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

	return &lib.Node
}
