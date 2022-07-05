#!/usr/bin/env -S v

module main

// import semver
import vab.vxt
// import vab.java
import os
import flag
import runtime
import sync.pool
// import crypto.md5
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
	cache_directory        = ab_cache_dir()
	accepted_input_files   = ['.v', '.apk', '.aab']
	supported_sdl_versions = ['2.0.8', '2.0.9', '2.0.10', '2.0.12', '2.0.14', '2.0.16', '2.0.18',
		'2.0.20', '2.0.22']
)

struct Options {
	// Internals
	verbosity int
	work_dir  string = work_directory
	//
	parallel       bool = true // Run, what can be run, in parallel
	cache          bool = true
	// Build specifics
	c_flags   []string // flags passed to the C compiler(s)
	v_flags   []string // flags passed to the V compiler
	archs     []string
	show_help bool
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

struct SDLCompileOptions {
pub mut:
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
	v_flags   []string // flags passed to the V compiler
	ndk_version     string   // version of the Android NDK to compile against
	api_level       string   // Android API level to use when compiling
	min_sdk_version int
	//
	env SDLEnv
}

// build_directory returns a valid build directory.
pub fn (opt SDLCompileOptions) build_directory() string {
	return os.join_path(opt.work_dir, 'sdl','build',opt.env.version.replace('.',''))
}

// archs returns an array of target architectures.
pub fn (opt SDLCompileOptions) archs() ![]string {
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
	config SDLConfig
	version      string
	includes     map[string]map[string][]string // .includes['libSDL2'][arch] << h_file
	sources      map[string]map[string]map[string][]string // .sources['libSDL2'][arch]['c'] << c_file
	c_flags      map[string]map[string][]string // .c_flags['libSDL2'][arch] << '-DEFINE'
	ld_flags     map[string]map[string][]string // .ld_flags['libSDL2'][arch] << '-ldl'
}

struct SDLMixerFeatures {
pub:
	flac bool = true // if you want to support loading FLAC music with libFLAC
	ogg bool // TODO = true // if you want to support loading OGG Vorbis music via Tremor
	mp3_mpg123 bool = true // if you want to support loading MP3 music via MPG123
	mod_modplug bool = true // if you want to support loading MOD music via modplug
	mid_timidity bool // TODO = true // if you want to support TiMidity
}

struct SDLMixerCompileOptions {
pub:
	//
	sdl_opt SDLCompileOptions
	env SDLMixerEnv
}

struct SDLMixerConfig {
	features SDLMixerFeatures
	root string
}

struct SDLMixerEnv {
	config  SDLMixerConfig
	version      string
	includes     map[string]map[string][]string // .includes['libSDL2'][arch] << h_file
	sources      map[string]map[string]map[string][]string // .sources['libSDL2'][arch]['c'] << c_file
	c_flags      map[string]map[string][]string // .c_flags['libSDL2'][arch] << '-DEFINE'
	ld_flags     map[string]map[string][]string // .ld_flags['libSDL2'][arch] << '-ldl'
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

fn run_jobs(jobs []ShellJob, parallel bool, verbosity int) ! {
	if parallel {
		mut pp := pool.new_pool_processor(callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results<ShellJobResult>() {
			util.verbosity_print_cmd(job_res.job.cmd, verbosity)
			if verbosity > 2 {
				println('$job_res.result.output')
			}
			if job_res.result.exit_code != 0 {
				return error('${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
			}
		}
	} else {
		for job in jobs {
			util.verbosity_print_cmd(job.cmd, verbosity)
			job_res := sync_run(job)
			if verbosity > 2 {
				println('$job_res.result.output')
			}
			if job_res.result.exit_code != 0 {
				return error('${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
			}
		}
	}
}

fn main() {
	mut opt := Options{}
	mut fp := &flag.FlagParser(0)

	opt, fp = args_to_options(os.args, opt) or {
		eprintln('Error while parsing `os.args`: $err')
		exit(1)
	}

	if opt.show_help {
		println(fp.usage())
		exit(0)
	}

	input := fp.args[fp.args.len - 1]
	/*
	input_ext := os.file_ext(input)
	if !(os.is_dir(input) || input_ext in accepted_input_files) {
		eprintln('$exe_name requires input to be a V file, an APK, AAB or a directory containing V sources')
		exit(1)
	}*/
	opt.input = input

	resolve_options(mut opt, true)

	if opt.verbosity > 0 {
		println('Analyzing V source')
		if opt.v_flags.len > 0 {
			println('V flags: `$opt.v_flags`')
		}
	}

	mut v_flags := opt.v_flags.clone()
	v_meta_opt := android.VCompileOptions{
		verbosity: opt.verbosity
		cache: opt.cache
		flags: v_flags
		work_dir: os.join_path(opt.work_dir, 'v')
		input: opt.input
	}

	v_meta_dump := android.v_dump_meta(v_meta_opt) or { panic(err) }
	imported_modules := v_meta_dump.imports
	if 'sdl' !in imported_modules {
		eprintln('Error: v project "$opt.input" does not import `sdl`')
		exit(1)
	}

	// TODO detect sdl module + SDL2 version -> download sources -> build -> $$$Profit
	// v_sdl_path := detect_v_sdl_module_path()
	vmodules_path := vxt.vmodules() or { panic(err) }
	sdl_module_home := os.join_path(vmodules_path, 'sdl')
	if !os.is_dir(sdl_module_home) {
		panic(@MOD + '.' + @FN +
			': could not locate `vlang/sdl` module. It can be installed by running `v install sdl`')
	}
	sdl_home := os.getenv('SDL_HOME')
	if !os.is_dir(sdl_home) {
		panic(@MOD + '.' + @FN + ': could not locate SDL install at "$sdl_home"')
	}

	sdl_env := sdl_environment(root: sdl_home)!
	if opt.verbosity > 3 {
		eprintln('SDL environment:\n$sdl_env')
	}

	mut sdl_comp_opt := SDLCompileOptions{
		verbosity: opt.verbosity
		cache: opt.cache
		is_prod: opt.is_prod
		c_flags: opt.c_flags
		v_flags: v_flags
		archs: opt.archs
		work_dir: opt.work_dir
		input: opt.input
		ndk_version: opt.ndk_version
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
		env: sdl_env
	}

	compile_sdl(sdl_comp_opt) or { panic(err) }

	if 'sdl.mixer' in imported_modules {
		// TODO can be auto detected
		sdl_mixer_home := os.getenv('SDL_MIXER_HOME')
		if !os.is_dir(sdl_mixer_home) {
			panic(@MOD + '.' + @FN + ': could not locate SDL Mixer install at "$sdl_mixer_home"')
		}
		mix_env := sdl_mixer_environment(root: sdl_mixer_home)!
		compile_sdl_mixer(env: mix_env, sdl_opt: sdl_comp_opt) or { panic(err) }

		// TODO
		sdl_comp_opt.cache = false
		sdl_comp_opt.c_flags << '-I"'+mix_env.includes['libSDL2_mixer']['arm64-v8a'][0]+'"' // TODO
		//println('DER $sdl_comp_opt.c_flags mix_env.includes')
	}
	/*
	// TODO
	if 'sdl.image' in imported_modules {
		compile_sdl_image(sdl_comp_opt) or { panic(err) }
	}
	if 'sdl.ttf' in imported_modules {
		compile_sdl_ttf(sdl_comp_opt) or { panic(err) }
	}*/

	compile_v_code(sdl_comp_opt) or { panic(err) }
}

fn compile_sdl(opt SDLCompileOptions) ! {
	err_sig := @MOD + '.' + @FN

	sdl_env := opt.env

	// ndk_root := ndk.root_version(opt.ndk_version)
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('$err_sig: getting NDK sysroot path. $err')
	}

	build_dir := opt.build_directory()

	is_prod_build := opt.is_prod
	is_debug_build := !is_prod_build

	// TODO better caching, can fail if execution is aborted, new archs added etc.
	if opt.cache && os.exists(build_dir) {
		if opt.verbosity > 0 {
			eprintln('Using cached SDL at "$build_dir"')
		}
		return
	}

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or {
			return error('$err_sig: failed removing previous build directory "$build_dir". $err')
		}
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
		defines << ['-DNDEBUG']
	} else {
		cflags << ['-O0']
		cflags << ['-g']
		defines << ['-UNDEBUG']
	}

	// Resolve what architectures to compile for
	mut archs := opt.archs()!
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = android.default_archs.clone()
	}
	if opt.verbosity > 0 {
		eprintln('Compiling SDL to $archs' + if opt.parallel { ' in parallel' } else { '' })
	}

	if opt.verbosity > 3 {
		cflags << ['-v'] // Verbose clang
	}

	cflags << ['-fno-limit-debug-info', '-fdata-sections', '-ffunction-sections',
			'-fstack-protector-strong', '-funwind-tables', '-no-canonical-prefixes']

	cflags << ['--sysroot "$ndk_sysroot"']

	// TODO Unfixed NDK/Gradle (?)
	cflags << ['-Wno-invalid-command-line-argument', '-Wno-unused-command-line-argument']

	cflags << ['-fPIC']
	// '-mthumb' except for SDL_atomic.c / SDL_spinlock.c

	defines << ['-D_FORTIFY_SOURCE=2']
	defines << ['-DANDROID']

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
			arch_cflags[arch] << ['-march=armv7-a -mthumb']
		}
	}

