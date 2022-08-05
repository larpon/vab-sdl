module main

import os
import flag
import vab.cli
import vab.android
import vab.android.ndk
// import vab.android.sdk

const (
	exe_version            = version()
	exe_name               = os.file_name(os.executable())
	exe_short_name         = os.file_name(os.executable()).replace('.exe', '')
	exe_dir                = os.dir(os.real_path(os.executable()))
	exe_description        = '$exe_short_name
compile SDL for Android.
'
	exe_git_hash           = ab_commit_hash()
	work_directory         = ab_work_dir()
	cache_directory        = ab_cache_dir()
	accepted_input_files   = ['.v', '.apk', '.aab']
	supported_sdl_versions = ['2.0.8', '2.0.9', '2.0.10', '2.0.12', '2.0.14', '2.0.16', '2.0.18',
		'2.0.20', '2.0.22']
)

fn main() {
	// Collect user flags in an extended manner.
	// Start with defaults -> overwrite by VAB_FLAGS -> overwrite by commandline flags -> extend by .vab file entries.
	mut opt := cli.Options{}
	mut fp := &flag.FlagParser(0)

	opt = cli.options_from_env(opt) or {
		eprintln('Error while parsing `VAB_FLAGS`: $err')
		eprintln('Use `$exe_short_name -h` to see all flags')
		exit(1)
	}

	opt, fp = cli.args_to_options(os.args, opt) or {
		eprintln('Error while parsing `os.args`: $err')
		eprintln('Use `$exe_short_name -h` to see all flags')
		exit(1)
	}

	if opt.dump_usage {
		println(fp.usage())
		exit(0)
	}

	// All flags after this requires an input argument
	if fp.args.len == 0 {
		eprintln('No arguments given')
		eprintln('Use `vab -h` to see all flags')
		exit(1)
	}

	// Call the doctor at this point
	if opt.additional_args.len > 0 {
		if opt.additional_args[0] == 'doctor' {
			// Validate environment
			cli.check_essentials(false)
			opt.resolve(false)
			cli.doctor(opt)
			exit(0)
		}
	}

	// Validate environment
	cli.check_essentials(true)
	opt.resolve(true)

	input := fp.args.last()
	cli.validate_input(input) or {
		eprintln('$cli.exe_short_name: $err')
		exit(1)
	}
	opt.input = input

	opt.resolve_output()

	opt.extend_from_dot_vab()

	// Validate environment after options and input has been resolved
	opt.validate_env()

	opt.ensure_launch_fields()

	// Keystore file
	keystore := opt.resolve_keystore()!

	///////////////////////////////////////////////
	// TODO
	opt.lib_name = 'main'
	opt.activity_name = 'VSDLActivity'
	opt.package_id = 'io.v.android.ex'
	opt.log_tags << ['SDL', 'SDL/APP']
	mut libs_extra := compile_sdl_and_v(opt) or { panic(err) }
	//
	//////////////////////////////////////////////

	ado := opt.as_android_deploy_options() or {
		eprintln('Could not create deploy options.\n$err')
		exit(1)
	}
	deploy_opt := android.DeployOptions{
		...ado
		keystore: keystore
	}

	if opt.verbosity > 1 {
		println('Output will be signed with keystore at "$deploy_opt.keystore.path"')
	}

	input_ext := os.file_ext(opt.input)

	// Early deployment
	if input_ext in ['.apk', '.aab'] {
		if deploy_opt.device_id != '' {
			deploy(deploy_opt)
			exit(0)
		}
	}

	// NOTE this step from vab is skipped since we've already compiled the v sources in compile_sdl_and_v()
	// aco := opt.as_android_compile_options()
	// comp_opt := android.CompileOptions{
	// 	...aco
	// 	cache_key: if os.is_dir(input) || input_ext == '.v' { opt.input } else { '' }
	// }
	// android.compile(comp_opt) or {
	// 	eprintln('$cli.exe_short_name compiling didn\'t succeed.\n$err')
	// 	exit(1)
	// }

	apo := opt.as_android_package_options()
	pck_opt := android.PackageOptions{
		...apo
		assets_extra: [
			os.join_path(os.home_dir(), '.vmodules', 'sdl', 'examples', 'assets'),
		] // base_abo.assets_extra
		libs_extra: libs_extra // base_abo.libs_extra
		keystore: keystore
		base_files: os.join_path(os.home_dir(), '.vmodules', 'vab', 'platforms', 'android')
		overrides_path: os.join_path(os.home_dir(), 'Projects/vdev/v_sdl4android/tmp/v_sdl_java') // TODO base_abo.package_overrides_path
	}
	android.package(pck_opt) or {
		eprintln("Packaging didn't succeed.\n$err")
		exit(1)
	}

	if deploy_opt.device_id != '' {
		deploy(deploy_opt)
	} else {
		if opt.verbosity > 0 {
			println('Generated ${os.real_path(opt.output)}')
			println('Use `$cli.exe_short_name --device <id> ${os.real_path(opt.output)}` to deploy package')
		}
	}
}

