module main

import os

struct SDL2ImageFeatures {
	bmp bool = true
	gif bool = true
	lbm bool = true
	pcx bool = true
	pnm bool = true
	svg bool = true
	tga bool = true
	xcf bool = true
	xpm bool = true
	xv  bool = true
	// External deps
	jpg  bool = true // if you want to support loading JPEG images
	png  bool = true // if you want to support loading PNG images
	webp bool = true // if you want to support loading WebP images
}

struct SDL2ImageConfig {
	features SDL2ImageFeatures
	abo      AndroidBuildOptions
	root     string
}

fn libsdl2_image_node(config SDL2ImageConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch
	// version := abo.version

	mut lib := new_node('SDL2_image', .build_dynamic_lib, arch, ['cpp'])
	if arch == 'armeabi-v7a' {
		lib.Node.tags << 'use-v7a-as-armeabi'
	}
	lib.attach_data(abo: abo)
	lib.add_link_lib('SDL2', .dynamic, arch, [])!

	lib.add_export('include', root, ['c', 'cpp'])!

	mut o_build := new_node('SDL2_image', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add_include(root, ['c', 'cpp'])!

	mut sources := []string{}

	sources << [
		os.join_path(root, 'IMG.c'),
		os.join_path(root, 'IMG_bmp.c'),
		os.join_path(root, 'IMG_gif.c'),
		os.join_path(root, 'IMG_jpg.c'),
		os.join_path(root, 'IMG_lbm.c'),
		os.join_path(root, 'IMG_pcx.c'),
		os.join_path(root, 'IMG_png.c'),
		os.join_path(root, 'IMG_pnm.c'),
		os.join_path(root, 'IMG_svg.c'),
		os.join_path(root, 'IMG_tga.c'),
		os.join_path(root, 'IMG_tif.c'),
		os.join_path(root, 'IMG_webp.c'),
		os.join_path(root, 'IMG_WIC.c'),
		os.join_path(root, 'IMG_xcf.c'),
		os.join_path(root, 'IMG_xv.c'),
		os.join_path(root, 'IMG_xxx.c'),
	]

	for source in sources {
		o_build.add_source(source, ['c'])!
	}
	o_build.add_source(os.join_path(root, 'IMG_xpm.c'), ['c', 'arm'])!

	mut flags := '-Wno-unused-variable -Wno-unused-function'.split(' ')
	for flag in flags {
		// o_build.add('flags', as_heap(id: flag, note: 'build flag', tags: ['c', 'cpp', 'flag','warning']))
		o_build.add_flag(flag, ['c', 'cpp'])!
	}
	flags.clear()

	if config.features.bmp {
		flags << '-DLOAD_BMP'
	}
	if config.features.gif {
		flags << '-DLOAD_GIF'
	}
	if config.features.lbm {
		flags << '-DLOAD_LBM'
	}
	if config.features.pcx {
		flags << '-DLOAD_PCX'
	}
	if config.features.pnm {
		flags << '-DLOAD_PNM'
	}
	if config.features.svg {
		flags << '-DLOAD_SVG'
	}
	if config.features.tga {
		flags << '-DLOAD_TGA'
	}
	if config.features.xcf {
		flags << '-DLOAD_XCF'
	}
	if config.features.xpm {
		flags << '-DLOAD_XPM'
	}
	if config.features.xv {
		flags << '-DLOAD_XV'
	}

	for flag in flags {
		// o_build.add('flags', as_heap(id: flag, note: 'build flag', tags: ['c', 'cpp', 'flag',	'define']))
		o_build.add_flag(flag, ['c', 'cpp'])!
	}

	lib.add('dependencies', o_build.Node)

	// libpng
	if config.features.png {
		png_root := os.join_path(root, 'external', 'libpng-1.6.37')
		lib.add_link_lib('png', .@static, arch, [])!

		o_build.add_flag('-DLOAD_PNG', ['c', 'cpp'])!
		o_build.add_include(png_root, ['c', 'cpp'])!
		lib.add_flag('-lz', []string{})!

		png_build := libpng_node(config)!

		lib.add('dependencies', png_build)
	}

	if config.features.jpg {
		jpg_root := os.join_path(root, 'external', 'jpeg-9b')

		lib.add_link_lib('jpeg', .@static, arch, [])!

		o_build.add_flag('-DLOAD_JPG', ['c', 'cpp'])!
		o_build.add_include(jpg_root, ['c', 'cpp'])!

		jpg_build := libjpeg_node(config)!

		lib.add('dependencies', jpg_build)
	}

	if config.features.webp {
		webp_root := os.join_path(root, 'external', 'libwebp-1.0.2')
		webp_src := os.join_path(webp_root, 'src')

		lib.add_link_lib('webpdecoder', .@static, arch, [])!
		lib.add_link_lib('webp', .@static, arch, [])!
		lib.add_link_lib('webpdemux', .@static, arch, [])!
		lib.add_link_lib('webpmux', .@static, arch, [])!
		lib.add_link_lib('imageio_util', .@static, arch, [])!
		lib.add_link_lib('imagedec', .@static, arch, [])!
		lib.add_link_lib('imageenc', .@static, arch, [])!
		o_build.add_flag('-DLOAD_WEBP', ['c', 'cpp'])!
		o_build.add_include(webp_src, ['c', 'cpp'])!

		webp_build := libwebp_node(config)!

		lib.add('dependencies', webp_build)
	}

	return &lib.Node
}

fn libpng_node(config SDL2ImageConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	png_root := os.join_path(root, 'external', 'libpng-1.6.37')

	mut a_build := new_node('png', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('png', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add_include(png_root, ['c'])!

	mut sources := []string{}
	sources << [
		os.join_path(png_root, 'png.c'),
		os.join_path(png_root, 'pngerror.c'),
		os.join_path(png_root, 'pngget.c'),
		os.join_path(png_root, 'pngmem.c'),
		os.join_path(png_root, 'pngpread.c'),
		os.join_path(png_root, 'pngread.c'),
		os.join_path(png_root, 'pngrio.c'),
		os.join_path(png_root, 'pngrtran.c'),
		os.join_path(png_root, 'pngrutil.c'),
		os.join_path(png_root, 'pngset.c'),
		os.join_path(png_root, 'pngtrans.c'),
		os.join_path(png_root, 'pngwio.c'),
		os.join_path(png_root, 'pngwrite.c'),
		os.join_path(png_root, 'pngwtran.c'),
		os.join_path(png_root, 'pngwutil.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c'])!
	}

	// neon
	if arch == 'armeabi-v7a' {
		sources.clear()
		sources << [
			os.join_path(png_root, 'arm', 'arm_init.c'),
			os.join_path(png_root, 'arm', 'filter_neon.S'),
			os.join_path(png_root, 'arm', 'filter_neon_intrinsics.c'),
			os.join_path(png_root, 'arm', 'palette_neon_intrinsics.c'),
		]
		for source in sources {
			o_build.add_source(source, ['c', 'arm'])!
		}
	}
	// neon64
	if arch == 'arm64-v8a' {
		sources.clear()
		sources << [
			os.join_path(png_root, 'arm', 'arm_init.c'),
			os.join_path(png_root, 'arm', 'filter_neon.S'),
			os.join_path(png_root, 'arm', 'filter_neon_intrinsics.c'),
			os.join_path(png_root, 'arm', 'palette_neon_intrinsics.c'),
		]
		for source in sources {
			o_build.add_source(source, ['c', 'arm'])!
		}
	}

	a_build.add('dependencies', &o_build.Node)
	return &a_build.Node
}

fn libjpeg_node(config SDL2ImageConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	jpg_root := os.join_path(root, 'external', 'jpeg-9b')

	mut a_build := AndroidNode{
		id: 'jpeg'
		Node: &Node{
			id: 'jpeg'
			note: 'libjpeg .o to .a for $arch'
			tags: ['lib', 'static', '$arch']
		}
	}
	a_build.attach_data(abo: abo)

	mut o_build := &AndroidNode{
		id: 'jpeg'
		Node: &Node{
			id: 'jpeg'
			note: 'libjpeg .c to .o for $arch'
			tags: ['o', 'build', '$arch']
		}
	}
	o_build.attach_data(abo: abo)

	o_build.add_include(jpg_root, ['c'])!

	mut sources := []string{}
	sources << [
		os.join_path(jpg_root, 'jaricom.c'),
		os.join_path(jpg_root, 'jcapimin.c'),
		os.join_path(jpg_root, 'jcapistd.c'),
		os.join_path(jpg_root, 'jcarith.c'),
		os.join_path(jpg_root, 'jccoefct.c'),
		os.join_path(jpg_root, 'jccolor.c'),
		os.join_path(jpg_root, 'jcdctmgr.c'),
		os.join_path(jpg_root, 'jchuff.c'),
		os.join_path(jpg_root, 'jcinit.c'),
		os.join_path(jpg_root, 'jcmainct.c'),
		os.join_path(jpg_root, 'jcmarker.c'),
		os.join_path(jpg_root, 'jcmaster.c'),
		os.join_path(jpg_root, 'jcomapi.c'),
		os.join_path(jpg_root, 'jcparam.c'),
		os.join_path(jpg_root, 'jcprepct.c'),
		os.join_path(jpg_root, 'jcsample.c'),
		os.join_path(jpg_root, 'jctrans.c'),
		os.join_path(jpg_root, 'jdapimin.c'),
		os.join_path(jpg_root, 'jdapistd.c'),
		os.join_path(jpg_root, 'jdarith.c'),
		os.join_path(jpg_root, 'jdatadst.c'),
		os.join_path(jpg_root, 'jdatasrc.c'),
		os.join_path(jpg_root, 'jdcoefct.c'),
		os.join_path(jpg_root, 'jdcolor.c'),
		os.join_path(jpg_root, 'jddctmgr.c'),
		os.join_path(jpg_root, 'jdhuff.c'),
		os.join_path(jpg_root, 'jdinput.c'),
		os.join_path(jpg_root, 'jdmainct.c'),
		os.join_path(jpg_root, 'jdmarker.c'),
		os.join_path(jpg_root, 'jdmaster.c'),
		os.join_path(jpg_root, 'jdmerge.c'),
		os.join_path(jpg_root, 'jdpostct.c'),
		os.join_path(jpg_root, 'jdsample.c'),
		os.join_path(jpg_root, 'jdtrans.c'),
		os.join_path(jpg_root, 'jerror.c'),
		os.join_path(jpg_root, 'jfdctflt.c'),
		os.join_path(jpg_root, 'jfdctfst.c'),
		os.join_path(jpg_root, 'jfdctint.c'),
		os.join_path(jpg_root, 'jidctflt.c'),
		os.join_path(jpg_root, 'jquant1.c'),
		os.join_path(jpg_root, 'jquant2.c'),
		os.join_path(jpg_root, 'jutils.c'),
		os.join_path(jpg_root, 'jmemmgr.c'),
		os.join_path(jpg_root, 'jmem-android.c'),
	]

	sources << [
		os.join_path(jpg_root, 'jidctint.c'),
		os.join_path(jpg_root, 'jidctfst.c'), // TEMP FIX jidctfst.S SDL BUG see Android.mk
	]

	for source in sources {
		o_build.add_source(source, ['c', 'arm'])!
	}

	flags := ['-DAVOID_TABLES', '-O3', '-fstrict-aliasing', '-fprefetch-loop-arrays']
	for flag in flags {
		o_build.add_flag(flag, ['c', 'cpp'])!
	}

	a_build.add('dependencies', &o_build.Node)
	return &a_build.Node
}

fn libwebp_node(config SDL2ImageConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	webp_root := os.join_path(root, 'external', 'libwebp-1.0.2')
	webp_src := os.join_path(webp_root, 'src')

	mut tasks := &Node{
		id: 'build-all-of-libwebp'
		note: 'build all of libwebp'
		tags: ['container']
	}

	mut decoder_a_build := new_node('webpdecoder', .build_static_lib, arch, [])
	decoder_a_build.attach_data(abo: abo)

	mut decoder_o_build := new_node('webpdecoder', .build_src_to_o, arch, [])
	decoder_o_build.attach_data(abo: abo)
	decoder_a_build.add('dependencies', &decoder_o_build.Node)

	tasks.add('tasks', &decoder_a_build.Node)

	mut a_build := new_node('webp', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('webp', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	a_build.add('dependencies', &o_build.Node)

	tasks.add('tasks', &a_build.Node)

	mut neon := 'c'

	/*
	TODO
	if arch == 'armeabi-v7a' {
		neon = 'c.neon'

		// cpu-features
		cpu_features_root := os.join_path(ndk.root_version(abo.ndk_version), 'sources',	'android', 'cpufeatures')

		decoder_a_build.add('libs', as_heap(id: 'cpufeatures', tags: ['static', '$arch']))

		decoder_o_build.add_flag('-DHAVE_CPU_FEATURES_H',['c','cpp'])
		decoder_o_build.add_include(cpu_features_root, [			'c',			'cpp',		])

		cpuf_build := libcpufeatures_node(cpu_features_root, abo)!

		a_build.add('dependencies', cpuf_build)

	}
	*/

	dec_srcs := [
		os.join_path(webp_src, 'dec', 'alpha_dec.c'),
		os.join_path(webp_src, 'dec', 'buffer_dec.c'),
		os.join_path(webp_src, 'dec', 'frame_dec.c'),
		os.join_path(webp_src, 'dec', 'idec_dec.c'),
		os.join_path(webp_src, 'dec', 'io_dec.c'),
		os.join_path(webp_src, 'dec', 'quant_dec.c'),
		os.join_path(webp_src, 'dec', 'tree_dec.c'),
		os.join_path(webp_src, 'dec', 'vp8_dec.c'),
		os.join_path(webp_src, 'dec', 'vp8l_dec.c'),
		os.join_path(webp_src, 'dec', 'webp_dec.c'),
	]

	demux_srcs := [
		os.join_path(webp_src, 'demux', 'anim_decode.c'),
		os.join_path(webp_src, 'demux', 'demux.c'),
	]

	dsp_dec_srcs := [
		os.join_path(webp_src, 'dsp', 'alpha_processing.c'),
		os.join_path(webp_src, 'dsp', 'alpha_processing_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'alpha_processing_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'alpha_processing_sse2.c'),
		os.join_path(webp_src, 'dsp', 'alpha_processing_sse41.c'),
		os.join_path(webp_src, 'dsp', 'cpu.c'),
		os.join_path(webp_src, 'dsp', 'dec.c'),
		os.join_path(webp_src, 'dsp', 'dec_clip_tables.c'),
		os.join_path(webp_src, 'dsp', 'dec_mips32.c'),
		os.join_path(webp_src, 'dsp', 'dec_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'dec_msa.c'),
		os.join_path(webp_src, 'dsp', 'dec_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'dec_sse2.c'),
		os.join_path(webp_src, 'dsp', 'dec_sse41.c'),
		os.join_path(webp_src, 'dsp', 'filters.c'),
		os.join_path(webp_src, 'dsp', 'filters_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'filters_msa.c'),
		os.join_path(webp_src, 'dsp', 'filters_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'filters_sse2.c'),
		os.join_path(webp_src, 'dsp', 'lossless.c'),
		os.join_path(webp_src, 'dsp', 'lossless_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'lossless_msa.c'),
		os.join_path(webp_src, 'dsp', 'lossless_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'lossless_sse2.c'),
		os.join_path(webp_src, 'dsp', 'rescaler.c'),
		os.join_path(webp_src, 'dsp', 'rescaler_mips32.c'),
		os.join_path(webp_src, 'dsp', 'rescaler_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'rescaler_msa.c'),
		os.join_path(webp_src, 'dsp', 'rescaler_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'rescaler_sse2.c'),
		os.join_path(webp_src, 'dsp', 'upsampling.c'),
		os.join_path(webp_src, 'dsp', 'upsampling_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'upsampling_msa.c'),
		os.join_path(webp_src, 'dsp', 'upsampling_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'upsampling_sse2.c'),
		os.join_path(webp_src, 'dsp', 'upsampling_sse41.c'),
		os.join_path(webp_src, 'dsp', 'yuv.c'),
		os.join_path(webp_src, 'dsp', 'yuv_mips32.c'),
		os.join_path(webp_src, 'dsp', 'yuv_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'yuv_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'yuv_sse2.c'),
		os.join_path(webp_src, 'dsp', 'yuv_sse41.c'),
	]

	dsp_enc_srcs := [
		os.join_path(webp_src, 'dsp', 'cost.c'),
		os.join_path(webp_src, 'dsp', 'cost_mips32.c'),
		os.join_path(webp_src, 'dsp', 'cost_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'cost_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'cost_sse2.c'),
		os.join_path(webp_src, 'dsp', 'enc.c'),
		os.join_path(webp_src, 'dsp', 'enc_mips32.c'),
		os.join_path(webp_src, 'dsp', 'enc_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'enc_msa.c'),
		os.join_path(webp_src, 'dsp', 'enc_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'enc_sse2.c'),
		os.join_path(webp_src, 'dsp', 'enc_sse41.c'),
		os.join_path(webp_src, 'dsp', 'lossless_enc.c'),
		os.join_path(webp_src, 'dsp', 'lossless_enc_mips32.c'),
		os.join_path(webp_src, 'dsp', 'lossless_enc_mips_dsp_r2.c'),
		os.join_path(webp_src, 'dsp', 'lossless_enc_msa.c'),
		os.join_path(webp_src, 'dsp', 'lossless_enc_neon.$neon'),
		os.join_path(webp_src, 'dsp', 'lossless_enc_sse2.c'),
		os.join_path(webp_src, 'dsp', 'lossless_enc_sse41.c'),
		os.join_path(webp_src, 'dsp', 'ssim.c'),
		os.join_path(webp_src, 'dsp', 'ssim_sse2.c'),
	]

	enc_srcs := [
		os.join_path(webp_src, 'enc', 'alpha_enc.c'),
		os.join_path(webp_src, 'enc', 'analysis_enc.c'),
		os.join_path(webp_src, 'enc', 'backward_references_cost_enc.c'),
		os.join_path(webp_src, 'enc', 'backward_references_enc.c'),
		os.join_path(webp_src, 'enc', 'config_enc.c'),
		os.join_path(webp_src, 'enc', 'cost_enc.c'),
		os.join_path(webp_src, 'enc', 'filter_enc.c'),
		os.join_path(webp_src, 'enc', 'frame_enc.c'),
		os.join_path(webp_src, 'enc', 'histogram_enc.c'),
		os.join_path(webp_src, 'enc', 'iterator_enc.c'),
		os.join_path(webp_src, 'enc', 'near_lossless_enc.c'),
		os.join_path(webp_src, 'enc', 'picture_enc.c'),
		os.join_path(webp_src, 'enc', 'picture_csp_enc.c'),
		os.join_path(webp_src, 'enc', 'picture_psnr_enc.c'),
		os.join_path(webp_src, 'enc', 'picture_rescale_enc.c'),
		os.join_path(webp_src, 'enc', 'picture_tools_enc.c'),
		os.join_path(webp_src, 'enc', 'predictor_enc.c'),
		os.join_path(webp_src, 'enc', 'quant_enc.c'),
		os.join_path(webp_src, 'enc', 'syntax_enc.c'),
		os.join_path(webp_src, 'enc', 'token_enc.c'),
		os.join_path(webp_src, 'enc', 'tree_enc.c'),
		os.join_path(webp_src, 'enc', 'vp8l_enc.c'),
		os.join_path(webp_src, 'enc', 'webp_enc.c'),
	]

	mux_srcs := [
		os.join_path(webp_src, 'mux', 'anim_encode.c'),
		os.join_path(webp_src, 'mux', 'muxedit.c'),
		os.join_path(webp_src, 'mux', 'muxinternal.c'),
		os.join_path(webp_src, 'mux', 'muxread.c'),
	]

	utils_dec_srcs := [
		os.join_path(webp_src, 'utils', 'bit_reader_utils.c'),
		os.join_path(webp_src, 'utils', 'color_cache_utils.c'),
		os.join_path(webp_src, 'utils', 'filters_utils.c'),
		os.join_path(webp_src, 'utils', 'huffman_utils.c'),
		os.join_path(webp_src, 'utils', 'quant_levels_dec_utils.c'),
		os.join_path(webp_src, 'utils', 'random_utils.c'),
		os.join_path(webp_src, 'utils', 'rescaler_utils.c'),
		os.join_path(webp_src, 'utils', 'thread_utils.c'),
		os.join_path(webp_src, 'utils', 'utils.c'),
	]

	utils_enc_srcs := [
		os.join_path(webp_src, 'utils', 'bit_writer_utils.c'),
		os.join_path(webp_src, 'utils', 'huffman_encode_utils.c'),
		os.join_path(webp_src, 'utils', 'quant_levels_utils.c'),
	]

	mut webp_c_flags := '-Wall -DANDROID -DHAVE_MALLOC_H -DHAVE_PTHREAD -DWEBP_USE_THREAD'.split(' ')
	webp_c_flags << '-fvisibility=hidden'
	if abo.is_prod {
		webp_c_flags << '-finline-functions -ffast-math -ffunction-sections -fdata-sections'.split(' ')
	}
	// if clang .. // NOTE Default is clang in all supprted NDKs
	webp_c_flags << '-frename-registers -s'.split(' ')

	mut sources := []string{}

	// libwebp / libwebpdecoder
	decoder_o_build.add_include(webp_root, ['c'])!

	sources << dec_srcs
	sources << dsp_dec_srcs
	sources << utils_dec_srcs
	for source in sources {
		decoder_o_build.add_source(source, ['c', 'arm'])!
	}
	sources.clear()
	for flag in webp_c_flags {
		decoder_o_build.add_flag(flag, ['c', 'cpp'])!
	}

	// libwebp / libwebp
	o_build.add_include(webp_root, ['c'])!

	sources << dsp_enc_srcs
	sources << enc_srcs
	sources << utils_enc_srcs
	for source in sources {
		o_build.add_source(source, ['c', 'arm'])!
	}
	sources.clear()
	for flag in webp_c_flags {
		o_build.add_flag(flag, ['c', 'cpp'])!
	}

	// libwebp / libwebpdemux
	mut demux_a_build := new_node('webpdemux', .build_static_lib, arch, [])
	demux_a_build.attach_data(abo: abo)
	mut demux_o_build := new_node('webpdemux', .build_src_to_o, arch, [])
	demux_o_build.attach_data(abo: abo)

	demux_a_build.add('dependencies', &demux_o_build.Node)
	tasks.add('tasks', &demux_a_build.Node)

	demux_o_build.add_include(webp_root, ['c'])!
	sources << demux_srcs
	for source in sources {
		demux_o_build.add_source(source, ['c', 'arm'])!
	}
	sources.clear()
	for flag in webp_c_flags {
		demux_o_build.add_flag(flag, ['c', 'cpp'])!
	}

	// libwebp / libwebpmux
	mut mux_a_build := new_node('webpmux', .build_static_lib, arch, [])
	mux_a_build.attach_data(abo: abo)
	mut mux_o_build := new_node('webpmux', .build_src_to_o, arch, [])
	mux_o_build.attach_data(abo: abo)

	mux_a_build.add('dependencies', &mux_o_build.Node)
	tasks.add('tasks', &mux_a_build.Node)

	mux_o_build.add_include(webp_root, ['c'])!
	sources << mux_srcs
	for source in sources {
		mux_o_build.add_source(source, ['c', 'arm'])!
	}
	sources.clear()
	for flag in webp_c_flags {
		mux_o_build.add_flag(flag, ['c', 'cpp'])!
	}

	imageio_root := os.join_path(webp_root, 'imageio')
	// imageio / libimageio_util
	mut imageio_util_a_build := new_node('imageio_util', .build_static_lib, arch, [])
	imageio_util_a_build.attach_data(abo: abo)
	mut imageio_util_o_build := new_node('imageio_util', .build_src_to_o, arch, [])
	imageio_util_o_build.attach_data(abo: abo)
	imageio_util_a_build.add('dependencies', &imageio_util_o_build.Node)
	tasks.add('tasks', &imageio_util_a_build.Node)

	imageio_util_o_build.add_include(webp_src, ['c'])!
	sources << os.join_path(imageio_root, 'imageio_util.c')
	for source in sources {
		imageio_util_o_build.add_source(source, ['c'])!
	}
	sources.clear()
	for flag in webp_c_flags {
		imageio_util_o_build.add_flag(flag, ['c', 'cpp'])!
	}

	// imageio / libimagedec
	mut imagedec_a_build := new_node('imagedec', .build_static_lib, arch, [])
	imagedec_a_build.attach_data(abo: abo)
	mut imagedec_o_build := new_node('imagedec', .build_src_to_o, arch, [])
	imagedec_o_build.attach_data(abo: abo)
	imagedec_a_build.add('dependencies', &imagedec_o_build.Node)
	tasks.add('tasks', &imagedec_a_build.Node)

	imagedec_o_build.add_include(webp_src, ['c'])!
	sources << [
		os.join_path(imageio_root, 'image_dec.c'),
		os.join_path(imageio_root, 'jpegdec.c'),
		os.join_path(imageio_root, 'metadata.c'),
		os.join_path(imageio_root, 'pngdec.c'),
		os.join_path(imageio_root, 'pnmdec.c'),
		os.join_path(imageio_root, 'tiffdec.c'),
		os.join_path(imageio_root, 'webpdec.c'),
	]
	for source in sources {
		imagedec_o_build.add_source(source, ['c'])!
	}
	sources.clear()
	for flag in webp_c_flags {
		imagedec_o_build.add_flag(flag, ['c', 'cpp'])!
	}

	// imageio / libimageenc
	mut imageenc_a_build := new_node('imageenc', .build_static_lib, arch, [])
	imageenc_a_build.attach_data(abo: abo)
	mut imageenc_o_build := new_node('imageenc', .build_src_to_o, arch, [])
	imageenc_o_build.attach_data(abo: abo)
	imageenc_a_build.add('dependencies', &imageenc_o_build.Node)
	tasks.add('tasks', &imageenc_a_build.Node)

	imageenc_o_build.add_include(webp_src, ['c'])!
	sources << [
		os.join_path(imageio_root, 'image_enc.c'),
	]
	for source in sources {
		imageenc_o_build.add_source(source, ['c'])!
	}
	sources.clear()
	for flag in webp_c_flags {
		imageenc_o_build.add_flag(flag, ['c', 'cpp'])!
	}

	return tasks
}
