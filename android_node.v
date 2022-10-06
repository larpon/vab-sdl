module main

import os
import vab.util as vab_util
import vab.android.ndk

pub enum NodeKind {
	build_src_to_o
	build_dynamic_lib
	build_static_lib
}

pub enum LibKind {
	dynamic
	@static
}

fn product_cache_path() string {
	cache_path := os.cache_dir()
	return os.join_path(cache_path, 'v', 'android', 'sdl', 'products')
}

pub struct AndroidBuildOptions {
pub mut:
	version   string = '0.0.0' // version modifier of what's being built
	verbosity int    // level of verbosity
	parallel  bool = true
	cache     bool = true
	// env
	work_dir string // temporary work directory
	//
	is_prod         bool
	arch            string // compile for this CPU architecture
	ndk_version     string // version of the Android NDK to compile against
	api_level       string // Android API level to use when compiling
	min_sdk_version int
	//
	flags []string // extra flags to pass to the C compiler(s)
	// vmeta android.VMetaInfo
}

fn (abo &AndroidBuildOptions) make_product(path string) ! {
	err_sig := @FN
	mut products_path := product_cache_path()
	if !os.exists(products_path) {
		os.mkdir_all(products_path) or {
			return error('$err_sig: could not make product directory "$products_path"')
		}
	}

	id := os.file_name(path).all_after('lib').all_before('.')

	mut dst_path := ''
	if path.contains(os.path_separator + 'lib' + os.path_separator) {
		dst_path = abo.path_product_lib(id)
	}

	if dst_path == '' {
		return error('$err_sig: could resolve product directory for "$path"')
	}

	if !os.exists(dst_path) {
		os.mkdir_all(dst_path) or {
			return error('$err_sig: could not make product directory "$dst_path"')
		}
	}

	dst := os.join_path(dst_path, os.file_name(path))
	if os.exists(dst) {
		os.rm(dst) or { return error('$err_sig: could not delete existsing product "$dst"') }
	}
	os.cp(path, dst) or { return error('$err_sig: could not copy product "$path" to "$dst"') }
}

fn (abo &AndroidBuildOptions) path_product_lib(id string) string {
	// err_sig := @FN
	dst_path := os.join_path(abo.path_product_libs(id), abo.arch)
	return dst_path
}

fn (abo &AndroidBuildOptions) path_product_libs(id string) string {
	// err_sig := @FN
	products_path := product_cache_path()
	// NOTE Don't use abo.version in this scheme, since versions aren't known to other build nodes
	dst_path := os.join_path(products_path, id, 'lib')
	return dst_path
}

fn (abo AndroidBuildOptions) path_base() string {
	mut release_or_debug := 'debug'
	if abo.is_prod {
		release_or_debug = 'release'
	}
	return os.join_path(abo.work_dir, release_or_debug)
}

pub fn (abo AndroidBuildOptions) path_lib(id string) string {
	return os.join_path(abo.path_libs(id), abo.arch)
}

pub fn (abo AndroidBuildOptions) path_libs(id string) string {
	return os.join_path(abo.path_base(), id, abo.version, 'lib')
}

pub fn (abo AndroidBuildOptions) path_object(id string) string {
	return os.join_path(abo.path_objects(id), abo.arch)
}

pub fn (abo AndroidBuildOptions) path_objects(id string) string {
	return os.join_path(abo.path_base(), id, abo.version, 'o')
}

fn (abo AndroidBuildOptions) path_arch(id string, arch string, typ string) string {
	return os.join_path(abo.path_base(), id, abo.version, typ, arch)
}

fn (abo AndroidBuildOptions) path(id string, typ string) string {
	return os.join_path(abo.path_base(), id, abo.version, typ, abo.arch)
}

pub fn new_node(id string, kind NodeKind, arch string, tags []string) AndroidNode {
	mut f_tags := tags.clone()
	mut comment := ''
	mut pre_id := ''
	match kind {
		.build_src_to_o {
			comment = 'source to .o'
			f_tags << 'o'
		}
		.build_static_lib {
			pre_id = 'lib'
			comment = 'static'
			f_tags << ['lib', 'static']
		}
		.build_dynamic_lib {
			pre_id = 'lib'
			comment = 'dynamic'
			f_tags << ['lib', 'dynamic']
		}
	}
	f_tags << 'build'
	f_tags << arch
	mut node := AndroidNode{
		id: id
		Node: &Node{
			id: id
			note: '$pre_id$id $comment for $arch'
			tags: f_tags
		}
	}

	if kind == .build_dynamic_lib {
		mut exports := &Node{
			id: '${node.id}.exports'
			note: 'lib$node.id exports for $arch'
			tags: ['exports', '$arch']
		}
		node.add('exports', exports)
	}

	return node
}

