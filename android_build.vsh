#!/usr/bin/env -S v

module main

// import semver
import vab.vxt
// import vab.java
import os
import flag
import runtime
import sync.pool
import crypto.md5
import vab.android
import vab.android.sdk
import vab.android.ndk
// import vab.android.env
import vab.android.util

const (
	exe_version            = version()
	exe_pretty_name        = os.file_name(@FILE)
	exe_name               = os.file_name(os.executable())
	exe_dir                = os.dir(os.real_path(os.executable()))
	exe_description        = '$exe_pretty_name
compile SDL for Android.
'
	exe_git_hash           = ab_commit_hash()
	work_directory         = ab_work_dir()
	accepted_input_files   = ['.v', '.apk', '.aab']
	supported_sdl_versions = ['2.0.8', '2.0.9', '2.0.10', '2.0.12', '2.0.14', '2.0.16', '2.0.18',
		'2.0.20', '2.0.22']
)

struct Options {
	// Internals
	verbosity int
	// Build specifics
	c_flags   []string // flags passed to the C compiler(s)
	archs     []string
	show_help bool
	work_dir  string = work_directory
mut:
	additional_args []string
	//
	input  string
	output string
	// Build and packaging
	is_prod bool
	// Build specifics
	api_level       string
	ndk_version     string
	min_sdk_version int = android.default_min_sdk_version
}

struct CompileOptions {
	verbosity int // level of verbosity
	parallel  bool = true
	cache     bool = true
	cache_key string
	// env
	input    string
	work_dir string // temporary work directory
	//
	is_prod         bool
	archs           []string // compile for these CPU architectures
	c_flags         []string // flags to pass to the C compiler(s)
	ndk_version     string   // version of the Android NDK to compile against
	api_level       string   // Android API level to use when compiling
	min_sdk_version int
	//
	sdl_config SDLConfig
}

// archs returns an array of target architectures.
pub fn (opt CompileOptions) archs() ![]string {
	mut archs := []string{}
	if opt.archs.len > 0 {
		for arch in opt.archs.map(it.trim_space()) {
			if arch in android.default_archs {
				archs << arch
			} else {
				return error(@MOD + '.' + @FN +
					': Architechture "$arch" not one of $android.default_archs')
			}
		}
	}
	return archs
}

struct SDLConfig {
	root string
}

struct SDLEnv {
	version      string
	src_path     string
	include_path string
	c_files      []string
	c_arm_files  []string
	cpp_files    []string
}

struct ShellJob {
	std_out  string
	std_err  string
	env_vars map[string]string
	cmd      []string
}

struct ShellJobResult {
	job    ShellJob
	result os.Result
}

fn async_run(pp &pool.PoolProcessor, idx int, wid int) &ShellJobResult {
	item := pp.get_item<ShellJob>(idx)
	return sync_run(item)
}

fn sync_run(item ShellJob) &ShellJobResult {
	for key, value in item.env_vars {
		os.setenv(key, value, true)
	}
	if item.std_out != '' {
		println(item.std_out)
	}
	if item.std_err != '' {
		println(item.std_err)
	}
	res := util.run(item.cmd)
	return &ShellJobResult{
		job: item
		result: res
	}
}

fn main() {
	mut opt := Options{}
	mut fp := &flag.FlagParser(0)

	opt, fp = args_to_options(os.args, opt) or {
		println(fp.usage())
		eprintln('Error while parsing `os.args`: $err')
		exit(1)
	}

	if opt.show_help {
		println(fp.usage())
		exit(0)
	}

	input := fp.args[fp.args.len - 1]
	/*input_ext := os.file_ext(input)
	if !(os.is_dir(input) || input_ext in accepted_input_files) {
		println(fp.usage())
		eprintln('$exe_name requires input to be a V file, an APK, AAB or a directory containing V sources')
		exit(1)
	}*/
	opt.input = input

	resolve_options(mut opt, true)


	// TODO detect sdl module + SDL2 version -> download sources -> build -> $$$Profit
	// v_sdl_path := detect_v_sdl_module_path()
	vmodules_path := vxt.vmodules() or { panic(err) }
	sdl_module_home := os.join_path(vmodules_path,'sdl')
	if !os.is_dir(sdl_module_home) {
		panic(@MOD+'.'+@FN+': could not locate `vlang/sdl` module. It can be installed by running `v install sdl`')
	}
	sdl_home := os.getenv('SDL_HOME')
	if !os.is_dir(sdl_home) {
		panic(@MOD+'.'+@FN+': could not locate SDL install at "$sdl_home"')
	}
	sdl_config := SDLConfig{
		root: sdl_home
	}

	comp_opt := CompileOptions{
		verbosity: opt.verbosity
		is_prod: opt.is_prod
		c_flags: opt.c_flags
		archs: opt.archs
		work_dir: opt.work_dir
		input: opt.input
		ndk_version: opt.ndk_version
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
		sdl_config: sdl_config
	}

	compile_sdl(comp_opt) or { panic(err) }
	compile_v_code(comp_opt) or { panic(err) }
}

