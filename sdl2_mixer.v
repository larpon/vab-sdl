module main

import os

struct SDL2MixerFeatures {
	flac         bool = true
	ogg          bool = true
	mp3_mpg123   bool = true
	mod_modplug  bool = true
	mid_timidity bool = true
}

struct SDL2MixerConfig {
	features SDL2MixerFeatures
	abo      AndroidBuildOptions
	root     string
}

fn libsdl2_mixer_node(config SDL2MixerConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch
	// version := abo.version

	mut lib := new_node('SDL2_mixer', .build_dynamic_lib, arch, ['cpp'])
	if arch == 'armeabi-v7a' {
		lib.Node.tags << 'use-v7a-as-armeabi'
	}
	lib.attach_data(abo: abo)
	lib.add_link_lib('SDL2', .dynamic, arch, [])!

	lib.add_export('include', root, ['c', 'cpp'])!

	mut o_build := new_node('SDL2_mixer', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add_include(root, ['c', 'cpp'])!

	mut sources := []string{}

	// SDL_mixer .c files
	collect_flat_ext(root, mut sources, '.c')
	sources = sources.filter(os.file_name(it) !in ['playmus.c', 'playwave.c'])

	for source in sources {
		o_build.add_source(source, ['c'])!
	}

	lib.add('dependencies', &o_build.Node)

	// libFLAC
	if config.features.flac {
		// flac_root := os.join_path(root, 'external', 'flac-1.3.2')
		lib.add_link_lib('FLAC', .@static, arch, [])!

		o_build.add_flag('-DMUSIC_FLAC', ['c', 'cpp'])!

		flac_build := libflac_node(config)!

		// Add all FLAC includes to SDL2_mixer's C -> .o build
		if flac_o_build := flac_build.find_nearest(id: 'FLAC', tags: ['o', 'build', '$arch']) {
			if includes := flac_o_build.items['includes'] {
				for include_node in includes {
					o_build.add_include(include_node.id, ['c', 'cpp'])!
				}
			}
		}

		lib.add('dependencies', flac_build)

		// If libogg is not included we need to include libvorbis headers
		if !config.features.ogg {
			// ogg_root := os.join_path(root, 'external', 'libogg-1.3.2')
			lib.add_link_lib('ogg', .@static, arch, [])!
			ogg_build := libogg_node(config)!

			// Add all ogg includes to SDL2_mixer's C -> .o build
			if ogg_o_build := ogg_build.find_nearest(id: 'ogg', tags: ['o', 'build', '$arch']) {
				ogg_o_build_an := AndroidNode{
					Node: ogg_o_build
				}
				vorbis_root := os.join_path(root, 'external', 'libvorbis-1.3.5')
				ogg_o_build_an.add_include(os.join_path(vorbis_root, 'include'), ['c', 'cpp'])!

				if includes := ogg_o_build.items['includes'] {
					for include_node in includes {
						o_build.add_include(include_node.id, ['c', 'cpp'])!
					}
				}
			}

			lib.add('dependencies', ogg_build)
		}
	}

	// libogg
	if config.features.ogg {
		// ogg_root := os.join_path(root, 'external', 'libogg-1.3.2')
		lib.add_link_lib('ogg', .@static, arch, [])!

		flags := '-DMUSIC_OGG -DOGG_USE_TREMOR -DOGG_HEADER="<ivorbisfile.h>"'.split(' ')
		for flag in flags {
			o_build.add_flag(flag, ['c', 'cpp'])!
		}

		ogg_build := libogg_node(config)!

		// Add all ogg includes to SDL2_mixer's C -> .o build
		if ogg_o_build := ogg_build.find_nearest(id: 'ogg', tags: ['o', 'build', '$arch']) {
			if includes := ogg_o_build.items['includes'] {
				for include_node in includes {
					o_build.add_include(include_node.id, ['c', 'cpp'])!
				}
			}
		}

		lib.add('dependencies', ogg_build)

		// libvorbisidec
		// vorbisidec_root := os.join_path(root, 'external', 'libvorbisidec-1.2.1')
		lib.add_link_lib('vorbisidec', .@static, arch, [])!

		vorbisidec_build := libvorbisidec_node(config)!

		// Add lib's includes to SDL2_mixer's C -> .o build
		if vorbisidec_o_build := vorbisidec_build.find_nearest(
			id: 'vorbisidec'
			tags: [
				'o',
				'build',
				'$arch',
			]
		)
		{
			if includes := vorbisidec_o_build.items['includes'] {
				for include_node in includes {
					o_build.add_include(include_node.id, ['c', 'cpp'])!
				}
			}
		}

		lib.add('dependencies', vorbisidec_build)
	}

	// libmpg123
	if config.features.mp3_mpg123 {
		// mpg123_root := os.join_path(root, 'external', 'mpg123-1.25.6')
		lib.add_link_lib('mpg123', .dynamic, arch, [])!

		o_build.add_flag('-DMUSIC_MP3_MPG123', ['c', 'cpp'])!

		mpg123_build := libmpg123_node(config)!

		// Add lib's includes to SDL2_mixer's C -> .o build
		if mpg123_o_build := mpg123_build.find_nearest(id: 'mpg123', tags: ['o', 'build', '$arch']) {
			if includes := mpg123_o_build.items['includes'] {
				for include_node in includes {
					o_build.add_include(include_node.id, ['c', 'cpp'])!
				}
			}
		}

		lib.add('dependencies', mpg123_build)
	}

	// libmodplug
	if config.features.mod_modplug {
		lib.add_link_lib('modplug', .@static, arch, [])!

		flags := '-DMUSIC_MOD_MODPLUG -DMODPLUG_HEADER="<modplug.h>"'.split(' ')
		for flag in flags {
			o_build.add_flag(flag, ['c', 'cpp'])!
		}

		modplug_build := libmodplug_node(config)!

		// Add lib'sincludes to SDL2_mixer's C -> .o build
		if modplug_o_build := modplug_build.find_nearest(
			id: 'modplug'
			tags: ['o', 'build', '$arch']
		)
		{
			if includes := modplug_o_build.items['includes'] {
				for include_node in includes {
					o_build.add_include(include_node.id, ['c', 'cpp'])!
				}
			}
		}

		lib.add('dependencies', modplug_build)
	}

	// libtimidity / TiMidity
	if config.features.mid_timidity {
		lib.add_link_lib('timidity', .@static, arch, [])!

		o_build.add_flag('-DMUSIC_MID_TIMIDITY', ['c', 'cpp'])!

		timidity_build := libtimidity_node(config)!

		// Add lib'sincludes to SDL2_mixer's C -> .o build
		if lib_o_build := timidity_build.find_nearest(id: 'timidity', tags: ['o', 'build', '$arch']) {
			if includes := lib_o_build.items['includes'] {
				for include_node in includes {
					o_build.add_include(include_node.id, ['c', 'cpp'])!
				}
			}
		}

		lib.add('dependencies', timidity_build)
	}

	return &lib.Node
}

fn libflac_node(config SDL2MixerConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	flac_root := os.join_path(root, 'external', 'flac-1.3.2')
	lib_flac_root := os.join_path(flac_root, 'src', 'libFLAC')
	ogg_root := os.join_path(root, 'external', 'libogg-1.3.2')

	mut a_build := new_node('FLAC', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('FLAC', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	a_build.add('dependencies', &o_build.Node)

	includes := [
		os.join_path(flac_root, 'include'),
		os.join_path(lib_flac_root, 'include'),
		os.join_path(ogg_root, 'include'),
		os.join_path(ogg_root, 'android'),
	]

	for include in includes {
		o_build.add_include(include, ['c', 'cpp'])!
	}

	o_build.add_flag('-Wno-implicit-function-declaration', ['c', 'cpp'])!
	o_build.add_flag('-include "' + os.join_path(flac_root, 'android', 'config.h') + '"',
		['c', 'cpp'])!

	mut sources := []string{}
	sources << [
		os.join_path(lib_flac_root, 'bitmath.c'),
		os.join_path(lib_flac_root, 'bitreader.c'),
		os.join_path(lib_flac_root, 'bitwriter.c'),
		os.join_path(lib_flac_root, 'cpu.c'),
		os.join_path(lib_flac_root, 'crc.c'),
		os.join_path(lib_flac_root, 'fixed.c'),
		os.join_path(lib_flac_root, 'fixed_intrin_sse2.c'),
		os.join_path(lib_flac_root, 'fixed_intrin_ssse3.c'),
		os.join_path(lib_flac_root, 'float.c'),
		os.join_path(lib_flac_root, 'format.c'),
		os.join_path(lib_flac_root, 'lpc.c'),
		os.join_path(lib_flac_root, 'lpc_intrin_sse.c'),
		os.join_path(lib_flac_root, 'lpc_intrin_sse2.c'),
		os.join_path(lib_flac_root, 'lpc_intrin_sse41.c'),
		os.join_path(lib_flac_root, 'lpc_intrin_avx2.c'),
		os.join_path(lib_flac_root, 'md5.c'),
		os.join_path(lib_flac_root, 'memory.c'),
		os.join_path(lib_flac_root, 'metadata_iterators.c'),
		os.join_path(lib_flac_root, 'metadata_object.c'),
		os.join_path(lib_flac_root, 'stream_decoder.c'),
		os.join_path(lib_flac_root, 'stream_encoder.c'),
		os.join_path(lib_flac_root, 'stream_encoder_intrin_sse2.c'),
		os.join_path(lib_flac_root, 'stream_encoder_intrin_ssse3.c'),
		os.join_path(lib_flac_root, 'stream_encoder_intrin_avx2.c'),
		os.join_path(lib_flac_root, 'stream_encoder_framing.c'),
		os.join_path(lib_flac_root, 'window.c'),
		os.join_path(lib_flac_root, 'ogg_decoder_aspect.c'),
		os.join_path(lib_flac_root, 'ogg_encoder_aspect.c'),
		os.join_path(lib_flac_root, 'ogg_helper.c'),
		os.join_path(lib_flac_root, 'ogg_mapping.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c'])!
	}

	return &a_build.Node
}

fn libogg_node(config SDL2MixerConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	ogg_root := os.join_path(root, 'external', 'libogg-1.3.2')
	//	vorbis_root := os.join_path(root, 'external', 'libvorbis-1.3.5')

	mut a_build := new_node('ogg', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('ogg', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	a_build.add('dependencies', &o_build.Node)

	includes := [
		os.join_path(ogg_root, 'include'),
		os.join_path(ogg_root, 'android')
		//		os.join_path(vorbis_root,'include'),
	]

	for include in includes {
		o_build.add_include(include, ['c', 'cpp'])!
	}

	// o_build.add_flag('-Wno-implicit-function-declaration', ['c', 'cpp'])!
	// o_build.add_flag('-include "' + os.join_path(flac_root, 'android', 'config.h') + '"',
	// 	['c', 'cpp'])!

	mut sources := []string{}
	sources << [
		os.join_path(ogg_root, 'src/framing.c'),
		os.join_path(ogg_root, 'src/bitwise.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c'])!
	}

	return &a_build.Node
}

fn libvorbisidec_node(config SDL2MixerConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	ogg_root := os.join_path(root, 'external', 'libogg-1.3.2')
	vorbis_root := os.join_path(root, 'external', 'libvorbisidec-1.2.1')

	mut a_build := new_node('vorbisidec', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('vorbisidec', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	a_build.add('dependencies', &o_build.Node)

	o_build.add_flag('-Wno-duplicate-decl-specifier', ['c', 'cpp'])!
	// c_flags['libvorbisidec']['armeabi-v7a'] << '-D_ARM_ASSEM_' // "arm" only

	includes := [
		os.join_path(ogg_root, 'include'),
		os.join_path(ogg_root, 'android'),
		os.join_path(vorbis_root),
	]
	for include in includes {
		o_build.add_include(include, ['c', 'cpp'])!
	}

	mut sources := []string{}
	sources << [
		os.join_path(vorbis_root, 'block.c'),
		os.join_path(vorbis_root, 'synthesis.c'),
		os.join_path(vorbis_root, 'info.c'),
		os.join_path(vorbis_root, 'res012.c'),
		os.join_path(vorbis_root, 'mapping0.c'),
		os.join_path(vorbis_root, 'registry.c'),
		os.join_path(vorbis_root, 'codebook.c'),
	]
	sources << [
		os.join_path(ogg_root, 'src/framing.c'),
		os.join_path(ogg_root, 'src/bitwise.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c'])!
	}
	sources.clear()

	sources << [
		os.join_path(vorbis_root, 'mdct.c'),
		os.join_path(vorbis_root, 'window.c'),
		os.join_path(vorbis_root, 'floor1.c'),
		os.join_path(vorbis_root, 'floor0.c'),
		os.join_path(vorbis_root, 'vorbisfile.c'),
		os.join_path(vorbis_root, 'sharedbook.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c', 'arm'])!
	}
	sources.clear()

	return &a_build.Node
}

fn libmpg123_node(config SDL2MixerConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	mpg123_root := os.join_path(root, 'external', 'mpg123-1.25.6')
	libmpg123_src := os.join_path(mpg123_root, 'src', 'libmpg123')
	libmpg123_compat_src := os.join_path(mpg123_root, 'src', 'compat')

	mut so_build := new_node('mpg123', .build_dynamic_lib, arch, [])
	so_build.attach_data(abo: abo)

	mut o_build := new_node('mpg123', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	so_build.add('dependencies', &o_build.Node)

	// o_build.add_flag('-Wno-duplicate-decl-specifier',['c','cpp'])!

	includes := [
		os.join_path(mpg123_root, 'android'),
		os.join_path(mpg123_root, 'src'),
		os.join_path(mpg123_root, 'src/compat'),
		os.join_path(mpg123_root, 'src/libmpg123'),
	]

	for include in includes {
		o_build.add_include(include, ['c', 'cpp'])!
	}

	mut sources := []string{}
	mut flags := []string{}
	// neon
	if arch == 'armeabi-v7a' {
		flags << '-DOPT_NEON -DREAL_IS_FLOAT'.split(' ')
		sources << [
			os.join_path(libmpg123_src, 'stringbuf.c'),
			os.join_path(libmpg123_src, 'icy.c'),
			os.join_path(libmpg123_src, 'icy2utf8.c'),
			os.join_path(libmpg123_src, 'ntom.c'),
			os.join_path(libmpg123_src, 'synth.c'),
			os.join_path(libmpg123_src, 'synth_8bit.c'),
			os.join_path(libmpg123_src, 'layer1.c'),
			os.join_path(libmpg123_src, 'layer2.c'),
			os.join_path(libmpg123_src, 'layer3.c'),
			os.join_path(libmpg123_src, 'dct36_neon.S'),
			os.join_path(libmpg123_src, 'dct64_neon_float.S'),
			os.join_path(libmpg123_src, 'synth_neon_float.S'),
			os.join_path(libmpg123_src, 'synth_neon_s32.S'),
			os.join_path(libmpg123_src, 'synth_stereo_neon_float.S'),
			os.join_path(libmpg123_src, 'synth_stereo_neon_s32.S'),
			os.join_path(libmpg123_src, 'dct64_neon.S'),
			os.join_path(libmpg123_src, 'synth_neon.S'),
			os.join_path(libmpg123_src, 'synth_stereo_neon.S'),
			os.join_path(libmpg123_src, 'synth_s32.c'),
			os.join_path(libmpg123_src, 'synth_real.c'),
			os.join_path(libmpg123_src, 'feature.c'),
		]
	}
	// neon64
	if arch == 'arm64-v8a' {
		flags << '-DOPT_MULTI -DOPT_GENERIC -DOPT_GENERIC_DITHER -DOPT_NEON64 -DREAL_IS_FLOAT'.split(' ')
		sources << [
			os.join_path(libmpg123_src, 'stringbuf.c'),
			os.join_path(libmpg123_src, 'icy.c'),
			os.join_path(libmpg123_src, 'icy2utf8.c'),
			os.join_path(libmpg123_src, 'ntom.c'),
			os.join_path(libmpg123_src, 'synth.c'),
			os.join_path(libmpg123_src, 'synth_8bit.c'),
			os.join_path(libmpg123_src, 'layer1.c'),
			os.join_path(libmpg123_src, 'layer2.c'),
			os.join_path(libmpg123_src, 'layer3.c'),
			os.join_path(libmpg123_src, 'dct36_neon64.S'),
			os.join_path(libmpg123_src, 'dct64_neon64_float.S'),
			os.join_path(libmpg123_src, 'synth_neon64_float.S'),
			os.join_path(libmpg123_src, 'synth_neon64_s32.S'),
			os.join_path(libmpg123_src, 'synth_stereo_neon64_float.S'),
			os.join_path(libmpg123_src, 'synth_stereo_neon64_s32.S'),
			os.join_path(libmpg123_src, 'dct64_neon64.S'),
			os.join_path(libmpg123_src, 'synth_neon64.S'),
			os.join_path(libmpg123_src, 'synth_stereo_neon64.S'),
			os.join_path(libmpg123_src, 'synth_s32.c'),
			os.join_path(libmpg123_src, 'synth_real.c'),
			os.join_path(libmpg123_src, 'dither.c'),
			os.join_path(libmpg123_src, 'getcpuflags_arm.c'),
			os.join_path(libmpg123_src, 'check_neon.S'),
			os.join_path(libmpg123_src, 'feature.c'),
		]
	}
	// x86
	if arch == 'x86' {
		flags << '-DOPT_GENERIC -DREAL_IS_FLOAT'.split(' ')
		sources << [
			os.join_path(libmpg123_src, 'feature.c'),
			os.join_path(libmpg123_src, 'icy2utf8.c'),
			os.join_path(libmpg123_src, 'icy.c'),
			os.join_path(libmpg123_src, 'layer1.c'),
			os.join_path(libmpg123_src, 'layer2.c'),
			os.join_path(libmpg123_src, 'layer3.c'),
			os.join_path(libmpg123_src, 'ntom.c'),
			os.join_path(libmpg123_src, 'stringbuf.c'),
			os.join_path(libmpg123_src, 'synth_8bit.c'),
			os.join_path(libmpg123_src, 'synth.c'),
			os.join_path(libmpg123_src, 'synth_real.c'),
			os.join_path(libmpg123_src, 'synth_s32.c'),
			os.join_path(libmpg123_src, 'dither.c'),
		]
	}
	// x86_64
	if arch == 'x86_64' {
		flags << '-DOPT_MULTI -DOPT_X86_64 -DOPT_GENERIC -DOPT_GENERIC_DITHER -DREAL_IS_FLOAT -DOPT_AVX'.split(' ')
		sources << [
			os.join_path(libmpg123_src, 'stringbuf.c'),
			os.join_path(libmpg123_src, 'icy.c'),
			// os.join_path(libmpg123_src,'icy.h')
			os.join_path(libmpg123_src, 'icy2utf8.c'),
			// os.join_path(libmpg123_src,'icy2utf8.h')
			os.join_path(libmpg123_src, 'ntom.c'),
			os.join_path(libmpg123_src, 'synth.c'),
			// os.join_path(libmpg123_src,'synth.h')
			os.join_path(libmpg123_src, 'synth_8bit.c'),
			// os.join_path(libmpg123_src,'synth_8bit.h')
			os.join_path(libmpg123_src, 'layer1.c'),
			os.join_path(libmpg123_src, 'layer2.c'),
			os.join_path(libmpg123_src, 'layer3.c'),
			os.join_path(libmpg123_src, 'synth_s32.c'),
			os.join_path(libmpg123_src, 'synth_real.c'),
			os.join_path(libmpg123_src, 'dct36_x86_64.S'),
			os.join_path(libmpg123_src, 'dct64_x86_64_float.S'),
			os.join_path(libmpg123_src, 'synth_x86_64_float.S'),
			os.join_path(libmpg123_src, 'synth_x86_64_s32.S'),
			os.join_path(libmpg123_src, 'synth_stereo_x86_64_float.S'),
			os.join_path(libmpg123_src, 'synth_stereo_x86_64_s32.S'),
			os.join_path(libmpg123_src, 'synth_x86_64.S'),
			os.join_path(libmpg123_src, 'dct64_x86_64.S'),
			os.join_path(libmpg123_src, 'synth_stereo_x86_64.S'),
			os.join_path(libmpg123_src, 'dither.c'),
			// os.join_path(libmpg123_src,'dither.h')
			os.join_path(libmpg123_src, 'getcpuflags_x86_64.S'),
			os.join_path(libmpg123_src, 'dct36_avx.S'),
			os.join_path(libmpg123_src, 'dct64_avx_float.S'),
			os.join_path(libmpg123_src, 'synth_stereo_avx_float.S'),
			os.join_path(libmpg123_src, 'synth_stereo_avx_s32.S'),
			os.join_path(libmpg123_src, 'dct64_avx.S'),
			os.join_path(libmpg123_src, 'synth_stereo_avx.S'),
			os.join_path(libmpg123_src, 'feature.c'),
		]
	}
	for flag in flags {
		o_build.add_flag(flag, ['c', 'cpp'])!
	}

	for source in sources {
		o_build.add_source(source, ['c'])!
	}
	sources.clear()

	sources << [
		os.join_path(libmpg123_src, 'parse.c'),
		os.join_path(libmpg123_src, 'frame.c'),
		os.join_path(libmpg123_src, 'format.c'),
		os.join_path(libmpg123_src, 'dct64.c'),
		os.join_path(libmpg123_src, 'equalizer.c'),
		os.join_path(libmpg123_src, 'id3.c'),
		os.join_path(libmpg123_src, 'optimize.c'),
		os.join_path(libmpg123_src, 'readers.c'),
		os.join_path(libmpg123_src, 'tabinit.c'),
		os.join_path(libmpg123_src, 'libmpg123.c'),
		os.join_path(libmpg123_src, 'index.c'),
		os.join_path(libmpg123_compat_src, 'compat_str.c'),
		os.join_path(libmpg123_compat_src, 'compat.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c'])!
	}
	sources.clear()

	return &so_build.Node
}

fn libmodplug_node(config SDL2MixerConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	modplug_root := os.join_path(root, 'external', 'libmodplug-0.8.9.0')

	mut a_build := new_node('modplug', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('modplug', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	a_build.add('dependencies', &o_build.Node)

	includes := [
		os.join_path(modplug_root, 'src'),
		os.join_path(modplug_root, 'src', 'libmodplug'),
	]

	for include in includes {
		o_build.add_include(include, ['c', 'cpp'])!
	}

	mut sources := []string{}
	mut flags := []string{}

	sources << [
		os.join_path(modplug_root, 'src/fastmix.cpp'),
		os.join_path(modplug_root, 'src/load_669.cpp'),
		os.join_path(modplug_root, 'src/load_abc.cpp'),
		os.join_path(modplug_root, 'src/load_amf.cpp'),
		os.join_path(modplug_root, 'src/load_ams.cpp'),
		os.join_path(modplug_root, 'src/load_dbm.cpp'),
		os.join_path(modplug_root, 'src/load_dmf.cpp'),
		os.join_path(modplug_root, 'src/load_dsm.cpp'),
		os.join_path(modplug_root, 'src/load_far.cpp'),
		os.join_path(modplug_root, 'src/load_it.cpp'),
		os.join_path(modplug_root, 'src/load_j2b.cpp'),
		os.join_path(modplug_root, 'src/load_mdl.cpp'),
		os.join_path(modplug_root, 'src/load_med.cpp'),
		os.join_path(modplug_root, 'src/load_mid.cpp'),
		os.join_path(modplug_root, 'src/load_mod.cpp'),
		os.join_path(modplug_root, 'src/load_mt2.cpp'),
		os.join_path(modplug_root, 'src/load_mtm.cpp'),
		os.join_path(modplug_root, 'src/load_okt.cpp'),
		os.join_path(modplug_root, 'src/load_pat.cpp'),
		os.join_path(modplug_root, 'src/load_psm.cpp'),
		os.join_path(modplug_root, 'src/load_ptm.cpp'),
		os.join_path(modplug_root, 'src/load_s3m.cpp'),
		os.join_path(modplug_root, 'src/load_stm.cpp'),
		os.join_path(modplug_root, 'src/load_ult.cpp'),
		os.join_path(modplug_root, 'src/load_umx.cpp'),
		os.join_path(modplug_root, 'src/load_wav.cpp'),
		os.join_path(modplug_root, 'src/load_xm.cpp'),
		os.join_path(modplug_root, 'src/mmcmp.cpp'),
		os.join_path(modplug_root, 'src/modplug.cpp'),
		os.join_path(modplug_root, 'src/snd_dsp.cpp'),
		os.join_path(modplug_root, 'src/snd_flt.cpp'),
		os.join_path(modplug_root, 'src/snd_fx.cpp'),
		os.join_path(modplug_root, 'src/sndfile.cpp'),
		os.join_path(modplug_root, 'src/sndmix.cpp'),
	]
	for source in sources {
		o_build.add_source(source, ['cpp'])!
	}
	sources.clear()

	flags << '-Wno-deprecated-register -Wunused-function'.split(' ') // For at least v2.0.4
	flags << '-DHAVE_SETENV -DHAVE_SINF'.split(' ')

	for flag in flags {
		o_build.add_flag(flag, ['c', 'cpp'])!
	}

	return &a_build.Node
}

fn libtimidity_node(config SDL2MixerConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	timidity_root := os.join_path(root, 'timidity')

	mut a_build := new_node('timidity', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('timidity', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	a_build.add('dependencies', &o_build.Node)

	o_build.add_include(timidity_root, ['c', 'cpp'])!

	mut sources := []string{}

	sources << [
		os.join_path(timidity_root, 'common.c'),
		os.join_path(timidity_root, 'instrum.c'),
		os.join_path(timidity_root, 'mix.c'),
		os.join_path(timidity_root, 'output.c'),
		os.join_path(timidity_root, 'playmidi.c'),
		os.join_path(timidity_root, 'readmidi.c'),
		os.join_path(timidity_root, 'resample.c'),
		os.join_path(timidity_root, 'tables.c'),
		os.join_path(timidity_root, 'timidity.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c'])!
	}
	sources.clear()

	return &a_build.Node
}