[params]
pub struct AndroidNode {
	Node
}

[params]
pub struct AndroidNodeData {
	abo AndroidBuildOptions
}

fn (an &AndroidNode) from_node(node Node) AndroidNode {
	return AndroidNode{
		id: node.id
		Node: node
	}
}

pub fn (mut an AndroidNode) attach_data(and AndroidNodeData) {
	heap_and := &AndroidNodeData{
		...and
	}
	mut node := &an.Node
	node.data['AndroidNode'] = voidptr(heap_and)
}

pub fn (an AndroidNode) fetch_data() !AndroidNodeData {
	err_sig := @FN
	if node_data := an.Node.data['AndroidNode'] {
		if isnil(node_data) {
			return error('$err_sig: data field for $an.id is nil')
		}
		heap_and := &AndroidNodeData(node_data)
		stack_and := AndroidNodeData{
			abo: heap_and.abo
		}
		return stack_and
	}
	return error('$err_sig: $an.id has no data attached')
}

pub fn (mut an AndroidNode) add_export(kind string, entry string, tags []string) ! {
	err_sig := @FN
	node := &an.Node
	if 'exports' in node.items.keys() {
		mut exports_node := an.from_node(node.items['exports'].first())
		if kind == 'includes' {
			exports_node.add_include(entry, tags)!
		} else {
			e_node := as_heap(id: '$entry', note: 'unknown export', tags: tags)
			exports_node.add('includes', e_node)
		}
	} else {
		return error('$err_sig: $an.id has no exports entry in items')
	}
}

pub fn (mut an AndroidNode) add_link_lib(lib string, kind LibKind, arch string, tags []string) ! {
	mut ll_tags := tags.clone()
	match kind {
		.dynamic {
			ll_tags << 'dynamic'
		}
		.@static {
			ll_tags << 'static'
		}
	}
	ll_tags << arch
	an.add('libs', as_heap(id: lib, tags: ll_tags))
}

pub fn (an &AndroidNode) parent_exports(arch string) []AndroidNode {
	mut res := []AndroidNode{}
	mut node := an.Node.parent
	for !isnil(node) {
		if exports := node.items['exports'] {
			for export_node in exports {
				if export_node.has_tags(['$arch']) {
					res << an.from_node(export_node)
				}
			}
		}
		if isnil(node.parent) {
			break
		}
		node = node.parent
	}
	return res
}

pub fn (an &AndroidNode) exports(arch string) []AndroidNode {
	mut res := []AndroidNode{}
	if exports := an.Node.items['exports'] {
		for export_node in exports {
			if export_node.has_tags(['$arch']) {
				res << an.from_node(export_node)
			}
		}
	}
	return res
}

pub fn (an &AndroidNode) includes() []string {
	if include_nodes := an.items['includes'] {
		return include_nodes.map('$it.id')
	}
	return []string{}
}

pub fn (an &AndroidNode) arch() !string {
	err_sig := @FN
	arch_tag := an.Node.find_one_of_tags(ndk.supported_archs) or {
		return error('$err_sig: could not locate any tags on node')
	} // TODO non-recursive node dump
	return arch_tag
}

pub fn (an &AndroidNode) add_flag(flag string, tags []string) ! {
	// err_sig := @FN
	mut n := &an.Node

	mut desc := ''
	// TODO validate that node can carry a flag?
	mut flag_type := 'unknown'
	if flag.starts_with('-I') {
		flag_type = 'include'
	}
	if flag.starts_with('-include') {
		flag_type = 'direct include'
	}
	if flag.starts_with('-D') {
		flag_type = 'define'
	}
	if flag.starts_with('-W') {
		flag_type = 'warning'
	}
	if flag.starts_with('-f') {
		flag_type = 'normal'
	}
	if flag.starts_with('-l') {
		flag_type = 'linker'
	}

	desc += flag_type + ' flag'

	mut flag_tags := tags.clone()
	flag_tags << ['flag', flag_type]

	n.add('flags', as_heap(id: '$flag', note: desc, tags: flag_tags))
}