fn compile_sdl(opt CompileOptions) ! {
	err_sig := @MOD + '.' + @FN

	ndk_root := ndk.root_version(opt.ndk_version)
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('$err_sig: getting NDK sysroot path. $err')
	}

	build_dir := os.join_path(opt.work_dir, 'sdl_build')

	is_prod_build := opt.is_prod
	is_debug_build := !is_prod_build

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or { return error('$err_sig: failed removing previous build directory "$build_dir". $err') }
	}
	os.mkdir_all(build_dir) or {
		return error('$err_sig: failed making directory "$build_dir". $err')
	}

	// Resolve compiler flags
	// For all C compilers
	mut cflags := opt.c_flags
	// For all C++ compilers
	mut cppflags := ['-fno-exceptions', '-fno-rtti']

	// For all compilers
	mut includes := []string{}
	mut defines := []string{}

	if opt.is_prod {
		cflags << ['-Os']
	} else {
		cflags << ['-O0']
	}

	sdl_env := sdl_environment(opt.sdl_config)!
	if opt.verbosity > 2 {
		eprintln('SDL environment:\n$sdl_env')
	}

	// Resolve what architectures to compile for
	mut archs := opt.archs()!
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = android.default_archs.clone()
	}
	if opt.verbosity > 0 {
		eprintln('Compiling SDL to $archs')
	}

	/*
	if opt.verbosity > 2 {
		cflags << ['-v'] // Verbose clang
	}*/

	// DEBUG builds
	if is_debug_build {
		cflags << ['-fno-limit-debug-info', '-fdata-sections', '-ffunction-sections',
			'-fstack-protector-strong', '-funwind-tables', '-no-canonical-prefixes']
		cflags << ['-g']

		defines << ['-UNDEBUG']
	}

	cflags << ['--sysroot "$ndk_sysroot"']

	// Defaults
	cflags << ['-Wall', '-Wextra', '-Wformat', '-Werror=format-security']
	// SDL -W's
	cflags << ['-Wdocumentation', '-Wdocumentation-unknown-command', '-Wmissing-prototypes',
		'-Wunreachable-code-break', '-Wunneeded-internal-declaration',
		'-Wmissing-variable-declarations', '-Wfloat-conversion', '-Wshorten-64-to-32',
		'-Wunreachable-code-return', '-Wshift-sign-overflow', '-Wstrict-prototypes',
		'-Wkeyword-macro']

	// TODO Unfixed NDK/Gradle (?)
	cflags << ['-Wno-invalid-command-line-argument', '-Wno-unused-command-line-argument']

	// SDL/JNI specifics that aren't fixed yet
	cflags << ['-Wno-unused-parameter', '-Wno-sign-compare']

	cflags << ['-fpic']
	// '-mthumb' except for SDL_atomic.c / SDL_spinlock.c

	defines << ['-D_FORTIFY_SOURCE=2']
	defines << ['-DANDROID', '-DGL_GLEXT_PROTOTYPES']

	includes << '-I"' + sdl_env.include_path + '"'

	ndk_cpu_features_path := os.join_path(ndk.root_version(opt.ndk_version), 'sources',
		'android', 'cpufeatures')
	includes << ['-I"$ndk_cpu_features_path"']

	mut arch_cc := map[string]string{}
	mut arch_cc_cpp := map[string]string{}
	mut arch_ar := map[string]string{}
	// mut arch_libs := map[string]string{}

	mut arch_cflags := map[string][]string{}
	for arch in archs {
		// TODO introduce method to get just the `clang` or `clang++` base wrapper
		c_compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			return error('$err_sig: failed getting NDK compiler. $err')
		}
		arch_cc[arch] = c_compiler

		cpp_compiler := ndk.compiler(.cpp, opt.ndk_version, arch, opt.api_level) or {
			return error('$err_sig: failed getting NDK compiler. $err')
		}
		arch_cc_cpp[arch] = cpp_compiler

		ar_tool := ndk.tool(.ar, opt.ndk_version, arch) or {
			return error('$err_sig: failed getting ar tool. $err')
		}
		arch_ar[arch] = ar_tool

		// Architechture dependent flags
		// TODO min_sdk_version SDL builds with 16 as lowest for the 32-bit archs?!
		arch_cflags[arch] << [
			'-target ' + ndk.compiler_triplet(arch) + opt.min_sdk_version.str(),
		]
		if arch == 'armeabi-v7a' {
			arch_cflags[arch] << ['-march=armv7-a']
		}
	}

	// TODO clean up this mess
	mut cpufeatures_c_args := []string{}
	// DEBUG builds
	if is_debug_build {
		cpufeatures_c_args << ['-fno-limit-debug-info', '-fdata-sections', '-ffunction-sections',
			'-fstack-protector-strong', '-funwind-tables', '-no-canonical-prefixes']
		cpufeatures_c_args << ['-g']
		cpufeatures_c_args << ['-UNDEBUG']
	}
	cpufeatures_c_args << ['--sysroot "$ndk_sysroot"']
	// Unfixed NDK
	cpufeatures_c_args << ['-Wno-invalid-command-line-argument', '-Wno-unused-command-line-argument']
	// Defaults
	cpufeatures_c_args << ['-Wall', '-Wextra', '-Werror', '-Wformat', '-Werror=format-security']
	cpufeatures_c_args << ['-D_FORTIFY_SOURCE=2']
	cpufeatures_c_args << ['-fpic']
	cpufeatures_c_args << ['-mthumb']
	cpufeatures_c_args << ['-I"$ndk_cpu_features_path"']

	// Cross compile each .c/.cpp to .o
	mut jobs := []ShellJob{}
	mut o_files := map[string][]string{}
	mut a_files := map[string][]string{}

	for arch in archs {
		// Setup work directories
		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir) or {
			return error('$err_sig: failed making directory "$arch_lib_dir". $err')
		}

		tmp_arch_object_dir := os.join_path(build_dir, 'tmp', arch, 'objects')
		os.rmdir_all(tmp_arch_object_dir) or {}
		os.mkdir_all(tmp_arch_object_dir) or {
			return error('$err_sig: failed making directory "$tmp_arch_object_dir". $err')
		}

		tmp_arch_dep_file_dir := os.join_path(build_dir, 'tmp', arch, 'deps')
		os.rmdir_all(tmp_arch_dep_file_dir) or {}
		os.mkdir_all(tmp_arch_dep_file_dir) or {
			return error('$err_sig: failed making directory "tmp_arch_dep_file_dir". $err')
		}

		arch_ndk_tmp_dir := os.join_path(build_dir, 'tmp', 'ndk', arch)
		os.mkdir_all(arch_ndk_tmp_dir) or {
			return error('$err_sig: failed making directory "arch_ndk_tmp_dir". $err')
		}

		// Start collecting flags, files etc.

		// Compile cpu-features
		// cpu-features.c -> cpu-features.o -> cpu-features.a
		cpufeatures_source_file := os.join_path(ndk_cpu_features_path, 'cpu-features.c')
		cpufeatures_o_file := os.join_path(tmp_arch_object_dir,
			os.file_name(cpufeatures_source_file).all_before_last('.') + '.o')
		cpufeatures_a_file := os.join_path(arch_lib_dir, 'libcpufeatures.a')
		if opt.verbosity > 0 {
			eprintln('Compiling for $arch (thumb) NDK cpu-features "${os.file_name(cpufeatures_source_file)}"')
		}

		mut cpufeatures_m_cflags := []string{}
		if is_debug_build {
			cpufeatures_m_cflags << ['-MMD', '-MP'] //, '-MF <tmp path to SDL_<name>.o.d>']
			cpufeatures_m_cflags << '-MF"' +
				os.join_path(arch_ndk_tmp_dir, os.file_name(cpufeatures_source_file).all_before_last('.') +
				'.o.d"')
		}

		cpufeatures_build_cmd := [
			arch_cc[arch],
			arch_cflags[arch].join(' '),
			cpufeatures_m_cflags.join(' '),
			cpufeatures_c_args.join(' '),
			'-c "$cpufeatures_source_file"',
			'-o "$cpufeatures_o_file"',
		]

		// TODO -showcc ??
		util.verbosity_print_cmd(cpufeatures_build_cmd, opt.verbosity)
		cpufeatures_comp_res := util.run_or_error(cpufeatures_build_cmd) !
		if opt.verbosity > 2 {
			eprintln(cpufeatures_comp_res)
		}

		if opt.verbosity > 0 {
			eprintln('Creating static library for $arch NDK cpu-features from "${os.file_name(cpufeatures_o_file)}"')
		}

		// Build static .a
		cpufeatures_build_static_cmd := [
			arch_ar[arch],
			'crsD',
			'"$cpufeatures_a_file"',
			'"$cpufeatures_o_file"',
		]

		// TODO -showcc ??
		util.verbosity_print_cmd(cpufeatures_build_static_cmd, opt.verbosity)
		cpufeatures_a_res := util.run_or_error(cpufeatures_build_static_cmd)!
		if opt.verbosity > 2 {
			eprintln(cpufeatures_a_res)
		}

		a_files[arch] << cpufeatures_a_file

		// Compile C files to object files
		for c_file in sdl_env.c_files {
			source_file := c_file
			object_file := os.join_path(tmp_arch_object_dir,
				os.file_name(source_file).all_before_last('.') + '.o')
			o_files[arch] << object_file

			mut m_cflags := []string{}
			if is_debug_build {
				m_cflags << ['-MMD', '-MP'] //, '-MF <tmp path to SDL_<name>.o.d>']
				m_cflags << '-MF"' +
					os.join_path(tmp_arch_dep_file_dir, os.file_name(source_file).all_before_last('.') +
					'.o.d"')
			}

			build_cmd := [
				arch_cc[arch],
				m_cflags.join(' '),
				arch_cflags[arch].join(' '),
				'-mthumb',
				cflags.join(' '),
				includes.join(' '),
				defines.join(' '),
				'-c "$source_file"',
				'-o "$object_file"',
			]

			jobs << ShellJob{
				std_err: if opt.verbosity > 0 { 'Compiling for $arch (thumb) C SDL file "${os.file_name(c_file)}"' } else { '' }
				cmd: build_cmd
			}
		}

		// Compile (without thumb) C files to object files
		for c_arm_file in sdl_env.c_arm_files {
			source_file := c_arm_file
			object_file := os.join_path(tmp_arch_object_dir,
				os.file_name(source_file).all_before_last('.') + '.o')
			o_files[arch] << object_file

			mut m_cflags := []string{}
			if is_debug_build {
				m_cflags << ['-MMD', '-MP']
				m_cflags << '-MF"' +
					os.join_path(tmp_arch_dep_file_dir, os.file_name(source_file).all_before_last('.') +
					'.o.d"')
			}

			build_cmd := [
				arch_cc[arch],
				m_cflags.join(' '),
				arch_cflags[arch].join(' '),
				cflags.join(' '),
				includes.join(' '),
				defines.join(' '),
				'-c "$source_file"',
				'-o "$object_file"',
			]

			jobs << ShellJob{
				std_err: if opt.verbosity > 0 { 'Compiling for $arch (arm)   C SDL file "${os.file_name(c_arm_file)}"' } else { '' }
				cmd: build_cmd
			}
		}

		// Compile C++ files to object files
		for cpp_file in sdl_env.cpp_files {
			source_file := cpp_file
			object_file := os.join_path(tmp_arch_object_dir,
				os.file_name(source_file).all_before_last('.') + '.o')
			o_files[arch] << object_file

			mut m_cflags := []string{}
			if is_debug_build {
				m_cflags << ['-MMD', '-MP']
				m_cflags << '-MF"' +
					os.join_path(tmp_arch_dep_file_dir, os.file_name(source_file).all_before_last('.') +
					'.o.d"')
			}

			build_cmd := [
				arch_cc_cpp[arch],
				arch_cflags[arch].join(' '),
				'-mthumb',
				m_cflags.join(' '),
				cppflags.join(' '),
				cflags.join(' '),
				includes.join(' '),
				defines.join(' '),
				'-c "$source_file"',
				'-o "$object_file"',
			]

			jobs << ShellJob{
				std_err: if opt.verbosity > 0 { 'Compiling for $arch (thumb) C++ SDL file "${os.file_name(cpp_file)}"' } else { '' }
				cmd: build_cmd
			}
		}
	}

	if opt.parallel {
		mut pp := pool.new_pool_processor(maxjobs: runtime.nr_cpus() - 1, callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results<ShellJobResult>() {
			util.verbosity_print_cmd(job_res.job.cmd, opt.verbosity)
			util.exit_on_bad_result(job_res.result, '${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				eprintln(job_res.result.output)
			}
		}
	} else {
		for job in jobs {
			util.verbosity_print_cmd(job.cmd, opt.verbosity)
			job_res := sync_run(job)
			util.exit_on_bad_result(job_res.result, '${job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				eprintln(job_res.result.output)
			}
		}
	}
	jobs.clear()

	// libSDL2.so linker flags
	mut ldflags := []string{}
	ldflags << ['-ldl', '-lGLESv1_CM', '-lGLESv2', '-lOpenSLES', '-llog', '-landroid', '-lc', '-lm']

	for arch in archs {
		arch_lib_dir := os.join_path(build_dir, 'lib', arch)

		libsdl2_so_file := os.join_path(arch_lib_dir, 'libSDL2.so')
		// Finally, build libSDL2.so
		build_so_cmd := [
			arch_cc_cpp[arch],
			'-Wl,-soname,libSDL2.so -shared',
			o_files[arch].map('"' + it + '"').join(' '), // <ALL .o files produced above except cpu-features>
			a_files[arch].map('"' + it + '"').join(' '), // <path to>/libcpufeatures.a
			'-lgcc -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_real.a -latomic -Wl,--exclude-libs,libatomic.a',
			arch_cflags[arch].join(' '),
			'-no-canonical-prefixes',
			'-Wl,--build-id',
			'-stdlib=libstdc++',
			'-Wl,--no-undefined',
			'-Wl,--fatal-warnings',
			ldflags.join(' '),
			'-o "$libsdl2_so_file"',
		]

		jobs << ShellJob{
			std_err: if opt.verbosity > 0 { 'Compiling libSDL2.so for $arch' } else { '' }
			cmd: build_so_cmd
		}
	}

	if opt.parallel {
		mut pp := pool.new_pool_processor(maxjobs: runtime.nr_cpus() - 1, callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results<ShellJobResult>() {
			util.verbosity_print_cmd(job_res.job.cmd, opt.verbosity)
			util.exit_on_bad_result(job_res.result, '${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				eprintln(job_res.result.output)
			}
		}
	} else {
		for job in jobs {
			util.verbosity_print_cmd(job.cmd, opt.verbosity)
			job_res := sync_run(job)
			util.exit_on_bad_result(job_res.result, '${job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				eprintln(job_res.result.output)
			}
		}
	}

	unsafe { jobs.free() }

	if 'armeabi-v7a' in archs {
		// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
		armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
		os.mkdir_all(armeabi_lib_dir) or {
			return error('$err_sig: failed making directory "$armeabi_lib_dir". $err')
		}

		armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'libSDL2.so')
		armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'libSDL2.so')
		os.cp(armeabi_lib_src, armeabi_lib_dst) or {
			return error('$err_sig: failed copying "$armeabi_lib_src" to "$armeabi_lib_dst". $err')
		}

		cpufeatures_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'libcpufeatures.a')
		cpufeatures_lib_dst := os.join_path(armeabi_lib_dir, 'libcpufeatures.a')
		os.cp(cpufeatures_lib_src, cpufeatures_lib_dst) or {
			return error('$err_sig: failed copying "$cpufeatures_lib_src" to "$cpufeatures_lib_dst". $err')
		}
	}
}

