module main

import os

struct SDL2TTFFeatures {
}

struct SDL2TTFConfig {
	features SDL2TTFFeatures
	abo      AndroidBuildOptions
	root     string
}

fn libsdl2_ttf_node(config SDL2TTFConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch
	// version := abo.version

	mut lib := new_node('SDL2_ttf', .build_dynamic_lib, arch, ['cpp'])
	if arch == 'armeabi-v7a' {
		lib.Node.tags << 'use-v7a-as-armeabi'
	}
	lib.attach_data(abo: abo)
	lib.add_link_lib('SDL2', .dynamic, arch, [])!

	lib.add_export('include', root, ['c', 'cpp'])!

	mut o_build := new_node('SDL2_ttf', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add_include(root, ['c', 'cpp'])!

	mut sources := []string{}

	sources << [
		os.join_path(root, 'SDL_ttf.c'),
	]

	for source in sources {
		o_build.add_source(source, ['c'])!
	}

	// mut flags := '-Wno-unused-variable -Wno-unused-function'.split(' ')
	// for flag in flags {
	// 	// o_build.add('flags', as_heap(id: flag, note: 'build flag', tags: ['c', 'cpp', 'flag','warning']))
	// 	o_build.add_flag(flag, ['c', 'cpp'])!
	// }
	// flags.clear()

	lib.add('dependencies', o_build.Node)

	// libfreetype
	freetype_root := os.join_path(root, 'external', 'freetype-2.9.1')

	lib.add_link_lib('freetype', .@static, arch, [])!
	o_build.add_include(os.join_path(freetype_root,'include'), ['c', 'cpp'])!

	freetype_build := libfreetype_node(config)!

	lib.add('dependencies', freetype_build)

	return &lib.Node
}

fn libfreetype_node(config SDL2TTFConfig) !&Node {
	abo := config.abo
	root := config.root
	arch := abo.arch

	freetype_root := os.join_path(root, 'external', 'freetype-2.9.1')
	freetype_src := os.join_path(freetype_root, 'src')

	mut a_build := new_node('freetype', .build_static_lib, arch, [])
	a_build.attach_data(abo: abo)

	mut o_build := new_node('freetype', .build_src_to_o, arch, [])
	o_build.attach_data(abo: abo)

	o_build.add_include(os.join_path(freetype_root, 'include'), ['c'])!

	flags := '-DFT2_BUILD_LIBRARY -Os'.split(' ')
	for flag in flags {
		o_build.add_flag(flag, ['c', 'cpp'])!
	}

	mut sources := []string{}
	sources << [
			os.join_path(freetype_src, 'autofit', 'autofit.c'),
			os.join_path(freetype_src, 'base', 'ftbase.c'),
			os.join_path(freetype_src, 'base', 'ftbbox.c'),
			os.join_path(freetype_src, 'base', 'ftbdf.c'),
			os.join_path(freetype_src, 'base', 'ftbitmap.c'),
			os.join_path(freetype_src, 'base', 'ftcid.c'),
			os.join_path(freetype_src, 'base', 'ftdebug.c'),
			os.join_path(freetype_src, 'base', 'ftfstype.c'),
			os.join_path(freetype_src, 'base', 'ftgasp.c'),
			os.join_path(freetype_src, 'base', 'ftglyph.c'),
			os.join_path(freetype_src, 'base', 'ftgxval.c'),
			os.join_path(freetype_src, 'base', 'ftinit.c'),
			os.join_path(freetype_src, 'base', 'ftlcdfil.c'),
			os.join_path(freetype_src, 'base', 'ftmm.c'),
			os.join_path(freetype_src, 'base', 'ftotval.c'),
			os.join_path(freetype_src, 'base', 'ftpatent.c'),
			os.join_path(freetype_src, 'base', 'ftpfr.c'),
			os.join_path(freetype_src, 'base', 'ftstroke.c'),
			os.join_path(freetype_src, 'base', 'ftsynth.c'),
			os.join_path(freetype_src, 'base', 'ftsystem.c'),
			os.join_path(freetype_src, 'base', 'fttype1.c'),
			os.join_path(freetype_src, 'base', 'ftwinfnt.c'),
			os.join_path(freetype_src, 'bdf', 'bdf.c'),
			os.join_path(freetype_src, 'bzip2', 'ftbzip2.c'),
			os.join_path(freetype_src, 'cache', 'ftcache.c'),
			os.join_path(freetype_src, 'cff', 'cff.c'),
			os.join_path(freetype_src, 'cid', 'type1cid.c'),
			os.join_path(freetype_src, 'gzip', 'ftgzip.c'),
			os.join_path(freetype_src, 'lzw', 'ftlzw.c'),
			os.join_path(freetype_src, 'pcf', 'pcf.c'),
			os.join_path(freetype_src, 'pfr', 'pfr.c'),
			os.join_path(freetype_src, 'psaux', 'psaux.c'),
			os.join_path(freetype_src, 'pshinter', 'pshinter.c'),
			os.join_path(freetype_src, 'psnames', 'psmodule.c'),
			os.join_path(freetype_src, 'raster', 'raster.c'),
			os.join_path(freetype_src, 'sfnt', 'sfnt.c'),
			os.join_path(freetype_src, 'smooth', 'smooth.c'),
			os.join_path(freetype_src, 'tools', 'apinames.c'),
			os.join_path(freetype_src, 'truetype', 'truetype.c'),
			os.join_path(freetype_src, 'type1', 'type1.c'),
			os.join_path(freetype_src, 'type42', 'type42.c'),
			os.join_path(freetype_src, 'winfonts', 'winfnt.c'),
	]
	for source in sources {
		o_build.add_source(source, ['c'])!
	}
	a_build.add('dependencies', &o_build.Node)
	return &a_build.Node
}