pub fn (an &AndroidNode) add_include(include string, tags []string) !&Node {
	err_sig := @FN
	mut node := &an.Node

	mut desc := ''
	mut inc_type := 'unknown'
	if os.is_dir(include) {
		inc_type = 'directory'
	} else if os.is_file(include) {
		inc_type = 'file'
	} else {
		return error('$err_sig: invalid include "$include" in node $node.id')
	}

	desc += inc_type + ' include'
	if 'c' in tags && 'cpp' in tags {
		desc = 'C/C++ ' + desc
	} else if 'c' in tags {
		desc = 'C ' + desc
	} else if 'cpp' in tags {
		desc = 'C++ ' + desc
	}

	mut i_tags := tags.clone()
	i_tags << ['include', inc_type]

	i_node := as_heap(id: '$include', note: desc, tags: i_tags)
	node.add('includes', i_node)
	return i_node
}

pub fn (an &AndroidNode) add_source(path string, tags []string) !&Node {
	err_sig := @FN
	mut n := &an.Node

	mut desc := ''
	// TODO validate that node can carry a flag?
	mut inc_type := 'unknown'
	if os.is_file(path) {
		inc_type = 'file'
	} else {
		return error('$err_sig: "$path" is not a file')
	}

	desc += 'source ' + inc_type

	arm_note := if 'arm' in tags { ' (arm)' } else { '' }
	if 'c' in tags {
		desc = 'C$arm_note ' + desc
	} else if 'cpp' in tags {
		desc = 'C++$arm_note ' + desc
	}

	mut s_tags := tags.clone()
	s_tags << 'source'

	if path.ends_with('.S') {
		s_tags << 'assembler'
	}
	s_tags << inc_type

	s_node := as_heap(id: '$path', note: desc, tags: s_tags)
	n.add('sources', s_node)
	return s_node
}

fn (an &AndroidNode) build_src_to_o() ! {
	err_sig := @FN

	node := an.Node
	node_data := an.fetch_data()!
	abo := node_data.abo
	arch := an.arch()!
	bo := abo

	// Setup work directories
	out_dir := os.join_path(bo.path_objects(node.id), arch)
	if !bo.cache {
		os.rmdir_all(out_dir) or {}
	}
	if !os.is_dir(out_dir) {
		os.mkdir_all(out_dir) or {
			return error('$err_sig: failed making directory "$out_dir". $err')
		}
	}

	lib := node.id
	include_nodes := node.items['includes'] or { []&Node{} }
	flag_nodes := node.items['flags'] or { []&Node{} }

	mut exported_include_nodes := []&Node{}
	exports := an.parent_exports(arch)
	for export in exports {
		if nodes := export.items['includes'] {
			exported_include_nodes << nodes
		}
	}

	mut jobs := []vab_util.ShellJob{}

	if file_nodes := node.items['sources'] {
		// Architechture dependent flags
		// TODO min_sdk_version SDL builds with 16 as lowest for the 32-bit archs?!
		// arch_cflags[arch] << [
		//	'-target ' + ndk.compiler_triplet(arch) + bo.min_sdk_version.str(),
		//]

		for file_node in file_nodes {
			source_file := file_node.id
			object_file := os.join_path(out_dir, os.file_name(source_file).all_before_last('.') +
				'.o')

			if bo.cache && os.is_file(object_file) {
				if bo.verbosity > 2 {
					eprintln('Using cached object file for $lib $arch "${os.file_name(object_file)}"')
				}
				continue
			}

			mut includes := []string{}
			mut flags := []string{}

			mut ndk_compiler_type := ndk.CompilerLanguageType.c
			if file_node.has_tags(['cpp']) {
				ndk_compiler_type = .cpp
			}

			match ndk_compiler_type {
				.c {
					includes << exported_include_nodes.filter(it.has_tags(['c'])).map('-I"$it.id"')
					includes << include_nodes.filter(it.has_tags(['c'])).map('-I"$it.id"')
					flags << flag_nodes.filter(it.has_tags(['c'])).map('$it.id')
				}
				.cpp {
					includes << exported_include_nodes.filter(it.has_tags(['cpp'])).map('-I"$it.id"')
					includes << include_nodes.filter(it.has_tags(['cpp'])).map('-I"$it.id"')
					flags << flag_nodes.filter(it.has_tags(['cpp'])).map('$it.id')
				}
			}

			if arch == 'armeabi-v7a' && !file_node.has_tags(['arm']) {
				flags << '-mthumb'
			}

			// TODO introduce method to get just the `clang` or `clang++` base wrapper
			compiler := ndk.compiler(ndk_compiler_type, bo.ndk_version, arch, bo.api_level) or {
				return error('$err_sig: failed getting NDK compiler. $err')
			}

			mut m_cflags := ['-MMD', '-MP'] //, '-MF <tmp path to SDL_<name>.o.d>']
			m_cflags << '-MF"' +
				os.join_path(out_dir, os.file_name(source_file).all_before_last('.') + '.o.d"')

			ndk_flag_res := ndk.compiler_flags_from_config(bo.ndk_version,
				arch: arch
				lang: ndk_compiler_type
				debug: !bo.is_prod
			)!
			build_cmd := [
				compiler,
				m_cflags.join(' '),
				ndk_flag_res.flags.join(' '),
				// arch_cflags[arch].join(' '),
				flags.join(' '),
				includes.join(' '),
				'-c "$source_file"',
				'-o "$object_file"',
			]

			jobs << vab_util.ShellJob{
				message: vab_util.ShellJobMessage {
					std_err: if bo.verbosity > 2 {
						mut thumb := ''
						if arch == 'armeabi-7va' {
							if '-mthumb' in flags {
								thumb = '(thumb)'
							} else {
								thumb = '(arm)'
							}
						}
						'Compiling $lib for $arch $thumb C file "${os.file_name(source_file)}"'
					} else {
						''
					}
				}
				cmd: build_cmd
			}
		}
	}
	vab_util.run_jobs(jobs, bo.parallel, bo.verbosity)!
	jobs.clear()
}