fn compile_v_code(opt CompileOptions) ! {

	// Keystore file
	mut keystore := android.Keystore{
		path: ''
	}
	if !os.is_file(keystore.path) {
		if keystore.path != '' {
			eprintln('Keystore "$keystore.path" is not a valid file')
			eprintln('Notice: Signing with debug keystore')
		}
		keystore_dir := os.join_path(opt.work_dir, 'keystore')
		if !os.is_dir(keystore_dir) {
			os.mkdir_all(keystore_dir) or {
				eprintln('Could make directory for debug keystore.\n$err')
				exit(1)
			}
		}
		keystore.path = os.join_path(keystore_dir, 'debug.keystore')
	}
	keystore = android.resolve_keystore(keystore, opt.verbosity) !

	mut c_flags := opt.c_flags
	c_flags << '-I"'+os.join_path(opt.sdl_config.root,'include')+'"'
	c_flags << '-UNDEBUG'
	c_flags << '-D_FORTIFY_SOURCE=2'
	c_flags << ['-Wno-pointer-to-int-cast', '-Wno-constant-conversion', '-Wno-literal-conversion','-Wno-deprecated-declarations']
	//c_flags << '-mthumb'
	// V specific
	c_flags << ['-Wno-int-to-pointer-cast']

	compile_cache_key := if os.is_dir(opt.input) /*|| input_ext == '.v'*/ { opt.input } else { '' }
	comp_opt := android.CompileOptions{
		verbosity: opt.verbosity
		cache: false //opt.cache
		cache_key: compile_cache_key
		parallel: opt.parallel
		is_prod: opt.is_prod
		no_printf_hijack: false
		v_flags: ['-gc none']// opt.v_flags
		c_flags: c_flags
		archs: opt.archs.filter(it.trim(' ') != '')
		work_dir: opt.work_dir
		input: opt.input
		ndk_version: opt.ndk_version
		lib_name: 'main' //opt.lib_name
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
	}
	vab_compile(comp_opt) or {
		eprintln('$exe_name compiling didn\'t succeed')
		exit(1)
	}

	pck_opt := android.PackageOptions{
		verbosity: opt.verbosity
		work_dir: opt.work_dir
		is_prod: opt.is_prod
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
		gles_version: 2 //opt.gles_version
		build_tools: sdk.default_build_tools_version
		//app_name: opt.app_name
		lib_name: 'main' //opt.lib_name
		activity_name: 'VSDLActivity'
		package_id: 'io.v.android.ex'
		//activity_name: 'SDLActivity' // activity_name
		//package_id: 'org.libsdl.app'//'io.v.android.ex' //package_id
		//format: android.PackageFormat.aab //format
		format: android.PackageFormat.apk //format
		//icon: opt.icon
		version_code: 0 //opt.version_code
		// v_flags: opt.v_flags
		input: opt.input
		//assets_extra: opt.assets_extra
		libs_extra: [os.join_path(opt.work_dir, 'sdl_build','lib')] //opt.libs_extra
		output_file: '/tmp/t.apk' //opt.output
		keystore: keystore
		base_files: os.join_path('$os.home_dir()/.vmodules/vab', 'platforms', 'android')
		//base_files: '$os.home_dir()/Projects/vdev/v_sdl4android/tmp/v_sdl_java'
		overrides_path: '$os.home_dir()/Projects/vdev/v_sdl4android/tmp/v_sdl_java' //opt.package_overrides_path
	}
	android.package(pck_opt) or {
		eprintln("Packaging didn't succeed:\n$err")
		exit(1)
	}
}