	// TODO clean up this mess
	mut cpufeatures_c_args := []string{}
	cpufeatures_c_args << ['-fno-limit-debug-info', '-fdata-sections', '-ffunction-sections',
			'-fstack-protector-strong', '-funwind-tables', '-no-canonical-prefixes']
	cpufeatures_c_args << ['-g']
	// DEBUG builds
	if is_debug_build {
		cpufeatures_c_args << ['-UNDEBUG']
	}
	cpufeatures_c_args << ['--sysroot "$ndk_sysroot"']
	// Unfixed NDK
	cpufeatures_c_args << ['-Wno-invalid-command-line-argument', '-Wno-unused-command-line-argument']
	// Defaults
	cpufeatures_c_args << ['-Wall', '-Wextra', '-Werror', '-Wformat', '-Werror=format-security']
	cpufeatures_c_args << ['-D_FORTIFY_SOURCE=2']
	cpufeatures_c_args << ['-fPIC']
	cpufeatures_c_args << ['-I"$ndk_cpu_features_path"']

	// Cross compile each .c/.cpp to .o
	mut jobs := []ShellJob{}
	mut o_files := map[string][]string{}
	mut a_files := map[string][]string{}

	libs := sdl_env.sources.keys()
	for lib in libs {
		lib_includes := sdl_env.includes[lib].clone()
		lib_sources := sdl_env.sources[lib].clone()
		lib_c_flags := sdl_env.c_flags[lib].clone()
		for arch in archs {
			// Setup work directories
			arch_lib_dir := os.join_path(build_dir, 'lib', arch)
			os.mkdir_all(arch_lib_dir) or {
				return error('$err_sig: failed making directory "$arch_lib_dir". $err')
			}

			arch_o_dir := os.join_path(build_dir, 'o', arch)
			os.rmdir_all(arch_o_dir) or {}
			os.mkdir_all(arch_o_dir) or {
				return error('$err_sig: failed making directory "$arch_o_dir". $err')
			}

			arch_ndk_tmp_dir := os.join_path(build_dir, 'tmp', 'ndk', arch)
			os.mkdir_all(arch_ndk_tmp_dir) or {
				return error('$err_sig: failed making directory "arch_ndk_tmp_dir". $err')
			}

			// Start collecting flags, files etc.

			// Compile cpu-features
			// cpu-features.c -> cpu-features.o -> cpu-features.a
			cpufeatures_source_file := os.join_path(ndk_cpu_features_path, 'cpu-features.c')
			cpufeatures_o_file := os.join_path(arch_o_dir,
				os.file_name(cpufeatures_source_file).all_before_last('.') + '.o')
			cpufeatures_a_file := os.join_path(arch_lib_dir, 'libcpufeatures.a')
			if opt.verbosity > 2 {
				mut thumb := if arch == 'armeabi-7va' { '(thumb)' } else { '' }
				eprintln('Compiling for $arch $thumb NDK cpu-features "${os.file_name(cpufeatures_source_file)}"')
			}

			mut cpufeatures_m_cflags := []string{}
			//if is_debug_build {
				cpufeatures_m_cflags << ['-MMD', '-MP'] //, '-MF <tmp path to SDL_<name>.o.d>']
				cpufeatures_m_cflags << '-MF"' +
					os.join_path(arch_ndk_tmp_dir, os.file_name(cpufeatures_source_file).all_before_last('.') +
					'.o.d"')
			//}

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
			cpufeatures_comp_res := util.run_or_error(cpufeatures_build_cmd)!
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
			for c_file in lib_sources[arch]['c'] {
				source_file := c_file
				object_file := os.join_path(arch_o_dir,
					os.file_name(source_file).all_before_last('.') + '.o')
				o_files[arch] << object_file

				mut m_cflags := []string{}
				//if is_debug_build {
					m_cflags << ['-MMD', '-MP'] //, '-MF <tmp path to SDL_<name>.o.d>']
					m_cflags << '-MF"' +
						os.join_path(arch_o_dir, os.file_name(source_file).all_before_last('.') +
						'.o.d"')
				//}

				build_cmd := [
					arch_cc[arch],
					m_cflags.join(' '),
					arch_cflags[arch].join(' '),
					lib_c_flags[arch].join(' ')
					cflags.join(' '),
					lib_includes[arch].map('-I"$it"').join(' ')
					includes.join(' '),
					defines.join(' '),
					'-c "$source_file"',
					'-o "$object_file"',
				]

				jobs << ShellJob{
					std_err: if opt.verbosity > 2 {
						mut thumb := if arch == 'armeabi-7va' { '(thumb)' } else { '' }
						'Compiling for $arch $thumb C SDL file "${os.file_name(c_file)}"'
					} else {
						''
					}
					cmd: build_cmd
				}
			}

			// Compile (without thumb) C files to object files
			for c_arm_file in lib_sources[arch]['c.arm'] {
				source_file := c_arm_file
				object_file := os.join_path(arch_o_dir,
					os.file_name(source_file).all_before_last('.') + '.o')
				o_files[arch] << object_file

				mut m_cflags := []string{}
				if is_debug_build {
					m_cflags << ['-MMD', '-MP']
					m_cflags << '-MF"' +
						os.join_path(arch_o_dir, os.file_name(source_file).all_before_last('.') +
						'.o.d"')
				}

				build_cmd := [
					arch_cc[arch],
					m_cflags.join(' '),
					arch_cflags[arch].join(' '),
					lib_c_flags[arch].join(' ')
					cflags.join(' '),
					lib_includes[arch].map('-I"$it"').join(' ')
					includes.join(' '),
					defines.join(' '),
					'-c "$source_file"',
					'-o "$object_file"',
				]

				jobs << ShellJob{
					std_err: if opt.verbosity > 2 {
						'Compiling for $arch (arm)   C SDL file "${os.file_name(c_arm_file)}"'
					} else {
						''
					}
					cmd: build_cmd
				}
			}

			// Compile C++ files to object files
			for cpp_file in lib_sources[arch]['cpp'] {
				source_file := cpp_file
				object_file := os.join_path(arch_o_dir,
					os.file_name(source_file).all_before_last('.') + '.o')
				o_files[arch] << object_file

				mut m_cflags := []string{}
				if is_debug_build {
					m_cflags << ['-MMD', '-MP']
					m_cflags << '-MF"' +
						os.join_path(arch_o_dir, os.file_name(source_file).all_before_last('.') +
						'.o.d"')
				}

				build_cmd := [
					arch_cc_cpp[arch],
					arch_cflags[arch].join(' '),
					m_cflags.join(' '),
					cppflags.join(' '),
					lib_c_flags[arch].join(' ')
					cflags.join(' '),
					lib_includes[arch].map('-I"$it"').join(' ')
					includes.join(' '),
					defines.join(' '),
					'-c "$source_file"',
					'-o "$object_file"',
				]

				jobs << ShellJob{
					std_err: if opt.verbosity > 2 {
						mut thumb := if arch == 'armeabi-7va' { '(thumb)' } else { '' }
						'Compiling for $arch $thumb C++ SDL file "${os.file_name(cpp_file)}"'
					} else {
						''
					}
					cmd: build_cmd
				}
			}
		}
	}
	run_jobs(jobs,opt.parallel,opt.verbosity) !
	jobs.clear()