fn compile_sdl_and_v(opt cli.Options) ![]string {
	mut collect_libs := []string{}

	// Dump meta data from V
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

	v_meta_dump := android.v_dump_meta(v_meta_opt) or { return error(@FN + ': $err') }
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

	os.rmdir_all(product_cache_path()) or {}

	apis := ndk.available_apis_by_arch(opt.ndk_version)
	for arch in opt.archs {
		mut sdl2_configs := []SDL2ConfigType{}

		mut sdl_build := &Node{
			id: 'SDL2.all.$arch'
			note: 'Build SDL2 and SDL2 modules for $arch variant'
		}

		if apis[arch].len == 0 {
			return error('NDK apis for arch "$arch" is empty: $apis')
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
		mut libsdl2 := libsdl2_node(sdl2_config) or { return error(@FN + ': $err') }
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
			libsdl2_image := libsdl2_image_node(sdl2_image_config) or {
				return error(@FN + ': $err')
			}

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
			libsdl2_mixer := libsdl2_mixer_node(sdl2_mixer_config) or {
				return error(@FN + ': $err')
			}

			libsdl2.add('tasks', libsdl2_mixer)
		}
		if 'sdl.ttf' in imported_modules {
			sdl2_ttf_home := os.real_path(os.join_path(os.home_dir(), 'Downloads', 'SDL2_ttf-2.0.15'))
			sdl2_ttf_version := os.file_name(sdl2_ttf_home).all_after('SDL2_ttf-') // TODO FIXME Detect version in V code

			mut abo := AndroidBuildOptions{
				...sdl2_abo
				version: sdl2_ttf_version
				work_dir: os.join_path(base_abo.work_dir, '$sdl2_ttf_version')
			}
			collect_libs << abo.path_product_libs('SDL2_ttf')

			sdl2_ttf_config := SDL2TTFConfig{
				abo: abo
				root: sdl2_ttf_home
			}
			sdl2_configs << sdl2_ttf_config
			libsdl2_ttf := libsdl2_ttf_node(sdl2_ttf_config) or { return error(@FN + ': $err') }

			libsdl2.add('tasks', libsdl2_ttf)
		}

		sdl_build.add('tasks', libsdl2)

		mut v_build := AndroidNode{
			Node: &Node{
				id: 'V.$arch'
				note: 'Build V sources for $arch variant'
			}
		}

		aco := opt.as_android_compile_options()
		v_config := VSDL2Config{
			sdl2_configs: sdl2_configs
			abo: sdl2_abo
			aco: aco
		}
		mut libv := libv_node(v_config) or { return error(@FN + ': $err') }

		collect_libs << v_config.abo.path_product_libs(opt.lib_name)
		v_build.add('dependencies', sdl_build)
		v_build.add('tasks', libv)

		v_build.build() or { return error(@FN + ': $err') }
	}
	return collect_libs
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

fn deploy(deploy_opt android.DeployOptions) {
	android.deploy(deploy_opt) or {
		eprintln('$cli.exe_short_name deployment didn\'t succeed.\n$err')
		if deploy_opt.kill_adb {
			cli.kill_adb()
		}
		exit(1)
	}
	if deploy_opt.verbosity > 0 {
		println('Deployed to $deploy_opt.device_id successfully')
	}
	if deploy_opt.kill_adb {
		cli.kill_adb()
	}
}