fn (an &AndroidNode) build_lib_static() ! {
	err_sig := @FN

	node := an.Node
	node_data := an.fetch_data()!
	abo := node_data.abo
	arch := abo.arch
	bo := abo

	// Setup work directories
	out_dir := os.join_path(bo.path_libs(node.id), arch)
	if !bo.cache {
		os.rmdir_all(out_dir) or {}
	}
	if !os.is_dir(out_dir) {
		os.mkdir_all(out_dir) or {
			return error('$err_sig: failed making directory "$out_dir". $err')
		}
	}

	lib := node.id
	lib_name := 'lib${lib}.a'
	lib_a_file := os.join_path(out_dir, lib_name)

	if bo.cache && os.is_file(lib_a_file) {
		if bo.verbosity > 2 {
			eprintln('Using cached .a file for $lib $arch "${os.file_name(lib_a_file)}"')
		}
		abo.make_product(lib_a_file)!
		return
	}

	mut o_files := []string{}

	// collect .o files added directly to node
	if added_o_files := node.items['o'] {
		for o_file_node in added_o_files {
			if o_file_node.has_tags(['o', 'file']) {
				o_file := o_file_node.id
				o_files << o_file
			}
		}
	}

	// collect .o files from child nodes
	if o_build := node.find_nearest(id: lib, tags: ['o', 'build', '$arch']) {
		o_out_dir := os.join_path(bo.path_objects(node.id), arch)
		if sources := o_build.items['sources'] {
			for source_node in sources {
				o_file_name := os.file_name(source_node.id).all_before_last('.') + '.o'
				o_file := os.join_path(o_out_dir, o_file_name)
				if o_file !in o_files {
					o_files << o_file
				}
			}
		}
	}
	if o_files.len == 0 {
		return error('$err_sig: could not locate any o files for building $lib_name')
	}

	mut jobs := []vab_util.ShellJob{}

	ar := ndk.tool(.ar, bo.ndk_version, arch) or {
		return error('$err_sig: failed getting ar tool. $err')
	}

	build_a_cmd := [
		ar,
		'crsD',
		'"$lib_a_file"',
		o_files.map('"$it"').join(' '),
	]

	jobs << vab_util.ShellJob{
		message: vab_util.ShellJobMessage {
			std_err: if abo.verbosity > 1 { 'Compiling (static) $lib for $arch' } else { '' }
		}
		cmd: build_a_cmd
	}
	vab_util.run_jobs(jobs, abo.parallel, abo.verbosity)!
	jobs.clear()
	abo.make_product(lib_a_file)!
}