fn args_to_options(arguments []string, defaults Options) ?(Options, &flag.FlagParser) {
	mut args := arguments.clone()

	mut fp := flag.new_flag_parser(args)
	fp.application(exe_pretty_name)
	fp.version(version_full())
	fp.description(exe_description)
	fp.arguments_description('input')

	fp.skip_executable()

	mut verbosity := fp.int_opt('verbosity', `v`, 'Verbosity level 1-3') or { defaults.verbosity }
	// TODO implement FlagParser 'is_sat(name string) bool' or something in vlib for this usecase?
	if ('-v' in args || 'verbosity' in args) && verbosity == 0 {
		verbosity = 1
	}

	mut opt := Options{
		c_flags: fp.string_multi('cflag', `c`, 'Additional flags for the C compiler')
		archs: fp.string('archs', 0, defaults.archs.filter(it.trim(' ') != '').join(','),
			'Comma separated string with any of $android.default_archs').split(',').filter(it.trim(' ') != '')
		//
		show_help: fp.bool('help', `h`, defaults.show_help, 'Show this help message and exit')
		//
		output: fp.string('output', `o`, defaults.output, 'Path to output (dir/file)')
		//
		verbosity: verbosity
		//
		api_level: fp.string('api', 0, defaults.api_level, 'Android API level to use')
		min_sdk_version: fp.int('min-sdk-version', 0, defaults.min_sdk_version, 'Minimum SDK version version code (android:minSdkVersion)')
		//
		ndk_version: fp.string('ndk-version', 0, defaults.ndk_version, 'Android NDK version to use')
		//
		work_dir: defaults.work_dir
	}

	opt.additional_args = fp.finalize()?

	return opt, fp
}

