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
	// For individual architectures / compilers
	mut cflags_arm32 := []string{}
	mut cflags_arm64 := []string{}
	mut cflags_x86 := []string{}
	mut cflags_x86_64 := []string{}

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
	mut archs := []string{}
	if opt.archs.len > 0 {
		for arch in opt.archs {
			if arch in android.default_archs {
				archs << arch.trim_space()
			} else {
				eprintln('Architechture "$arch" not one of $android.default_archs')
			}
		}
	}
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
			'-target ' + compiler_target_quadruple(arch) + opt.min_sdk_version.str(),
		]
		if arch == 'armeabi-v7a' {
			arch_cflags[arch] << ['-march=armv7-a']
		}
	}

	// TODO these are currently unused
	arch_cflags['arm64-v8a'] << cflags_arm64
	arch_cflags['armeabi-v7a'] << cflags_arm32
	arch_cflags['x86'] << cflags_x86
	arch_cflags['x86_64'] << cflags_x86_64

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
	if keystore.path == '' {
		keystore.path = os.join_path(opt.work_dir, 'debug.keystore') // TODO
	}
	keystore = android.resolve_keystore(keystore, opt.verbosity) !

	mut c_flags := opt.c_flags
	c_flags << '-I"'+os.join_path(opt.sdl_config.root,'include')+'"'
	c_flags << '-UNDEBUG'
	c_flags << '-D_FORTIFY_SOURCE=2'
	c_flags << ['-Wno-pointer-to-int-cast', '-Wno-constant-conversion', '-Wno-literal-conversion','-Wno-deprecated-declarations']
	//c_flags << '-mthumb'

	compile_cache_key := if os.is_dir(opt.input) /*|| input_ext == '.v'*/ { opt.input } else { '' }
	comp_opt := android.CompileOptions{
		verbosity: opt.verbosity
		cache: false //opt.cache
		cache_key: compile_cache_key
		parallel: opt.parallel
		is_prod: opt.is_prod
		no_printf_hijack: false
		// v_flags: opt.v_flags
		c_flags: c_flags
		archs: opt.archs.filter(it.trim(' ') != '')
		work_dir: opt.work_dir
		input: opt.input
		ndk_version: opt.ndk_version
		lib_name: 'main' //opt.lib_name
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
	}
	vab_compile_clone(comp_opt) or {
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
		build_tools: '27.0.3' // TODO: try using aapt2 from the SDK (not the aab required one) '24.0.3' // '29.0.3'//opt.build_tools
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
	// Validate API level
	mut api_level := sdk.default_api_level
	if opt.api_level != '' {
		if sdk.has_api(opt.api_level) {
			api_level = opt.api_level
		} else {
			// TODO Warnings
			eprintln('Android API level "$opt.api_level" is not available in SDK.')
			eprintln('Falling back to default "$api_level"')
		}
	}
	if api_level == '' {
		eprintln('Android API level "$opt.api_level" is not available in SDK.')
		eprintln('It can be installed with `$exe_name install "platforms;android-<API LEVEL>"`')
		if exit_on_error {
			exit(1)
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
	if opt.ndk_version != '' {
		if ndk.has_version(opt.ndk_version) {
			ndk_version = opt.ndk_version
		} else {
			// TODO FIX Warnings and add install function
			eprintln('Android NDK version $opt.ndk_version is not available.')
			// eprintln('(It can be installed with `$exe_name install "ndk;${opt.build_tools}"`)')
			eprintln('Falling back to default $ndk_version')
		}
	}
	if ndk_version == '' {
		eprintln('Android NDK version $opt.ndk_version is not available.')
		// eprintln('It can be installed with `$exe_name install android-api-${opt.api_level}`')
		if exit_on_error {
			exit(1)
		}
	}

	opt.ndk_version = ndk_version
}

fn ab_work_dir() string {
	return os.join_path(os.temp_dir(), 'v_sdl_android_build')
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

	// Detect version - TODO fixme
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

fn compiler_target_quadruple(arch string) string {
	mut eabi := ''
	mut arch_is := ndk.arch_to_instruction_set(arch)
	if arch == 'armeabi-v7a' {
		eabi = 'eabi'
		arch_is = 'armv7'
	}
	return arch_is + '-none-linux-android$eabi'
}


// TODO make generic enough to put it in vab??!
pub fn vab_compile_clone(opt android.CompileOptions) ! {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		return error('$err_sig: failed making directory "$opt.work_dir". $err')
	}
	build_dir := os.join_path(opt.work_dir, 'build')
	mut jobs := []ShellJob{}

	if opt.verbosity > 0 {
		println('Compiling V to C' + if opt.parallel { ' in parallel' } else { '' })
		if opt.v_flags.len > 0 {
			println('V flags: `$opt.v_flags`')
		}
	}
	vexe := vxt.vexe()
	v_output_file := os.join_path(opt.work_dir, 'v_android.c')

	// Dump modules and C flags to files
	v_cflags_file := os.join_path(opt.work_dir, 'v.cflags')
	os.rm(v_cflags_file) or {}
	v_dump_modules_file := os.join_path(opt.work_dir, 'v.modules')
	os.rm(v_dump_modules_file) or {}

	mut v_cmd := [vexe]
	if !opt.cache {
		v_cmd << '-nocache'
	}

	v_cmd << opt.v_flags
	v_cmd << [
		'-os android',
		'-gc none',
		'-cc clang',
		'-cmain SDL_main',
		'-dump-modules "$v_dump_modules_file"',
		'-dump-c-flags "$v_cflags_file"',
		//'-apk',
	]
	v_cmd << opt.input

	// NOTE this command fails with a C compile error but the output we need is still
	// present... Yes - not exactly pretty.
	// VCROSS_COMPILER_NAME is needed (on at least Windows)
	jobs << ShellJob{
		env_vars: {
			'VCROSS_COMPILER_NAME': ndk.compiler(.c, opt.ndk_version, 'arm64-v8a', opt.api_level) or {
				''
			}
		}
		cmd: v_cmd.clone()
	}

	// Compile to Android compatible C file
	v_cmd = [vexe]
	if !opt.cache {
		v_cmd << '-nocache'
	}
	v_cmd << opt.v_flags
	v_cmd << [
		'-os android',
		'-gc none',
		'-cmain SDL_main',
		'-os android',
		//'-apk',
		'-o "$v_output_file"',
	]
	v_cmd << opt.input
	jobs << ShellJob{
		cmd: v_cmd.clone()
	}

	if opt.parallel {
		mut pp := pool.new_pool_processor(maxjobs: runtime.nr_cpus() - 1, callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results<ShellJobResult>() {
			util.verbosity_print_cmd(job_res.job.cmd, opt.verbosity)
			if '-cc clang' !in job_res.job.cmd {
				util.exit_on_bad_result(job_res.result, '${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
				if opt.verbosity > 2 {
					println(job_res.result.output)
				}
			}
		}
	} else {
		for job in jobs {
			util.verbosity_print_cmd(job.cmd, opt.verbosity)
			job_res := sync_run(job)
			if '-cc clang' !in job_res.job.cmd {
				util.exit_on_bad_result(job_res.result, '${job.cmd[0]} failed with return code $job_res.result.exit_code')
				if opt.verbosity > 2 {
					println(job_res.result.output)
				}
			}
		}
	}
	jobs.clear()

	// Parse imported modules from dump
	mut imported_modules := os.read_file(v_dump_modules_file) or {
		return error('$err_sig: failed reading module dump file "$v_dump_modules_file". $err')
	}.split('\n').filter(it != '')
	imported_modules.sort()
	if opt.verbosity > 2 {
		println('Imported modules: $imported_modules')
	}
	if imported_modules.len == 0 {
		return error('$err_sig: empty module dump file "$v_dump_modules_file".')
	}

	/*
	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	if opt.cache && os.exists(build_dir) && os.exists(v_output_file) {
		mut bytes := os.read_bytes(v_output_file) or {
			return error('$err_sig: failed reading "$v_output_file". $err')
		}
		bytes << '$opt.str()-$opt.cache_key'.bytes()
		hash = md5.sum(bytes).hex()

		if os.exists(hash_file) {
			prev_hash := os.read_file(hash_file) or { '' }
			if hash == prev_hash {
				if opt.verbosity > 1 {
					println('Skipping compile. Hashes match $hash')
				}
				return true
			}
		}
	}

	if hash != '' && os.exists(v_output_file) {
		if opt.verbosity > 2 {
			println('Writing new hash $hash')
		}
		os.rm(hash_file) or {}
		mut hash_fh := os.open_file(hash_file, 'w+', 0o700) or {
			return error('$err_sig: failed opening "$hash_file". $err')
		}
		hash_fh.write(hash.bytes()) or { return error('$err_sig: failed writing to "$hash_file". $err') }
		hash_fh.close()
	}
	*/

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or {}
	}
	os.mkdir(build_dir) or { return error('$err_sig: $err') }

	v_home := vxt.home()

	mut archs := []string{}
	if opt.archs.len > 0 {
		for a in opt.archs {
			if a in android.default_archs {
				archs << a.trim_space()
			} else {
				eprintln('Architechture "$a" not one of $android.default_archs')
			}
		}
	}
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = android.default_archs.clone()
	}

	// For all compilers
	mut cflags := opt.c_flags
	mut includes := []string{}
	mut defines := []string{}
	mut ldflags := []string{}
	mut sources := []string{}

	// Read in the dumped cflags
	vcflags := os.read_file(v_cflags_file) or {
		return error('$err_sig: failed reading C flags to "$v_cflags_file". $err')
	}
	for line in vcflags.split('\n') {
		if line.contains('.tmp.c') || line.ends_with('.o"') {
			continue
		}
		if line.starts_with('-D') {
			defines << line
		}
		if line.starts_with('-I') {
			if line.contains('/usr/') {
				continue
			}
			includes << line
		}
		if line.starts_with('-l') {
			if line.contains('-lgc') {
				continue
			}
			ldflags << line
		}
	}

	// ... still a bit of a mess
	if opt.is_prod {
		cflags << ['-Os']
	} else {
		cflags << ['-O0']
	}
	cflags << ['-fPIC', '-fvisibility=hidden', '-ffunction-sections', '-fdata-sections',
		'-ferror-limit=1']

	cflags << ['-Wall', '-Wextra', '-Wno-unused-variable', '-Wno-unused-parameter',
		'-Wno-unused-result', '-Wno-unused-function', '-Wno-missing-braces', '-Wno-unused-label',
		'-Werror=implicit-function-declaration']

	// TODO Here to make the compiler(s) shut up :/
	cflags << ['-Wno-braced-scalar-init', '-Wno-incompatible-pointer-types',
		'-Wno-implicitly-unsigned-literal', '-Wno-pointer-sign', '-Wno-enum-conversion',
		'-Wno-int-conversion', '-Wno-int-to-pointer-cast', '-Wno-sign-compare', '-Wno-return-type',
		'-Wno-extra-tokens', '-Wno-unused-value']

	// NOTE This define allows V to redefine C's printf() - to let logging via println() etc. go
	// through Android device's system log (that adb logcat reads).
	if !opt.no_printf_hijack {
		if opt.verbosity > 1 {
			println('Define V_ANDROID_LOG_PRINT - (f)printf will be redefined...')
		}
		defines << '-DV_ANDROID_LOG_PRINT'
	}

	defines << '-DAPPNAME="$opt.lib_name"'
	defines << ['-DANDROID', '-D__ANDROID__', '-DANDROIDVERSION=$opt.api_level']

	// TODO if full_screen
	// defines << '-DANDROID_FULLSCREEN'

	// Include NDK headers
	// NOTE "$ndk_root/sysroot/usr/include" was deprecated since NDK r19
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('$err_sig: getting NDK sysroot path. $err')
	}
	includes << ['-I"' + os.join_path(ndk_sysroot, 'usr', 'include') + '"',
		'-I"' + os.join_path(ndk_sysroot, 'usr', 'include', 'android') + '"']

	is_debug_build := '-cg' in opt.v_flags || '-g' in opt.v_flags

	// Boehm-Demers-Weiser Garbage Collector (bdwgc / libgc)
	/*
	mut uses_gc := true // V default
	for v_flag in opt.v_flags {
		if v_flag.starts_with('-gc') {
			if v_flag.ends_with('none') {
				uses_gc = false
			}
			if opt.verbosity > 1 {
				println('Garbage collecting is $uses_gc via "$v_flag"')
			}
			break
		}
	}

	if uses_gc {
		includes << [
			'-I"' + os.join_path(v_home, 'thirdparty', 'libgc', 'include') + '"',
		]
		sources << ['"' + os.join_path(v_home, 'thirdparty', 'libgc', 'gc.c') + '"']
		if is_debug_build {
			defines << '-DGC_ASSERTIONS'
			defines << '-DGC_ANDROID_LOG'
		}
		defines << '-D_REENTRANT'
		defines << '-DUSE_MMAP' // Will otherwise crash with a message with a path to the lib in GC_unix_mmap_get_mem+528
	}

	// stb_image via `stbi` module
	if 'stbi' in imported_modules {
		if opt.verbosity > 1 {
			println('Including stb_image via stbi module')
		}
		// includes << ['-I"$v_home/thirdparty/stb_image"']
		sources << [
			'"' + os.join_path(v_home, 'thirdparty', 'stb_image', 'stbi.c') + '"',
		]
	}*/

	// cJson via `json` module
	if 'json' in imported_modules {
		if opt.verbosity > 1 {
			println('Including cJSON via json module')
		}
		includes << ['-I"' + os.join_path(v_home, 'thirdparty', 'cJSON') + '"']
		sources << [
			'"' + os.join_path(v_home, 'thirdparty', 'cJSON', 'cJSON.c') + '"',
		]
	}

	// misc
	ldflags << ['-llog', '-landroid', '-lm']

	ldflags << ['-lGLESv1_CM','-lGLESv2','-ldl','-lc']

	ldflags << ['-shared'] // <- Android loads native code via a library in NativeActivity

	mut cflags_arm64 := []string{}//['-m64']
	mut cflags_arm32 := []string{}//['-mfloat-abi=softfp', '-m32']
	mut cflags_x86 := []string{}//['-march=i686', '-mssse3', '-mfpmath=sse', '-m32']
	mut cflags_x86_64 := []string{}//['-march=x86-64', '-msse4.2', '-mpopcnt', '-m64']

	mut arch_cc := map[string]string{}
	mut arch_libs := map[string]string{}
	for arch in archs {
		compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			return error('$err_sig: failed getting NDK compiler. $err')
		}
		arch_cc[arch] = compiler

		arch_lib := ndk.libs_path(opt.ndk_version, arch, opt.api_level) or {
			return error('$err_sig: failed getting NDK libs path. $err')
		}
		arch_libs[arch] = arch_lib
	}

	mut arch_cflags := map[string][]string{}
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	if opt.verbosity > 0 {
		println('Compiling C to $archs' + if opt.parallel { ' in parallel' } else { '' })
	}

	for arch in archs {
		arch_cflags[arch] << [
			'-target ' + compiler_target_quadruple(arch) + opt.min_sdk_version.str()
		]
		if arch == 'armeabi-v7a' {
			arch_cflags[arch] << ['-march=armv7-a']
		}
	}

	// TODO compile one .c source at the time
	// sources << '"'+v_output_file+'"'

	// Cross compile .so lib files
	for arch in archs {
		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir) or {
			return error('$err_sig: failed making directory "$arch_lib_dir". $err')
		}

		// Compile .o
		build_cmd := [
			arch_cc[arch], cflags.join(' '), includes.join(' '),
			defines.join(' '), sources.join(' '), arch_cflags[arch].join(' '),
			'-c "$v_output_file"',
			'-o "$arch_lib_dir/sdl_${opt.lib_name}.o"',
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
	jobs.clear()

	sdl_build_dir := os.join_path(opt.work_dir, 'sdl_build')

	// Cross compile .so lib files
	for arch in archs {

		arch_lib_dir := os.join_path(build_dir, 'lib', arch)

		libsdl2_so_file := os.join_path(sdl_build_dir, 'lib', arch, 'libSDL2.so')


		//os.mkdir_all(arch_lib_dir) or {
		//	panic('$err_sig: failed making directory "$arch_lib_dir". $err')
		//}

		mut args := []string{}
		args << '-Wl,-soname,libmain.so -shared '
		args << "$arch_lib_dir/sdl_${opt.lib_name}.o"
		args << '-lgcc -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_real.a -latomic -Wl,--exclude-libs,libatomic.a'
		args << libsdl2_so_file
		args << arch_cflags[arch]
		args << '-no-canonical-prefixes -Wl,--build-id -stdlib=libstdc++ -Wl,--no-undefined -Wl,--fatal-warnings -lGLESv1_CM -lGLESv2 -llog -ldl -lc -lm'
		// Compile .o

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
			return error('$err_sig: failed making directory "$armeabi_lib_dir". $err')
		}

		armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'lib${opt.lib_name}.so')
		armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.lib_name}.so')
		os.cp(armeabi_lib_src, armeabi_lib_dst) or {
			return error('$err_sig: failed copying "$armeabi_lib_src" to "$armeabi_lib_dst". $err')
		}
	}
}
