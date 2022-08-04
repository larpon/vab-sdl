module main

import os
import flag
import vab.android
import vab.android.ndk
import vab.android.sdk

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
	parallel bool = true // Run, what can be run, in parallel
	cache    bool // NOTE flipped when parsed by args_to_options
	// Build specifics
	c_flags   []string // flags passed to the C compiler(s)
	v_flags   []string // flags passed to the V compiler
	lib_name  string = 'main'
	show_help bool
mut:
	additional_args []string
	//
	input  string
	output string
	// Build and packaging
	is_prod bool
	// Build specifics
	archs           []string = android.default_archs.clone()
	api_level       string
	ndk_version     string
	min_sdk_version int = android.default_min_sdk_version
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

	// All flags after this requires an input argument
	if fp.args.len == 0 {
		eprintln('No arguments given')
		eprintln('Use `$exe_pretty_name -h` to see all flags')
		exit(1)
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

	build_archs := opt.archs.clone()
	mut libs_extra := []string{}

	// v_sdl_app := opt.input // os.real_path(os.join_path(os.home_dir(), '.vmodules', 'sdl', 'examples','basic_image'))
	// lib_name := 'main' // TODO make an option

	mut v_flags := opt.v_flags.clone()

	if opt.verbosity > 0 {
		println('Analyzing V source')
		if opt.v_flags.len > 0 {
			println('V flags: `$opt.v_flags`')
		}
	}

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

	// Construct *base* build options
	base_abo := AndroidBuildOptions{
		verbosity: opt.verbosity
		cache: opt.cache
		work_dir: opt.work_dir
		ndk_version: opt.ndk_version
		api_level: opt.api_level // sdk.default_api_level
	}

	sdl2_home := os.real_path(os.join_path(os.home_dir(), 'Downloads', 'SDL2-2.0.20'))
	sdl2_version := os.file_name(sdl2_home).all_after('SDL2-') // TODO FIXME Detect version in V code

	mut collect_libs := []string{}

	os.rmdir_all(product_cache_path()) or {}

	apis := ndk.available_apis_by_arch(opt.ndk_version)
	for arch in build_archs {
		mut sdl2_configs := []SDL2ConfigType{}

		mut sdl_build := &Node{
			id: 'SDL2.all.$arch'
			note: 'Build SDL2 and SDL2 modules for $arch variant'
		}

		min_api_level_available := apis[arch][0] // TODO
		mut sdl2_abo := AndroidBuildOptions{
			...base_abo
			version: sdl2_version
			arch: arch
			api_level: min_api_level_available
			work_dir: os.join_path(base_abo.work_dir)
		}
		collect_libs << sdl2_abo.path_product_libs('SDL2')

		sdl2_config := SDL2Config{
			abo: sdl2_abo
			root: sdl2_home
		}
		mut libsdl2 := libsdl2_node(sdl2_config) or { panic(err) }
		sdl2_configs << sdl2_config

		if 'sdl.image' in imported_modules {
			sdl2_image_home := os.real_path(os.join_path(os.home_dir(), 'Downloads', 'SDL2_image-2.0.5'))
			sdl2_image_version := os.file_name(sdl2_image_home).all_after('SDL2_image-') // TODO FIXME Detect version in V code

			mut abo := AndroidBuildOptions{
				...sdl2_abo
				version: sdl2_image_version
				work_dir: os.join_path(base_abo.work_dir)
			}
			collect_libs << abo.path_product_libs('SDL2_image')
			sdl2_image_config := SDL2ImageConfig{
				abo: abo
				root: sdl2_image_home
			}
			sdl2_configs << sdl2_image_config
			libsdl2_image := libsdl2_image_node(sdl2_image_config) or { panic(err) }

			libsdl2.add('tasks', libsdl2_image)
		}
		if 'sdl.mixer' in imported_modules {
			sdl2_mixer_home := os.real_path(os.join_path(os.home_dir(), 'Downloads', 'SDL2_mixer-2.0.4'))
			sdl2_mixer_version := os.file_name(sdl2_mixer_home).all_after('SDL2_mixer-') // TODO FIXME Detect version in V code

			mut abo := AndroidBuildOptions{
				...sdl2_abo
				version: sdl2_mixer_version
				work_dir: os.join_path(base_abo.work_dir)
			}
			collect_libs << abo.path_product_libs('SDL2_mixer')
			collect_libs << abo.path_product_libs('mpg123')

			sdl2_mixer_config := SDL2MixerConfig{
				abo: abo
				root: sdl2_mixer_home
			}
			sdl2_configs << sdl2_mixer_config
			libsdl2_mixer := libsdl2_mixer_node(sdl2_mixer_config) or { panic(err) }

			libsdl2.add('tasks', libsdl2_mixer)
		}
		if 'sdl.ttf' in imported_modules {
			sdl2_ttf_home := os.real_path(os.join_path(os.home_dir(), 'Downloads', 'SDL2_ttf-2.0.15'))
			sdl2_ttf_version := os.file_name(sdl2_ttf_home).all_after('SDL2_ttf-') // TODO FIXME Detect version in V code

			mut abo := AndroidBuildOptions{
				...sdl2_abo
				version: sdl2_ttf_version
				work_dir: os.join_path(base_abo.work_dir,'$sdl2_ttf_version')
			}
			collect_libs << abo.path_product_libs('SDL2_ttf')

			sdl2_ttf_config := SDL2TTFConfig{
				abo: abo
				root: sdl2_ttf_home
			}
			sdl2_configs << sdl2_ttf_config
			libsdl2_ttf := libsdl2_ttf_node(sdl2_ttf_config) or { panic(err) }

			libsdl2.add('tasks', libsdl2_ttf)
		}

		sdl_build.add('tasks', libsdl2)

		mut v_build := AndroidNode{
			Node: &Node{
				id: 'V.$arch'
				note: 'Build V sources for $arch variant'
			}
		}

		v_config := VSDL2Config{
			sdl2_configs: sdl2_configs
			abo: sdl2_abo
			vbo: VBuildOptions{
				input: opt.input
				lib_name: opt.lib_name
			}
		}
		mut libv := libv_node(v_config) or { panic(err) }

		collect_libs << v_config.abo.path_product_libs(opt.lib_name)
		v_build.add('dependencies', sdl_build)
		v_build.add('tasks', libv)

		v_build.build() or { panic(err) }
	}

	for path in collect_libs {
		libs_extra << path
	}

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
	if base_abo.verbosity > 1 {
		println('Output will be signed with keystore at "$keystore.path"')
	}

	pck_opt := android.PackageOptions{
		verbosity: opt.verbosity
		work_dir: opt.work_dir
		is_prod: opt.is_prod
		api_level: opt.api_level
		min_sdk_version: opt.min_sdk_version
		gles_version: 2 // TODO base_abo.gles_version
		build_tools: sdk.default_build_tools_version
		// app_name: base_abo.app_name
		lib_name: 'main' // TODO base_abo.lib_name
		activity_name: 'VSDLActivity'
		package_id: 'io.v.android.ex'
		// format: android.PackageFormat.aab //format
		format: android.PackageFormat.apk // format
		// icon: base_abo.icon
		version_code: 0 // TODO base_abo.version_code
		// v_flags: base_abo.v_flags
		input: opt.input
		assets_extra: [
			os.join_path(os.home_dir(), '.vmodules', 'sdl', 'examples', 'assets'),
		] // base_abo.assets_extra
		libs_extra: libs_extra // base_abo.libs_extra
		output_file: '/tmp/t.apk' // TODO base_abo.output
		keystore: keystore
		base_files: os.join_path(os.home_dir(), '.vmodules', 'vab', 'platforms', 'android')
		// base_files: '$os.home_dir()/Projects/vdev/v_sdl4android/tmp/v_sdl_java'
		overrides_path: os.join_path(os.home_dir(), 'Projects/vdev/v_sdl4android/tmp/v_sdl_java') // TODO base_abo.package_overrides_path
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
		archs: fp.string('archs', 0, defaults.archs.filter(it.trim_space() != '').join(','),
			'Comma separated string with any of $android.default_archs').split(',').filter(it.trim_space() != '')
		//
		show_help: fp.bool('help', `h`, defaults.show_help, 'Show this help message and exit')
		//
		output: fp.string('output', `o`, defaults.output, 'Path to output (dir/file)')
		//
		verbosity: verbosity
		//
		cache: !fp.bool('nocache', 0, defaults.cache, 'Do not use build cache')
		//
		api_level: fp.string('api', 0, defaults.api_level, 'Android API level to use')
		min_sdk_version: fp.int('min-sdk-version', 0, defaults.min_sdk_version, 'Minimum SDK version version code (android:minSdkVersion)')
		//
		ndk_version: fp.string('ndk-version', 0, defaults.ndk_version, 'Android NDK version to use')
		//
		work_dir: defaults.work_dir
	}
	opt.archs = opt.archs.map(it.trim_space())
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
	return os.join_path(os.temp_dir(), 'vsdl2android')
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