fn resolve_options(mut opt Options, exit_on_error bool) {
	// Validate SDK API level
	mut api_level := sdk.default_api_level
	if api_level == '' {
		eprintln('No Android API levels could be detected in the SDK.')
		eprintln('If the SDK is working and writable, new platforms can be installed with:')
		eprintln('`$exe_name install "platforms;android-<API LEVEL>"`')
		eprintln('You can set a custom SDK with the ANDROID_SDK_ROOT env variable')
		if exit_on_error {
			exit(1)
		}
	}
	if opt.api_level != '' {
		// Set user requested API level
		if sdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			eprintln('Notice: The requested Android API level "$opt.api_level" is not available in the SDK.')
			eprintln('Notice: Falling back to default "$api_level"')
		}
	}
	if api_level.i16() < sdk.min_supported_api_level.i16() {
		eprintln('Android API level "$api_level" is less than the supported level ($sdk.min_supported_api_level).')
		eprintln('A vab compatible version can be installed with `$exe_name install "platforms;android-$sdk.min_supported_api_level"`')
		if exit_on_error {
			exit(1)
		}
	}

	opt.api_level = api_level

	// Validate NDK version
	mut ndk_version := ndk.default_version()
	if ndk_version == '' {
		eprintln('No Android NDK versions could be detected.')
		eprintln('If the SDK is working and writable, new NDK versions can be installed with:')
		eprintln('`$exe_name install "ndk;<NDK VERSION>"`')
		eprintln('The minimum supported NDK version is "$ndk.min_supported_version"')
		if exit_on_error {
			exit(1)
		}
	}
	if opt.ndk_version != '' {
		// Set user requested NDK version
		if ndk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and add install function
			eprintln('Android NDK version "$opt.ndk_version" could not be found.')
			eprintln('If the SDK is working and writable, new NDK versions can be installed with:')
			eprintln('`$exe_name install "ndk;<NDK VERSION>"`')
			eprintln('The minimum supported NDK version is "$ndk.min_supported_version"')
			eprintln('Falling back to default $ndk_version')
		}
	}

	opt.ndk_version = ndk_version

	// Resolve NDK vs. SDK available platforms
	min_ndk_api_level := ndk.min_api_available(opt.ndk_version)
	max_ndk_api_level := ndk.max_api_available(opt.ndk_version)
	if opt.api_level.i16() > max_ndk_api_level.i16()
		|| opt.api_level.i16() < min_ndk_api_level.i16() {
		if opt.api_level.i16() > max_ndk_api_level.i16() {
			eprintln('Notice: Falling back to API level "$max_ndk_api_level" (SDK API level $opt.api_level > highest NDK API level $max_ndk_api_level).')
			opt.api_level = max_ndk_api_level
		}
		if opt.api_level.i16() < min_ndk_api_level.i16() {
			if sdk.has_api(min_ndk_api_level) {
				eprintln('Notice: Falling back to API level "$min_ndk_api_level" (SDK API level $opt.api_level < lowest NDK API level $max_ndk_api_level).')
				opt.api_level = min_ndk_api_level
			}
		}
	}
}