fn (an &AndroidNode) build_lib_shared() ! {
	err_sig := @FN

	node := an.Node
	node_data := an.fetch_data()!
	abo := node_data.abo
	arch := abo.arch
	bo := abo

	// Setup work directories
	out_dir := os.join_path(bo.path_libs(node.id), arch)
	if !bo.cache {
		os.rmdir_all(out_dir) or {}
	}
	if !os.is_dir(out_dir) {
		os.mkdir_all(out_dir) or {
			return error('$err_sig: failed making directory "$out_dir". $err')
		}
	}

	lib := node.id
	lib_name := 'lib${lib}.so'
	lib_so_file := os.join_path(out_dir, lib_name)

	if bo.cache && os.is_file(lib_so_file) {
		if bo.verbosity > 2 {
			eprintln('Using cached .so file for $lib $arch "${os.file_name(lib_so_file)}"')
		}
		abo.make_product(lib_so_file)!
		if arch == 'armeabi-v7a' && node.has_tags(['use-v7a-as-armeabi']) {
			// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
			armeabi_lib_dir := bo.path_arch(node.id, 'armeabi', 'lib')
			armeabi_lib_dst := os.join_path(armeabi_lib_dir, '$lib_name')
			abo.make_product(armeabi_lib_dst)!
		}
		return
	}
	mut o_files := []string{}

	// collect .o files added directly to node
	if added_o_files := node.items['o'] {
		for o_file_node in added_o_files {
			if o_file_node.has_tags(['o', 'file']) {
				o_file := o_file_node.id
				o_files << o_file
			}
		}
	}

	// collect .o files from child nodes
	if o_build := node.find_nearest(id: lib, tags: ['o', 'build', '$arch']) {
		o_out_dir := os.join_path(bo.path_objects(node.id), arch)
		if sources := o_build.items['sources'] {
			for source_node in sources {
				o_file_name := os.file_name(source_node.id).all_before_last('.') + '.o'
				o_file := os.join_path(o_out_dir, o_file_name)
				if o_file !in o_files {
					o_files << o_file
				}
			}
		}
	}
	if o_files.len == 0 {
		return error('$err_sig: could not locate any o files for building $lib_name')
	}

	// automatically collect libs from dependencies
	mut so_files := []string{}
	mut a_files := []string{}

	if libs_nodes := node.items['libs'] {
		for libs_node in libs_nodes {
			lib_base := 'lib' + libs_node.id

			mut lib_out_dir := bo.path_product_lib(libs_node.id)

			a_lib := os.join_path(lib_out_dir, lib_base + '.a')
			so_lib := os.join_path(lib_out_dir, lib_base + '.so')

			if libs_node.has_tags(['static']) {
				if os.is_file(a_lib) {
					a_files << a_lib
				} else {
					return error('$err_sig: could not locate static version of dependency libs $a_lib for $lib_name')
				}
			} else if libs_node.has_tags(['dynamic']) {
				if os.is_file(so_lib) {
					so_files << so_lib
				} else {
					return error('$err_sig: could not locate shared version of dependency libs $so_lib for $lib_name')
				}
			} else {
				return error('$err_sig: could not locate any of dependency libs $a_lib / $so_lib for $lib_name')
			}
		}
	}

	// ld_flags
	mut ld_flags := []string{}
	if flag_nodes := node.items['flags'] {
		for flag_node in flag_nodes {
			if flag_node.has_tags(['flag', 'linker']) {
				ld_flags << flag_node.id
			}
		}
	}
	if '-ldl' !in ld_flags {
		ld_flags << '-ldl'
	}

	mut ndk_compiler_type := ndk.CompilerLanguageType.c
	if node.has_tags(['cpp']) {
		ndk_compiler_type = .cpp
	}

	// TODO introduce method to get just the `clang` or `clang++` base wrapper
	compiler := ndk.compiler(ndk_compiler_type, bo.ndk_version, arch, bo.api_level) or {
		return error('$err_sig: failed getting NDK compiler. $err')
	}

	/*
	match ndk_compiler_type {
		.c {
			includes << exported_include_nodes.filter(it.has_tags(['c'])).map('-I"$it.id"')
			includes << include_nodes.filter(it.has_tags(['c'])).map('-I"$it.id"')
			flags << flag_nodes.filter(it.has_tags(['c'])).map('$it.id')
		}
		.cpp {
			includes << exported_include_nodes.filter(it.has_tags(['cpp'])).map('-I"$it.id"')
			includes << include_nodes.filter(it.has_tags(['cpp'])).map('-I"$it.id"')
			flags << flag_nodes.filter(it.has_tags(['cpp'])).map('$it.id')
		}
	}*/

	mut jobs := []vab_util.ShellJob{}

	ndk_flag_res := ndk.compiler_flags_from_config(bo.ndk_version,
		arch: arch
		lang: ndk_compiler_type
		debug: !bo.is_prod
		cpp_features: ['no-rtti', 'no-exceptions']
	)!

	// Finally, build libXXX.so
	build_so_cmd := [
		compiler,
		'-Wl,-soname,$lib_name -shared',
		o_files.map('"$it"').join(' '),
		a_files.map('"$it"').join(' '),
		so_files.map('"$it"').join(' '),
		ndk_flag_res.ld_flags.join(' '),
		ld_flags.join(' '),
		'-o "$lib_so_file"',
	]

	jobs << vab_util.ShellJob{
		message: vab_util.ShellJobMessage {
			std_err: if abo.verbosity > 1 {
				'Compiling (shared) $lib for $arch'
			} else {
				''
			}
		}
		cmd: build_so_cmd
	}

	vab_util.run_jobs(jobs, abo.parallel, abo.verbosity)!
	jobs.clear()

	abo.make_product(lib_so_file)!

	// TODO include in cache check
	if arch == 'armeabi-v7a' && node.has_tags(['use-v7a-as-armeabi']) {
		// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
		armeabi_lib_dir := bo.path_arch(node.id, 'armeabi', 'lib')
		armeabi_v7a_lib_dir := bo.path_arch(node.id, arch, 'lib')
		os.mkdir_all(armeabi_lib_dir) or {
			return error('$err_sig: failed making directory "$armeabi_lib_dir".\n$err')
		}

		armeabi_lib_src := os.join_path(armeabi_v7a_lib_dir, '$lib_name')
		armeabi_lib_dst := os.join_path(armeabi_lib_dir, '$lib_name')
		os.cp(armeabi_lib_src, armeabi_lib_dst) or {
			return error('$err_sig: failed copying "$armeabi_lib_src" to "$armeabi_lib_dst".\n$err')
		}

		abo.make_product(armeabi_lib_dst)!
	}
}