	// libSDL2.so linker flags
	mut ldflags := []string{}
	ldflags << ['-lc', '-lm']


	for lib in libs {
		lib_ld_flags := sdl_env.ld_flags[lib].clone()
		for arch in archs {
			arch_lib_dir := os.join_path(build_dir, 'lib', arch)

			lib_so_file := os.join_path(arch_lib_dir, '${lib}.so')
			// Finally, build libSDL2.so
			build_so_cmd := [
				arch_cc_cpp[arch],
				'-Wl,-soname,${lib}.so -shared',
				o_files[arch].map('"$it"').join(' '), // <ALL .o files produced above except cpu-features>
				a_files[arch].map('"$it"').join(' '), // <path to>/libcpufeatures.a
				'-lgcc -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_real.a -latomic -Wl,--exclude-libs,libatomic.a',
				//arch_cflags[arch].join(' '),
				'-no-canonical-prefixes',
				'-Wl,--build-id',
				'-stdlib=libstdc++',
				'-Wl,--no-undefined',
				'-Wl,--fatal-warnings',
				lib_ld_flags[arch].join(' ')
				ldflags.join(' '),
				'-o "$lib_so_file"',
			]

			jobs << ShellJob{
				std_err: if opt.verbosity > 1 { 'Compiling libSDL2.so for $arch' } else { '' }
				cmd: build_so_cmd
			}
		}
	}

	run_jobs(jobs,opt.parallel,opt.verbosity) !

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

fn compile_sdl_mixer(mix_opt SDLMixerCompileOptions) ! {
	err_sig := @MOD + '.' + @FN

	opt := mix_opt.sdl_opt
	sdl_env := opt.env
	// ndk_root := ndk.root_version(opt.ndk_version)
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('$err_sig: getting NDK sysroot path. $err')
	}

	sdl_build_dir := os.join_path(opt.build_directory())
	build_dir := os.join_path(opt.build_directory(),'mixer')

	is_prod_build := opt.is_prod
	is_debug_build := !is_prod_build

