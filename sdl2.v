module main

import os
import vab.android.ndk

type SDL2ConfigType = SDL2Config | SDL2ImageConfig | SDL2MixerConfig | SDL2TTFConfig

struct SDL2Config {
	abo  AndroidBuildOptions
	root string
}

fn libsdl2_node(config SDL2Config) !&Node {
	err_sig := @MOD + '.' + @FN

	abo := config.abo
	arch := abo.arch
	root := config.root
	version := abo.version

	// TODO test *all* versions
	if version != '2.0.20' {
		return error('$err_sig: TODO only 2.0.20 is currently supported (not "$version")')
	}

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
	collect_paths << [
		os.join_path(src, 'audio'),
		os.join_path(src, 'audio', 'android'),
		os.join_path(src, 'audio', 'dummy'),
		os.join_path(src, 'audio', 'aaudio'),
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
		os.join_path(src, 'joystick', 'virtual'),
		os.join_path(src, 'loadso', 'dlopen'),
		os.join_path(src, 'locale'),
		os.join_path(src, 'locale', 'android'),
		os.join_path(src, 'misc'),
		os.join_path(src, 'misc', 'android'),
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
		os.join_path(src, 'render', 'vitagxm'),
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

	mut collect_cpp_paths := [
		os.join_path(src, 'hidapi', 'android'),
	]

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

	flags << '-ldl -lGLESv1_CM -lGLESv2 -lOpenSLES -llog -landroid'.split(' ')
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
		id: cpuf_root
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
			id: flag
			note: 'build flag'
			tags: ['c', 'cpp', 'flag', 'warning']
		))
	}
	flags.clear()

	a_build.add('dependencies', &o_build.Node)
	return &a_build.Node
}