pub fn (an &AndroidNode) build() ! {
	err_sig := @FN
	mut node := &an.Node

	if node.is_root() {
		products_path := product_cache_path()
		os.mkdir_all(products_path) or {
			return error('$err_sig: could not make product directory "$products_path"')
		}
	}

	// Build dependencies first
	if dependencies := node.items['dependencies'] {
		println('Recursing $node.id $node.note')
		for dep_node in dependencies {
			a_node := an.from_node(dep_node)
			a_node.build()!
		}
	}

	if node.has_fn('pre_build') {
		node.invoke_fn('pre_build')!
	}

	is_object_build := node.has_tags(['o', 'build'])

	if is_object_build {
		items_available := node.items.keys()
		println('Build $node.id $node.note (c to o) items $items_available')

		an.build_src_to_o()!

		for item in items_available {
			if item in ['dependencies', 'sources', 'tasks'] {
				continue
			}
			/*
			if item == 'exports' {
				exports := an.exports(arch)
				for export in exports {
					println('\t$item:')
					includes := export.includes()
					if includes.len > 0 {
						println('\t  includes: $includes')
					}
				}
			} else if item_nodes := node.items[item] {
				ids := item_nodes.map('$it.id')
				println('\t$item: $ids')
			}
			*/
		}
	}

	is_static_lib_build := node.has_tags(['lib', 'static'])
	is_shared_lib_build := node.has_tags(['lib', 'dynamic'])
	if is_static_lib_build || is_shared_lib_build {
		items_available := node.items.keys()
		lib_type := if node.has_tags(['static']) { 'static' } else { 'dynamic' }
		println('Build $node.id $node.note ($lib_type lib) items $items_available')

		if is_static_lib_build {
			an.build_lib_static()!
		}
		if is_shared_lib_build {
			an.build_lib_shared()!
		}

		for item in items_available {
			if item in ['dependencies', 'sources', 'tasks'] {
				continue
			}
			/*
			if item == 'exports' {
				exports := an.exports(arch)
				for export in exports {
					println('\t$item:')
					includes := export.includes()
					if includes.len > 0 {
						println('\t  includes: $includes')
					}
				}
			} else if item_nodes := node.items[item] {
				ids := item_nodes.map('$it.id')
				println('\t$item: $ids')
			}*/
		}
	}

	if tasks := node.items['tasks'] {
		println('Looping tasks $node.id $node.note')
		for task_node in tasks {
			a_node := an.from_node(task_node)
			a_node.build()!
		}
	}
}