	// TODO better caching, can fail if execution is aborted etc.
	/*if opt.cache && os.exists(build_dir) {
		if opt.verbosity > 0 {
			eprintln('Using cached SDL Mixer at "$build_dir"')
		}
		return
	}*/

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or {
			return error('$err_sig: failed removing previous build directory "$build_dir". $err')
		}
	}
	os.mkdir_all(build_dir) or {
		return error('$err_sig: failed making directory "$build_dir". $err')
	}

	// Resolve compiler flags
	// For all C compilers
	mut cflags := opt.c_flags

	// For all compilers
	mut includes := []string{}
	mut defines := []string{}

	if opt.is_prod {
		cflags << ['-Os']
		defines << ['-UNDEBUG']
	} else {
		cflags << ['-O0']
		cflags << ['-g']
		defines << ['-UNDEBUG']
	}

	// Resolve what architectures to compile for
	mut archs := opt.archs()!
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = android.default_archs.clone()
	}
	if opt.verbosity > 0 {
		eprintln('Compiling SDL Mixer to $archs' + if opt.parallel { ' in parallel' } else { '' })
	}

	if opt.verbosity > 3 {
		cflags << ['-v'] // Verbose clang
	}

	cflags << ['-fno-limit-debug-info', '-fdata-sections', '-ffunction-sections',
			'-fstack-protector-strong', '-funwind-tables', '-no-canonical-prefixes']

	cflags << ['--sysroot "$ndk_sysroot"']

	// Defaults
	cflags << ['-Wall', '-Wextra', '-Wformat', '-Werror=format-security']

	// TODO Unfixed NDK/Gradle (?)
	cflags << ['-Wno-invalid-command-line-argument', '-Wno-unused-command-line-argument']

	// SDL/JNI specifics that aren't fixed yet
	cflags << ['-Wno-unused-parameter', '-Wno-sign-compare']

	cflags << ['-fPIC']
	// '-mthumb' except for SDL_atomic.c / SDL_spinlock.c

	defines << ['-D_FORTIFY_SOURCE=2']
	defines << ['-DANDROID']

	if opt.verbosity > 0 {
		eprintln('Compiling SDL2_mixer + dependencies to .o')
	}

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
			arch_cflags[arch] << ['-march=armv7-a','-mthumb']
		}
		if arch == 'x86' {
			arch_cflags[arch] << ['-mstackrealign'] // SDL_mixer x86
		}
	}

	mut jobs := []ShellJob{}
	mut lib_o_files := map[string]map[string][]string{}
	mut lib_so_files := map[string][]string{}
	mut lib_ao_files := map[string][]string{}
	mut lib_a_files := map[string]map[string][]string{}
	// .c -> .o/.a files
	libs := mix_opt.env.sources.keys()
	for lib in libs {
		mut lib_includes := mix_opt.env.includes[lib].clone()
		lib_sources := mix_opt.env.sources[lib].clone()
		lib_c_flags := mix_opt.env.c_flags[lib].clone()
		for arch in archs {
			lib_includes[arch] << opt.env.includes['libSDL2'][arch].clone() //.map('-I"$it"')
			// Setup work directories
			arch_o_dir := os.join_path(build_dir,lib, 'o', arch) // TODO sanitize lib name for filesystem?
			os.rmdir_all(arch_o_dir) or {}
			os.mkdir_all(arch_o_dir) or {
				return error('$err_sig: failed making directory "$arch_o_dir". $err')
			}

			//println('$lib -> $arch')

			for c_file in lib_sources[arch]['c'] {
				source_file := c_file
				object_file := os.join_path(arch_o_dir,
					os.file_name(source_file).all_before_last('.') + '.o')
				lib_o_files[lib][arch] << object_file

				mut m_cflags := []string{}
				//if is_debug_build {
					m_cflags << ['-MMD', '-MP'] //, '-MF <tmp path to SDL_<name>.o.d>']
					m_cflags << '-MF"' +
						os.join_path(arch_o_dir, os.file_name(source_file).all_before_last('.') +
						'.o.d"')
				//}

				build_cmd := [
					arch_cc[arch],
					m_cflags.join(' '),
					arch_cflags[arch].join(' '),
					cflags.join(' '),
					lib_c_flags[arch].join(' '),
					includes.join(' '),
					lib_includes[arch].map('-I"$it"').join(' '),
					defines.join(' '),
					'-c "$source_file"',
					'-o "$object_file"',
				]

				jobs << ShellJob{
					std_err: if opt.verbosity > 2 {
						mut thumb := if arch == 'armeabi-7va' { '(thumb)' } else { '' }
						'Compiling $lib for $arch $thumb C file "${os.file_name(c_file)}"'
					} else {
						''
					}
					cmd: build_cmd
				}
			}

			for cpp_file in lib_sources[arch]['cpp'] {
				source_file := cpp_file
				object_file := os.join_path(arch_o_dir,
					os.file_name(source_file).all_before_last('.') + '.o')
				lib_o_files[lib][arch] << object_file

				mut m_cflags := []string{}
				//if is_debug_build {
					m_cflags << ['-MMD', '-MP'] //, '-MF <tmp path to SDL_<name>.o.d>']
					m_cflags << '-MF"' +
						os.join_path(arch_o_dir, os.file_name(source_file).all_before_last('.') +
						'.o.d"')
				//}


				build_cmd := [
					arch_cc_cpp[arch],
					m_cflags.join(' '),
					'-fno-exceptions -fno-rtti', // NOTE prevents ld error "undefined reference to `__gxx_personality_v0'"
					arch_cflags[arch].join(' '),
					cflags.join(' '),
					lib_c_flags[arch].join(' '),
					includes.join(' '),
					lib_includes[arch].map('-I"$it"').join(' '),
					defines.join(' '),
					'-c "$source_file"',
					'-o "$object_file"',
				]

				jobs << ShellJob{
					std_err: if opt.verbosity > 2 {
						mut thumb := if arch == 'armeabi-7va' { '(thumb)' } else { '' }
						'Compiling $lib for $arch $thumb C++ file "${os.file_name(cpp_file)}"'
					} else {
						''
					}
					cmd: build_cmd
				}
			}
		}
	}
	run_jobs(jobs,opt.parallel,opt.verbosity) !
	jobs.clear()

	// .o -> to .so/.a
	for lib in libs {
		lib_ld_flags := mix_opt.env.ld_flags[lib].clone()
		if lib == 'libSDL2_mixer' {
			continue
		}

		mut fe := '.a'
		if lib == 'libmpg123' {
			fe = '.so'
		}
		lib_name := '$lib$fe'

		for arch in archs {
			// Setup work directories
			arch_lib_dir := os.join_path(build_dir,'lib', arch)
			os.mkdir_all(arch_lib_dir) or {
				return error('$err_sig: failed making directory "$arch_lib_dir". $err')
			}

			// linker flags
			mut ldflags := []string{}
			if fe == '.so' {
				ldflags << '-ldl'
			}
			ldflags << ['-lc', '-lm']

			if fe == '.a' {

				lib_a_file := os.join_path(arch_lib_dir, lib_name)

				build_a_cmd := [
					arch_ar[arch],
					'crsD',
					'"$lib_a_file"',
					lib_o_files[lib][arch].map('"$it"').join(' '),
				]

				lib_ao_files[arch] << lib_a_file

				jobs << ShellJob{
					std_err: if opt.verbosity > 1 { 'Compiling (static) $lib for $arch' } else { '' }
					cmd: build_a_cmd
				}
			} else {
				lib_so_file := os.join_path(arch_lib_dir, lib_name)
				// Finally, build libXXX.so
				build_so_cmd := [
					arch_cc_cpp[arch],
					'-Wl,-soname,$lib_name -shared',
					lib_o_files[lib][arch].map('"$it"').join(' '),
					lib_a_files[lib][arch].map('"$it"').join(' '),
					'-lgcc -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_real.a -latomic -Wl,--exclude-libs,libatomic.a',
					arch_cflags[arch].join(' '),
					os.join_path(sdl_build_dir,'lib', arch, 'libSDL2.so'),
					'-no-canonical-prefixes',
					'-Wl,--build-id=sha1',
					'-Wl,--no-rosegment',
					'-stdlib=libstdc++',
					'-Wl,--no-undefined',
					'-Wl,--fatal-warnings',
					lib_ld_flags[arch].join(' ')
					ldflags.join(' '),
					'-o "$lib_so_file"',
				]

				lib_so_files[arch] << lib_so_file

				jobs << ShellJob{
					std_err: if opt.verbosity > 1 { 'Compiling (dynamic) $lib for $arch' } else { '' }
					cmd: build_so_cmd
				}
			}
		}
	}
	run_jobs(jobs,opt.parallel,opt.verbosity) !
	jobs.clear()

	for arch in archs {
		lib := 'libSDL2_mixer'
		lib_name := '${lib}.so'
		// Setup work directories
		arch_lib_dir := os.join_path(build_dir,'lib', arch)
		os.mkdir_all(arch_lib_dir) or {
			return error('$err_sig: failed making directory "$arch_lib_dir". $err')
		}

		// linker flags
		mut ldflags := []string{}
		ldflags << ['-ldl', '-lc', '-lm'] // ,'-lstdc++'

		lib_so_file := os.join_path(arch_lib_dir, lib_name)
		// Finally, build libXXX.so
		build_so_cmd := [
			arch_cc_cpp[arch],
			'-Wl,-soname,$lib_name -shared',
			lib_o_files[lib][arch].map('"$it"').join(' '),
			lib_a_files[lib][arch].map('"$it"').join(' '),
			lib_ao_files[arch].map('"$it"').join(' ')
			'-lgcc -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_real.a -latomic -Wl,--exclude-libs,libatomic.a',
			arch_cflags[arch].join(' '),
			lib_so_files[arch].map('"$it"').join(' ')
			'"'+os.join_path(sdl_build_dir,'lib', arch, 'libSDL2.so')+'"',
			'-no-canonical-prefixes',
			'-Wl,--build-id=sha1',
			'-Wl,--no-rosegment',
			'-stdlib=libstdc++',
			'-Wl,--no-undefined', // TODO music_ogg / OGG_load ??
			'-Wl,--fatal-warnings',
			ldflags.join(' '),
			'-o "$lib_so_file"',
		]

		jobs << ShellJob{
			std_err: if opt.verbosity > 1 { 'Compiling $lib for $arch' } else { '' }
			cmd: build_so_cmd
		}
	}
	run_jobs(jobs,opt.parallel,opt.verbosity) !
	jobs.clear()
}