fn ab_work_dir() string {
	return os.join_path(os.temp_dir(), 'v_sdl_android')
}

fn ab_commit_hash() string {
	mut hash := ''
	git_exe := os.find_abs_path_of_executable('git') or { '' }
	if git_exe != '' {
		mut git_cmd := 'git -C "$exe_dir" rev-parse --short HEAD'
		$if windows {
			git_cmd = 'git.exe -C "$exe_dir" rev-parse --short HEAD'
		}
		res := os.execute(git_cmd)
		if res.exit_code == 0 {
			hash = res.output
		}
	}
	return hash
}

fn version_full() string {
	return '$exe_version $exe_git_hash'
}

fn version() string {
	mut v := '0.0.0'
	// TODO
	//vmod := @VMOD_FILE
	vmod := 'version: 0.0.1'
	if vmod.len > 0 {
		if vmod.contains('version:') {
			v = vmod.all_after('version:').all_before('\n').replace("'", '').replace('"',
				'').trim(' ')
		}
	}
	return v
}

fn sdl_environment(config SDLConfig) !SDLEnv {
	err_sig := @MOD + '.' + @FN
	root := os.real_path(config.root)

	// Detect version - TODO FIXME
	version := os.file_name(config.root).all_after('SDL2-')

	src := os.join_path(root, 'src')

	collect_flat_ext := fn (path string, mut files []string, ext string) {
		ls := os.ls(path) or { panic(err) }
		for file in ls {
			if file.ends_with(ext) {
				files << os.join_path(path.trim_string_right(os.path_separator), file)
			}
		}
	}

	mut c_files := []string{}
	mut c_arm_files := []string{}
	mut cpp_files := []string{}

	// TODO test *all* versions
	if version != '2.0.20' {
		return error('$err_sig: TODO only 2.0.20 is currently supported (not "$version")')
	}

	if version in supported_sdl_versions {
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

		// Collect C files
		for collect_path in collect_paths {
			collect_flat_ext(collect_path, mut c_files, '.c')
		}

		c_arm_files << [
			os.join_path(src, 'atomic', 'SDL_atomic.c'),
			os.join_path(src, 'atomic', 'SDL_spinlock.c'),
		]

		//
		for collect_path in collect_cpp_paths {
			collect_flat_ext(collect_path, mut cpp_files, '.cpp')
		}
	} else {
		return error('Can not detect SDL environment for SDL version "version"')
	}

	return SDLEnv{
		version: version
		c_files: c_files
		c_arm_files: c_arm_files
		cpp_files: cpp_files
		src_path: src
		include_path: os.join_path(root, 'include')
	}
}

