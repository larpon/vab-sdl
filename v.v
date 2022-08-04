module main

import os
import vab.android
// import vab.android.ndk


struct VBuildOptions {
	v_flags  []string
	input    string
	lib_name string
}

struct VSDL2Config {
	sdl2_configs []SDL2ConfigType
	abo          AndroidBuildOptions
	vbo          VBuildOptions
}

pub fn (vsc VSDL2Config) android_compile_options() android.CompileOptions {
	sdl2_configs := vsc.sdl2_configs
	abo := vsc.abo
	vbo := vsc.vbo

	// TODO
	mut c_flags := abo.flags
	c_flags << '-UNDEBUG'
	c_flags << '-D_FORTIFY_SOURCE=2'

	c_flags << ['-Wno-pointer-to-int-cast', '-Wno-constant-conversion', '-Wno-literal-conversion',
		'-Wno-deprecated-declarations']
	// V specific
	c_flags << ['-Wno-int-to-pointer-cast']

	// Even though not in use: prevent error: ("sokol_app.h: unknown 3D API selected for Android, must be SOKOL_GLES3 or SOKOL_GLES2")
	// And satisfy sokol_gfx.h:2571:2: error: "Please select a backend with SOKOL_GLCORE33, SOKOL_GLES2, SOKOL_GLES3, ... or SOKOL_DUMMY_BACKEND"
	c_flags << '-DSOKOL_GLES2'

	// Prevent: "ld: error: undefined symbol: glVertexAttribDivisorANGLE" etc.
	c_flags << '-DGL_EXT_PROTOTYPES'

	for sdl2_config in sdl2_configs {
		match sdl2_config {
			SDL2Config {
				c_flags << ['-I"' + os.join_path(sdl2_config.root, 'include') + '"']
			}
			SDL2ImageConfig {
				c_flags << ['-I"' + os.join_path(sdl2_config.root) + '"']
			}
			SDL2MixerConfig {
				c_flags << ['-I"' + os.join_path(sdl2_config.root) + '"']
			}
			SDL2TTFConfig {
				c_flags << ['-I"' + os.join_path(sdl2_config.root) + '"']
			}
		}
	}

	compile_cache_key := if os.is_dir(vbo.input) { vbo.input } else { '' } // || input_ext == '.v'
	acop := android.CompileOptions{
		verbosity: abo.verbosity
		cache: abo.cache
		cache_key: compile_cache_key
		parallel: abo.parallel
		is_prod: abo.is_prod
		no_printf_hijack: false
		v_flags: vbo.v_flags //['-g','-gc boehm'] //['-gc none']
		c_flags: c_flags
		archs: [abo.arch]
		work_dir: abo.work_dir
		input: vbo.input // abo.input
		ndk_version: abo.ndk_version
		lib_name: 'main' // abo.lib_name
		api_level: abo.api_level
		min_sdk_version: abo.min_sdk_version
	}

	return acop
}

fn libv_node(config VSDL2Config) !&Node {
	// err_sig := @MOD + '.' + @FN

	sdl2_configs := config.sdl2_configs
	abo := config.abo
	vbo := config.vbo
	arch := abo.arch

	heap_v_config := &VSDL2Config{
		...config
	}

	mut v_to_c := &Node{
		id: 'v_to_c.$arch'
		note: 'Compile V to C for $arch'
		tags: ['v', 'v2c', '$arch']
	}

	v_to_c.data['v_config'] = voidptr(heap_v_config)
	v_to_c.funcs['pre_build'] = compile_v_to_c

	mut lib := new_node(vbo.lib_name, .build_dynamic_lib, arch, ['cpp'])
	if arch == 'armeabi-v7a' {
		lib.Node.tags << 'use-v7a-as-armeabi'
	}
	lib.attach_data(abo: abo)

	lib.funcs['pre_build'] = collect_v_c_o_files
	lib.data['v_config'] = voidptr(heap_v_config)

	for sdl2_config in sdl2_configs {
		match sdl2_config {
			SDL2Config {
				lib.add('libs', as_heap(id: 'SDL2', tags: ['dynamic', '$arch']))
			}
			SDL2ImageConfig {
				lib.add('libs', as_heap(id: 'SDL2_image', tags: ['dynamic', '$arch']))
			}
			SDL2MixerConfig {
				lib.add('libs', as_heap(id: 'SDL2_mixer', tags: ['dynamic', '$arch']))
			}
			SDL2TTFConfig {
				lib.add('libs', as_heap(id: 'SDL2_ttf', tags: ['dynamic', '$arch']))
			}
		}
	}

	mut ldflags := ['-landroid', '-llog', '-lc', '-lm', '-lEGL', '-lGLESv1_CM', '-lGLESv2']
	for flag in ldflags {
		lib.add_flag(flag, ['c', 'cpp'])!
	}

	lib.add('dependencies', v_to_c)

	return &lib.Node
}

fn compile_v_to_c(mut n Node) ! {
	err_sig := @MOD + '.' + @FN

	if 'v_config' !in n.data.keys() {
		return error('$err_sig: no data["v_config"] in node $n.id')
	}
	v_config := &VSDL2Config(n.data['v_config'])
	// sdl2_configs := v_config.sdl2_configs
	// vbo := v_config.vbo
	abo := v_config.abo

	acop := v_config.android_compile_options()
	// TODO ? Building the .so will fail - but right now it's nice to piggyback
	// on all the other parts that succeed
	if _ := android.compile(acop) {
		// Just continue
		if abo.verbosity > 2 {
			eprintln('V to C compiling succeeded')
		}
	} else {
		if err is android.CompileError {
			if err.kind != .o_to_so {
				return error('$err_sig: unexpected compile error: $err.err')
			} else {
				if abo.verbosity > 2 {
					eprintln('V to C compiling failed compiling .o to .so, that is okay for now')
				}
			}
		} else {
			return error('$err_sig: unexpected compile error: $err')
		}
	}
}

fn collect_v_c_o_files(mut n Node) ! {
	err_sig := @MOD + '.' + @FN

	if 'v_config' !in n.data.keys() {
		return error('$err_sig: no data["v_config"] in node $n.id')
	}
	v_config := &VSDL2Config(n.data['v_config'])
	// sdl2_configs := v_config.sdl2_configs
	// vbo := v_config.vbo
	abo := v_config.abo
	arch := abo.arch

	acop := v_config.android_compile_options()

	build_dir := acop.build_directory()!

	// TODO compile v .so main
	mut o_files := []string{}
	o_file_path := os.join_path(build_dir, 'o', arch)
	if abo.verbosity > 1 {
		eprintln('Collecting V -> C .o files from "$o_file_path"')
	}

	o_ls := os.ls(o_file_path) or { []string{} }
	for f in o_ls {
		if f.ends_with('.o') {
			o_files << os.join_path(o_file_path, f)
		}
	}
	for o_file in o_files {
		n.add('o', as_heap(id: o_file, note: 'V -> C source .o file', tags: ['o', 'file', '$arch']))
	}
}