fn compile_v_code(sdl_opt SDLCompileOptions) ! {
	// err_sig := @MOD + '.' + @FN
	// TODO Keystore file
	mut keystore := android.Keystore{
		path: ''
	}
	if !os.is_file(keystore.path) {
		if keystore.path != '' {
			eprintln('Keystore "$keystore.path" is not a valid file')
			eprintln('Notice: Signing with debug keystore')
		}
		keystore = android.default_keystore(cache_directory) or {
			eprintln('Getting a default keystore failed.\n$err')
			exit(1)
		}
	} else {
		keystore = android.resolve_keystore(keystore) or {
			eprintln('Could not resolve keystore.\n$err')
			exit(1)
		}
	}
	if sdl_opt.verbosity > 1 {
		println('Output will be signed with keystore at "$keystore.path"')
	}

	mut c_flags := sdl_opt.c_flags
	// c_flags << android_includes
	c_flags << '-I"' + os.join_path(sdl_opt.env.config.root, 'include') + '"'
	c_flags << '-UNDEBUG'
	c_flags << '-D_FORTIFY_SOURCE=2'
	c_flags << ['-Wno-pointer-to-int-cast', '-Wno-constant-conversion', '-Wno-literal-conversion',
		'-Wno-deprecated-declarations']
	// c_flags << '-mthumb'
	// V specific
	c_flags << ['-Wno-int-to-pointer-cast']

	// Even though not in use: prevent error: ("sokol_app.h: unknown 3D API selected for Android, must be SOKOL_GLES3 or SOKOL_GLES2")
	// And satisfy sokol_gfx.h:2571:2: error: "Please select a backend with SOKOL_GLCORE33, SOKOL_GLES2, SOKOL_GLES3, ... or SOKOL_DUMMY_BACKEND"
	c_flags << '-DSOKOL_GLES2'

	compile_cache_key := if os.is_dir(sdl_opt.input) { sdl_opt.input } else { '' } // || input_ext == '.v'
	comp_opt := android.CompileOptions{
		verbosity: sdl_opt.verbosity
		cache: sdl_opt.cache
		cache_key: compile_cache_key
		parallel: sdl_opt.parallel
		is_prod: sdl_opt.is_prod
		no_printf_hijack: false
 		v_flags: sdl_opt.v_flags //['-g','-gc boehm'] //['-gc none']
		c_flags: c_flags
		archs: sdl_opt.archs.filter(it.trim(' ') != '')
		work_dir: sdl_opt.work_dir
		input: sdl_opt.input
		ndk_version: sdl_opt.ndk_version
		lib_name: 'main' // sdl_opt.lib_name
		api_level: sdl_opt.api_level
		min_sdk_version: sdl_opt.min_sdk_version
	}
	vab_compile(comp_opt, sdl_opt) or {
		eprintln('$exe_name compiling didn\'t succeed')
		exit(1)
	}

	pck_opt := android.PackageOptions{
		verbosity: sdl_opt.verbosity
		work_dir: sdl_opt.work_dir
		is_prod: sdl_opt.is_prod
		api_level: sdl_opt.api_level
		min_sdk_version: sdl_opt.min_sdk_version
		gles_version: 2 // sdl_opt.gles_version
		build_tools: sdk.default_build_tools_version
		// app_name: sdl_opt.app_name
		lib_name: 'main' // sdl_opt.lib_name
		activity_name: 'VSDLActivity'
		package_id: 'io.v.android.ex'
		// format: android.PackageFormat.aab //format
		format: android.PackageFormat.apk // format
		// icon: sdl_opt.icon
		version_code: 0 // sdl_opt.version_code
		v_flags: sdl_opt.v_flags
		input: sdl_opt.input
		assets_extra: ['/home/lmp/.vmodules/sdl/examples/assets']//sdl_opt.assets_extra
		libs_extra: [os.join_path(sdl_opt.build_directory(), 'lib'),os.join_path(sdl_opt.build_directory(),'mixer','lib')] // sdl_opt.libs_extra
		output_file: '/tmp/t.apk' // sdl_opt.output
		keystore: keystore
		base_files: os.join_path('$os.home_dir()/.vmodules/vab', 'platforms', 'android')
		// base_files: '$os.home_dir()/Projects/vdev/v_sdl4android/tmp/v_sdl_java'
		overrides_path: '$os.home_dir()/Projects/vdev/v_sdl4android/tmp/v_sdl_java' // sdl_opt.package_overrides_path
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
		v_flags: fp.string_multi('flag', `f`, 'Additional flags for the V compiler')
		archs: fp.string('archs', 0, defaults.archs.filter(it.trim(' ') != '').join(','),
			'Comma separated string with any of $android.default_archs').split(',').filter(it.trim(' ') != '')
		//
		show_help: fp.bool('help', `h`, defaults.show_help, 'Show this help message and exit')
		//
		output: fp.string('output', `o`, defaults.output, 'Path to output (dir/file)')
		//
		verbosity: verbosity
		//
		cache: fp.bool('nocache', 0, defaults.cache, 'Do not use build cache')
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

fn ab_cache_dir() string {
	return os.join_path(os.cache_dir(), 'vab')
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
	// vmod := @VMOD_FILE
	vmod := 'version: 0.0.1'
	if vmod.len > 0 {
		if vmod.contains('version:') {
			v = vmod.all_after('version:').all_before('\n').replace("'", '').replace('"',
				'').trim(' ')
		}
	}
	return v
}

pub fn vab_compile(opt android.CompileOptions, sdl_opt SDLCompileOptions) ! {
	err_sig := @MOD + '.' + @FN

	// TODO Building the .so will fail - but right now it's nice to piggyback on the part that succeeds
	android.compile(opt) or { println('TODO Expected error?: $err') }

	build_dir := opt.build_directory()!
	sdl_build_dir := sdl_opt.build_directory()

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

		o_file_path := os.join_path(build_dir, 'o', arch)
		o_ls := os.ls(o_file_path) or { []string{} }
		for f in o_ls {
			if f.ends_with('.o') {
				o_files[arch] << os.join_path(o_file_path, f)
			}
		}
	}

	mut jobs := []ShellJob{}

	mut ldflags := ['-landroid', '-llog', '-ldl', '-lc', '-lm', '-lEGL', '-lGLESv1_CM', '-lGLESv2']

	// Cross compile .so lib files
	for arch in archs {
		// arch_o_dir := os.join_path(build_dir, 'o', arch)
		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir) or {}

		libsdl2_so_file := os.join_path(sdl_build_dir, 'lib', arch, 'libSDL2.so')
		libsdl2_mixer_so_file := os.join_path(sdl_build_dir,'mixer', 'lib', arch, 'libSDL2_mixer.so')

		// os.mkdir_all(arch_o_dir) or {
		//	panic('$err_sig: failed making directory "$arch_o_dir". $err')
		//}

		arch_o_files := o_files[arch].map('"$it"')

		mut args := []string{}
		// args << '-v'
		args << '-Wl,-soname,libmain.so -shared '
		args << arch_o_files.join(' ')

		args << '-lgcc -Wl,--exclude-libs,libgcc.a -Wl,--exclude-libs,libgcc_real.a -latomic -Wl,--exclude-libs,libatomic.a'
		args << libsdl2_so_file
		args << libsdl2_mixer_so_file
		// args << arch_cflags[arch]
		args << '-no-canonical-prefixes -Wl,--build-id -stdlib=libstdc++ -Wl,--fatal-warnings'
		args << '-Wl,--no-undefined' // TODO SDL+Sokol

		// args << '-L"' + arch_libs[arch] + '"'
		args << ldflags.join(' ')

		// Compile .so
		build_cmd := [
			arch_cc[arch] + '++',
			args.join(' '),
			'-o "$arch_lib_dir/lib${opt.lib_name}.so"',
		]

		jobs << ShellJob{
			cmd: build_cmd
		}
	}

	run_jobs(jobs,opt.parallel,opt.verbosity)!

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

fn sdl_environment(config SDLConfig) !SDLEnv {
	err_sig := @MOD + '.' + @FN
	root := os.real_path(config.root)

	supported_archs := unsafe { ndk.supported_archs }

	// Detect version - TODO FIXME
	version := os.file_name(config.root).all_after('SDL2-')

	src := os.join_path(root, 'src')

	mut c_files := []string{}
	mut c_arm_files := []string{}
	mut cpp_files := []string{}

	// TODO test *all* versions
	if version != '2.0.20' {
		return error('$err_sig: TODO only 2.0.20 is currently supported (not "$version")')
	}

	if version !in supported_sdl_versions {
		return error('Can not detect SDL environment for SDL version "$version"')
	}

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
	// Collect C files that should compiled as arm (not thumb)
	c_arm_files << [
		os.join_path(src, 'atomic', 'SDL_atomic.c'),
		os.join_path(src, 'atomic', 'SDL_spinlock.c'),
	]
	// Collect c++ files
	for collect_path in collect_cpp_paths {
		collect_flat_ext(collect_path, mut cpp_files, '.cpp')
	}

	mut includes := map[string]map[string][]string{}
	for arch in supported_archs {
		includes['libSDL2'][arch] << os.join_path(root, 'include')
	}
	mut sources  :=  map[string]map[string]map[string][]string{}
	for arch in supported_archs {
		sources['libSDL2'][arch]['c'] << c_files
		sources['libSDL2'][arch]['cpp'] << cpp_files
		sources['libSDL2'][arch]['c.arm'] << c_arm_files
	}

	mut c_flags  := map[string]map[string][]string{}
	for arch in supported_archs {
		c_flags['libSDL2'][arch] << '-DGL_GLEXT_PROTOTYPES'
		c_flags['libSDL2'][arch] << ['-Wall','-Wextra','-Wdocumentation','-Wdocumentation-unknown-command','-Wmissing-prototypes','-Wunreachable-code-break','-Wunneeded-internal-declaration','-Wmissing-variable-declarations','-Wfloat-conversion','-Wshorten-64-to-32','-Wunreachable-code-return','-Wshift-sign-overflow','-Wstrict-prototypes','-Wkeyword-macro']
		// SDL/JNI specifics that aren't fixed yet
		c_flags['libSDL2'][arch] << '-Wno-unused-parameter -Wno-sign-compare'.split(' ')
	}

	mut ld_flags  := map[string]map[string][]string{}
	for arch in supported_archs {
		ld_flags['libSDL2'][arch] << '-ldl -lGLESv1_CM -lGLESv2 -lOpenSLES -llog -landroid'.split(' ')
	}

	return SDLEnv{
		config: config
		version: version
		includes: includes
		sources: sources
		c_flags: c_flags
		ld_flags: ld_flags
	}
}

fn sdl_mixer_environment(config SDLMixerConfig) !SDLMixerEnv {
	err_sig := @MOD + '.' + @FN
	root := os.real_path(config.root)

	supported_archs := unsafe { ndk.supported_archs }
	// Detect version - TODO FIXME
	version := os.file_name(config.root).all_after('SDL2_mixer-')

	mut includes := map[string]map[string][]string{}
	mut c_flags := map[string]map[string][]string{}
	mut sources  :=  map[string]map[string]map[string][]string{}


	ogg_root := os.join_path(root, 'external','libogg-1.3.2')
	vorbis_root := os.join_path(root, 'external','libvorbisidec-1.2.1')
	// libFLAC
	flac_root := os.join_path(root, 'external','flac-1.3.2')
	lib_flac_root := os.join_path(flac_root,'src','libFLAC')
	// libmpg123
	mpg123_root := os.join_path(root, 'external','mpg123-1.25.6')
	// libmodplug
	modplug_root := os.join_path(root, 'external','libmodplug-0.8.9.0')
	// TiMidity
	timidity_root := os.join_path(root, 'timidity')

	// Headers / defines
	for arch in supported_archs {
		includes['libSDL2_mixer'][arch] << root
	}

	// Sources
	mut srcs := []string{} // Re-use this to collect files in

	// SDL_mixer .c files
	collect_flat_ext(root, mut srcs, '.c')
	srcs = srcs.filter(os.file_name(it) !in ['playmus.c','playwave.c'])
	for arch in supported_archs {
		sources['libSDL2_mixer'][arch]['c'] << srcs.clone()
	}
	srcs.clear()

	// libFLAC
	for arch in supported_archs {
		includes['libFLAC'][arch] << os.join_path(flac_root,'include')
		includes['libFLAC'][arch] << os.join_path(lib_flac_root,'include')
		includes['libFLAC'][arch] << os.join_path(ogg_root,'include')
		includes['libFLAC'][arch] << os.join_path(ogg_root,'android')
		c_flags['libFLAC'][arch] << '-include "'+os.join_path(flac_root,'android','config.h')+'"'
		sources['libFLAC'][arch]['c'] << [
			os.join_path(lib_flac_root,'bitmath.c')
			os.join_path(lib_flac_root,'bitreader.c')
			os.join_path(lib_flac_root,'bitwriter.c')
			os.join_path(lib_flac_root,'cpu.c')
			os.join_path(lib_flac_root,'crc.c')
			os.join_path(lib_flac_root,'fixed.c')
			os.join_path(lib_flac_root,'fixed_intrin_sse2.c')
			os.join_path(lib_flac_root,'fixed_intrin_ssse3.c')
			os.join_path(lib_flac_root,'float.c')
			os.join_path(lib_flac_root,'format.c')
			os.join_path(lib_flac_root,'lpc.c')
			os.join_path(lib_flac_root,'lpc_intrin_sse.c')
			os.join_path(lib_flac_root,'lpc_intrin_sse2.c')
			os.join_path(lib_flac_root,'lpc_intrin_sse41.c')
			os.join_path(lib_flac_root,'lpc_intrin_avx2.c')
			os.join_path(lib_flac_root,'md5.c')
			os.join_path(lib_flac_root,'memory.c')
			os.join_path(lib_flac_root,'metadata_iterators.c')
			os.join_path(lib_flac_root,'metadata_object.c')
			os.join_path(lib_flac_root,'stream_decoder.c')
			os.join_path(lib_flac_root,'stream_encoder.c')
			os.join_path(lib_flac_root,'stream_encoder_intrin_sse2.c')
			os.join_path(lib_flac_root,'stream_encoder_intrin_ssse3.c')
			os.join_path(lib_flac_root,'stream_encoder_intrin_avx2.c')
			os.join_path(lib_flac_root,'stream_encoder_framing.c')
			os.join_path(lib_flac_root,'window.c')
			os.join_path(lib_flac_root,'ogg_decoder_aspect.c')
			os.join_path(lib_flac_root,'ogg_encoder_aspect.c')
			os.join_path(lib_flac_root,'ogg_helper.c')
			os.join_path(lib_flac_root,'ogg_mapping.c')
		]
	}

	// libmpg123
	for arch in supported_archs {
		includes['libmpg123'][arch] << os.join_path(mpg123_root,'android')
		includes['libmpg123'][arch] << os.join_path(mpg123_root,'src')
		includes['libmpg123'][arch] << os.join_path(mpg123_root,'src/compat')
		includes['libmpg123'][arch] << os.join_path(mpg123_root,'src/libmpg123')
	}

	// neon
	c_flags['libmpg123']['armeabi-v7a'] << '-DOPT_NEON -DREAL_IS_FLOAT'.split(' ')
	// neon64
	c_flags['libmpg123']['arm64-v8a'] << '-DOPT_MULTI -DOPT_GENERIC -DOPT_GENERIC_DITHER -DOPT_NEON64 -DREAL_IS_FLOAT'.split(' ')
	// x86
	c_flags['libmpg123']['x86'] << '-DOPT_GENERIC -DREAL_IS_FLOAT'.split(' ')
	// x86_64
	c_flags['libmpg123']['x86_64'] << '-DOPT_MULTI -DOPT_X86_64 -DOPT_GENERIC -DOPT_GENERIC_DITHER -DREAL_IS_FLOAT -DOPT_AVX'.split(' ')


	// libmpg123 .c files
	libmpg123_src := os.join_path(mpg123_root,'src','libmpg123')
	libmpg123_compat_src := os.join_path(mpg123_root,'src','compat')
	sources['libmpg123']['armeabi-v7a']['c'] << [
		os.join_path(libmpg123_src,'stringbuf.c'),
		os.join_path(libmpg123_src,'icy.c'),
		os.join_path(libmpg123_src,'icy2utf8.c'),
		os.join_path(libmpg123_src,'ntom.c'),
		os.join_path(libmpg123_src,'synth.c'),
		os.join_path(libmpg123_src,'synth_8bit.c'),
		os.join_path(libmpg123_src,'layer1.c'),
		os.join_path(libmpg123_src,'layer2.c'),
		os.join_path(libmpg123_src,'layer3.c'),
		os.join_path(libmpg123_src,'dct36_neon.S'),
		os.join_path(libmpg123_src,'dct64_neon_float.S'),
		os.join_path(libmpg123_src,'synth_neon_float.S'),
		os.join_path(libmpg123_src,'synth_neon_s32.S'),
		os.join_path(libmpg123_src,'synth_stereo_neon_float.S'),
		os.join_path(libmpg123_src,'synth_stereo_neon_s32.S'),
		os.join_path(libmpg123_src,'dct64_neon.S'),
		os.join_path(libmpg123_src,'synth_neon.S'),
		os.join_path(libmpg123_src,'synth_stereo_neon.S'),
		os.join_path(libmpg123_src,'synth_s32.c'),
		os.join_path(libmpg123_src,'synth_real.c'),
		os.join_path(libmpg123_src,'feature.c'),
	]
	sources['libmpg123']['arm64-v8a']['c'] << [
		os.join_path(libmpg123_src,'stringbuf.c')
		os.join_path(libmpg123_src,'icy.c')
		os.join_path(libmpg123_src,'icy2utf8.c')
		os.join_path(libmpg123_src,'ntom.c')
		os.join_path(libmpg123_src,'synth.c')
		os.join_path(libmpg123_src,'synth_8bit.c')
		os.join_path(libmpg123_src,'layer1.c')
		os.join_path(libmpg123_src,'layer2.c')
		os.join_path(libmpg123_src,'layer3.c')
		os.join_path(libmpg123_src,'dct36_neon64.S')
		os.join_path(libmpg123_src,'dct64_neon64_float.S')
		os.join_path(libmpg123_src,'synth_neon64_float.S')
		os.join_path(libmpg123_src,'synth_neon64_s32.S')
		os.join_path(libmpg123_src,'synth_stereo_neon64_float.S')
		os.join_path(libmpg123_src,'synth_stereo_neon64_s32.S')
		os.join_path(libmpg123_src,'dct64_neon64.S')
		os.join_path(libmpg123_src,'synth_neon64.S')
		os.join_path(libmpg123_src,'synth_stereo_neon64.S')
		os.join_path(libmpg123_src,'synth_s32.c')
		os.join_path(libmpg123_src,'synth_real.c')
		os.join_path(libmpg123_src,'dither.c')
		os.join_path(libmpg123_src,'getcpuflags_arm.c')
		os.join_path(libmpg123_src,'check_neon.S')
		os.join_path(libmpg123_src,'feature.c')
	]
	sources['libmpg123']['x86']['c'] << [
		os.join_path(libmpg123_src,'feature.c')
		os.join_path(libmpg123_src,'icy2utf8.c')
		os.join_path(libmpg123_src,'icy.c')
		os.join_path(libmpg123_src,'layer1.c')
		os.join_path(libmpg123_src,'layer2.c')
		os.join_path(libmpg123_src,'layer3.c')
		os.join_path(libmpg123_src,'ntom.c')
		os.join_path(libmpg123_src,'stringbuf.c')
		os.join_path(libmpg123_src,'synth_8bit.c')
		os.join_path(libmpg123_src,'synth.c')
		os.join_path(libmpg123_src,'synth_real.c')
		os.join_path(libmpg123_src,'synth_s32.c')
		os.join_path(libmpg123_src,'dither.c')
	]
	sources['libmpg123']['x86_64']['c'] << [
		os.join_path(libmpg123_src,'stringbuf.c')
		os.join_path(libmpg123_src,'icy.c')
		//os.join_path(libmpg123_src,'icy.h')
		os.join_path(libmpg123_src,'icy2utf8.c')
		//os.join_path(libmpg123_src,'icy2utf8.h')
		os.join_path(libmpg123_src,'ntom.c')
		os.join_path(libmpg123_src,'synth.c')
		//os.join_path(libmpg123_src,'synth.h')
		os.join_path(libmpg123_src,'synth_8bit.c')
		//os.join_path(libmpg123_src,'synth_8bit.h')
		os.join_path(libmpg123_src,'layer1.c')
		os.join_path(libmpg123_src,'layer2.c')
		os.join_path(libmpg123_src,'layer3.c')
		os.join_path(libmpg123_src,'synth_s32.c')
		os.join_path(libmpg123_src,'synth_real.c')
		os.join_path(libmpg123_src,'dct36_x86_64.S')
		os.join_path(libmpg123_src,'dct64_x86_64_float.S')
		os.join_path(libmpg123_src,'synth_x86_64_float.S')
		os.join_path(libmpg123_src,'synth_x86_64_s32.S')
		os.join_path(libmpg123_src,'synth_stereo_x86_64_float.S')
		os.join_path(libmpg123_src,'synth_stereo_x86_64_s32.S')
		os.join_path(libmpg123_src,'synth_x86_64.S')
		os.join_path(libmpg123_src,'dct64_x86_64.S')
		os.join_path(libmpg123_src,'synth_stereo_x86_64.S')
		os.join_path(libmpg123_src,'dither.c')
		// os.join_path(libmpg123_src,'dither.h')
		os.join_path(libmpg123_src,'getcpuflags_x86_64.S')
		os.join_path(libmpg123_src,'dct36_avx.S')
		os.join_path(libmpg123_src,'dct64_avx_float.S')
		os.join_path(libmpg123_src,'synth_stereo_avx_float.S')
		os.join_path(libmpg123_src,'synth_stereo_avx_s32.S')
		os.join_path(libmpg123_src,'dct64_avx.S')
		os.join_path(libmpg123_src,'synth_stereo_avx.S')
		os.join_path(libmpg123_src,'feature.c')
	]

	for arch in supported_archs {
		sources['libmpg123'][arch]['c'] << [
			os.join_path(libmpg123_src,'parse.c')
			os.join_path(libmpg123_src,'frame.c')
			os.join_path(libmpg123_src,'format.c')
			os.join_path(libmpg123_src,'dct64.c')
			os.join_path(libmpg123_src,'equalizer.c')
			os.join_path(libmpg123_src,'id3.c')
			os.join_path(libmpg123_src,'optimize.c')
			os.join_path(libmpg123_src,'readers.c')
			os.join_path(libmpg123_src,'tabinit.c')
			os.join_path(libmpg123_src,'libmpg123.c')
			os.join_path(libmpg123_src,'index.c')
			os.join_path(libmpg123_compat_src, 'compat_str.c')
			os.join_path(libmpg123_compat_src, 'compat.c')
		]
	}

	// libogg
	for arch in supported_archs {
		includes['libogg'][arch] << os.join_path(ogg_root,'include')
		includes['libogg'][arch] << os.join_path(ogg_root,'android')
		//includes['libogg'][arch] << os.join_path(vorbis_root)
	}

	for arch in supported_archs {
		sources['libogg'][arch]['c'] << [
			os.join_path(ogg_root,'src/framing.c')
			os.join_path(ogg_root,'src/bitwise.c')
		]
	}

	// libvorbisidec
	for arch in supported_archs {
		includes['libvorbisidec'][arch] << os.join_path(ogg_root,'include')
		includes['libvorbisidec'][arch] << os.join_path(ogg_root,'android')
		includes['libvorbisidec'][arch] << os.join_path(vorbis_root)
	}

	c_flags['libvorbisidec']['armeabi-v7a'] << '-D_ARM_ASSEM_'

	for arch in supported_archs {
		sources['libvorbisidec'][arch]['c'] << [
			os.join_path(vorbis_root,'block.c')
			os.join_path(vorbis_root,'synthesis.c')
			os.join_path(vorbis_root,'info.c')
			os.join_path(vorbis_root,'res012.c')
			os.join_path(vorbis_root,'mapping0.c')
			os.join_path(vorbis_root,'registry.c')
			os.join_path(vorbis_root,'codebook.c')
		]
		sources['libvorbisidec'][arch]['c.arm'] << [
			os.join_path(vorbis_root,'mdct.c')
			os.join_path(vorbis_root,'window.c')
			os.join_path(vorbis_root,'floor1.c')
			os.join_path(vorbis_root,'floor0.c')
			os.join_path(vorbis_root,'vorbisfile.c')
			os.join_path(vorbis_root,'sharedbook.c')
		]
		sources['libvorbisidec'][arch]['c'] << [
			os.join_path(ogg_root,'src/framing.c')
			os.join_path(ogg_root,'src/bitwise.c')
		]
	}

	// libmodplug
	for arch in supported_archs {
		includes['libmodplug'][arch] << os.join_path(modplug_root,'src')
		includes['libmodplug'][arch] << os.join_path(modplug_root,'src','libmodplug')
		sources['libmodplug'][arch]['cpp'] << [
			os.join_path(modplug_root,'src/fastmix.cpp')
			os.join_path(modplug_root,'src/load_669.cpp')
			os.join_path(modplug_root,'src/load_abc.cpp')
			os.join_path(modplug_root,'src/load_amf.cpp')
			os.join_path(modplug_root,'src/load_ams.cpp')
			os.join_path(modplug_root,'src/load_dbm.cpp')
			os.join_path(modplug_root,'src/load_dmf.cpp')
			os.join_path(modplug_root,'src/load_dsm.cpp')
			os.join_path(modplug_root,'src/load_far.cpp')
			os.join_path(modplug_root,'src/load_it.cpp')
			os.join_path(modplug_root,'src/load_j2b.cpp')
			os.join_path(modplug_root,'src/load_mdl.cpp')
			os.join_path(modplug_root,'src/load_med.cpp')
			os.join_path(modplug_root,'src/load_mid.cpp')
			os.join_path(modplug_root,'src/load_mod.cpp')
			os.join_path(modplug_root,'src/load_mt2.cpp')
			os.join_path(modplug_root,'src/load_mtm.cpp')
			os.join_path(modplug_root,'src/load_okt.cpp')
			os.join_path(modplug_root,'src/load_pat.cpp')
			os.join_path(modplug_root,'src/load_psm.cpp')
			os.join_path(modplug_root,'src/load_ptm.cpp')
			os.join_path(modplug_root,'src/load_s3m.cpp')
			os.join_path(modplug_root,'src/load_stm.cpp')
			os.join_path(modplug_root,'src/load_ult.cpp')
			os.join_path(modplug_root,'src/load_umx.cpp')
			os.join_path(modplug_root,'src/load_wav.cpp')
			os.join_path(modplug_root,'src/load_xm.cpp')
			os.join_path(modplug_root,'src/mmcmp.cpp')
			os.join_path(modplug_root,'src/modplug.cpp')
			os.join_path(modplug_root,'src/snd_dsp.cpp')
			os.join_path(modplug_root,'src/snd_flt.cpp')
			os.join_path(modplug_root,'src/snd_fx.cpp')
			os.join_path(modplug_root,'src/sndfile.cpp')
			os.join_path(modplug_root,'src/sndmix.cpp')
		]
		c_flags['libmodplug'][arch] << '-DHAVE_SETENV -DHAVE_SINF'.split(' ')
	}

	// libtimidity
	for arch in supported_archs {
		includes['libtimidity'][arch] << timidity_root
		sources['libtimidity'][arch]['c'] << [
			os.join_path(timidity_root,'common.c')
			os.join_path(timidity_root,'instrum.c')
			os.join_path(timidity_root,'mix.c')
			os.join_path(timidity_root,'output.c')
			os.join_path(timidity_root,'playmidi.c')
			os.join_path(timidity_root,'readmidi.c')
			os.join_path(timidity_root,'resample.c')
			os.join_path(timidity_root,'tables.c')
			os.join_path(timidity_root,'timidity.c')
		]
	}

	for arch in supported_archs {
		if config.features.flac {
			includes['libSDL2_mixer'][arch] << includes['libFLAC'][arch].clone()
			c_flags['libSDL2_mixer'][arch] << '-DMUSIC_FLAC'
		}
		if config.features.ogg {
			includes['libSDL2_mixer'][arch] << includes['libogg'][arch].clone()
			includes['libSDL2_mixer'][arch] << includes['libvorbisidec'][arch].clone()
			c_flags['libSDL2_mixer'][arch] << '-DMUSIC_OGG -DOGG_USE_TREMOR -DOGG_HEADER="<ivorbisfile.h>"'.split(' ')
		}
		if config.features.mp3_mpg123 {
			includes['libSDL2_mixer'][arch] << includes['libmpg123'][arch].clone()
			c_flags['libSDL2_mixer'][arch] << '-DMUSIC_MP3_MPG123'
		}
		if config.features.mod_modplug {
			includes['libSDL2_mixer'][arch] << includes['libmodplug'][arch].clone()
			c_flags['libSDL2_mixer'][arch] << '-DMUSIC_MOD_MODPLUG -DMODPLUG_HEADER="<modplug.h>"'.split(' ')
		}
		if config.features.mid_timidity {
			includes['libSDL2_mixer'][arch] << includes['libtimidity'][arch].clone()
			c_flags['libSDL2_mixer'][arch] << '-DMUSIC_MID_TIMIDITY'
		}
	}

	//println(sources)
	return SDLMixerEnv{
		config: config
		version: version
		includes: includes
		sources: sources
		c_flags: c_flags
	}
}

fn collect_flat_ext(path string, mut files []string, ext string) {
	ls := os.ls(path) or { panic(err) }
	for file in ls {
		if file.ends_with(ext) {
			files << os.join_path(path.trim_string_right(os.path_separator), file)
		}
	}
}