pub fn vab_compile(opt android.CompileOptions) ! {
	err_sig := @MOD + '.' + @FN

	android.compile(opt) or {} // Building the .so will fail

	build_dir := opt.build_directory()!
	sdl_build_dir := os.join_path(opt.work_dir, 'sdl_build')

	archs := opt.archs()!

	mut arch_cc := map[string]string{}
	mut arch_libs := map[string]string{}

	mut o_files := map[string][]string{}
	for arch in archs {
		compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			return error('$err_sig: failed getting NDK compiler.\n$err')
		}
		arch_cc[arch] = compiler

		arch_lib := ndk.libs_path(opt.ndk_version, arch, opt.api_level) or {
			return error('$err_sig: failed getting NDK libs path.\n$err')
		}
		arch_libs[arch] = arch_lib

		o_file_path := os.join_path(build_dir,'o',arch)
		o_ls := os.ls(o_file_path) or { []string{} }
		for f in o_ls {
			if f.ends_with('.o') {
				o_files[arch] << os.join_path(o_file_path, f)
			}
		}

	}

	mut jobs := []ShellJob{}

	// Cross compile .so lib files
	for arch in archs {

		//arch_o_dir := os.join_path(build_dir, 'o', arch)
		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir) or {}

		libsdl2_so_file := os.join_path(sdl_build_dir, 'lib', arch, 'libSDL2.so')

		//os.mkdir_all(arch_o_dir) or {
		//	panic('$err_sig: failed making directory "$arch_o_dir". $err')
		//}

		arch_o_files := o_files[arch].map('"$it"')

		mut args := []string{}
		args << '-Wl,-soname,libmain.so -shared '
		args << arch_o_files.join(' ')
		//args << "$arch_o_dir/sdl_${opt.lib_name}.o"
		args << '-lgcc -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_real.a -latomic -Wl,--exclude-libs,libatomic.a'
		args << libsdl2_so_file
		//args << arch_cflags[arch]
		args << '-no-canonical-prefixes -Wl,--build-id -stdlib=libstdc++ -Wl,--no-undefined -Wl,--fatal-warnings -lGLESv1_CM -lGLESv2 -llog -ldl -lc -lm'

		// Compile .so
		build_cmd := [
			arch_cc[arch]+'++',
			args.join(' '),
			'-o "$arch_lib_dir/lib${opt.lib_name}.so"'
		]

		jobs << ShellJob{
			cmd: build_cmd
		}
	}

	if opt.parallel {
		mut pp := pool.new_pool_processor(maxjobs: runtime.nr_cpus() - 1, callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results<ShellJobResult>() {
			util.verbosity_print_cmd(job_res.job.cmd, opt.verbosity)
			util.exit_on_bad_result(job_res.result, '${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				println(job_res.result.output)
			}
		}
	} else {
		for job in jobs {
			util.verbosity_print_cmd(job.cmd, opt.verbosity)
			job_res := sync_run(job)
			util.exit_on_bad_result(job_res.result, '${job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				println(job_res.result.output)
			}
		}
	}

	if 'armeabi-v7a' in archs {
		// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
		armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
		os.mkdir_all(armeabi_lib_dir) or {
			return error('$err_sig: failed making directory "$armeabi_lib_dir".\n$err')
		}

		armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'lib${opt.lib_name}.so')
		armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.lib_name}.so')
		os.cp(armeabi_lib_src, armeabi_lib_dst) or {
			return error('$err_sig: failed copying "$armeabi_lib_src" to "$armeabi_lib_dst".\n$err')
		}
	}
}
