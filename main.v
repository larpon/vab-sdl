module main

import os
// NOTE: This should never depend on `sdl` since the system <-> module version mismatch bug is not yet 100% solved.
// Compiling and running this should never yield a SDL compilation error, so:
// import sdl // NO-NO
import flag
import semver
import net.http
import vab.cli
import vab.vxt
import vab.util
import vab.paths
import vab.android.util as vabutil
import vab.android
import vab.android.ndk

const default_package_id = 'io.v.android.sdl'
const default_activity_name = 'VSDLActivity'

const default_vab_sdl_options = cli.Options{
	lib_name:      'main'
	package_id:    default_package_id
	activity_name: default_activity_name
	// SDL2's Android Java skeleton uses mipmaps
	icon_mipmaps: true
	// Set defaults for vab-sdl
	default_package_id:    default_package_id
	default_activity_name: default_activity_name
}

const exe_version = version()
const exe_name = os.file_name(os.executable())
const exe_short_name = os.file_name(os.executable()).replace('.exe', '')
const exe_dir = os.dir(os.real_path(os.executable()))
const exe_description = '${exe_short_name}
compile SDL for Android.
'
const exe_git_hash = ab_commit_hash()
const accepted_input_files = ['.v', '.apk', '.aab']
const unsupported_sdl2_versions = ['2.0.8', '2.0.9', '2.0.10', '2.0.12']
const supported_sdl2_versions = ['2.0.14', '2.0.16', '2.0.18', '2.0.20', '2.0.22', '2.24.0', '2.24.1',
	'2.24.2', '2.26.0', '2.26.1', '2.26.2', '2.26.3', '2.26.4', '2.26.5', '2.28.0', '2.28.1',
	'2.28.2', '2.28.3', '2.28.4', '2.28.5', '2.30.0', '2.30.1', '2.30.2', '2.30.3', '2.30.4',
	'2.30.5', '2.30.6', '2.30.7', '2.30.8', '2.30.9']

const cache_path = os.join_path(paths.cache(), '${exe_short_name}', 'cache')

const sdl2_source_downloads = {
	'2.0.8':  'https://www.libsdl.org/release/SDL2-2.0.8.zip'
	'2.0.9':  'https://www.libsdl.org/release/SDL2-2.0.9.zip'
	'2.0.10': 'https://www.libsdl.org/release/SDL2-2.0.10.zip'
	'2.0.12': 'https://www.libsdl.org/release/SDL2-2.0.12.zip'
	'2.0.14': 'https://www.libsdl.org/release/SDL2-2.0.14.zip'
	'2.0.16': 'https://www.libsdl.org/release/SDL2-2.0.16.zip'
	'2.0.18': 'https://www.libsdl.org/release/SDL2-2.0.18.zip'
	'2.0.20': 'https://www.libsdl.org/release/SDL2-2.0.20.zip'
	'2.0.22': 'https://www.libsdl.org/release/SDL2-2.0.22.zip'
	'2.24.0': 'https://www.libsdl.org/release/SDL2-2.24.0.zip'
	'2.24.1': 'https://www.libsdl.org/release/SDL2-2.24.1.zip'
	'2.24.2': 'https://www.libsdl.org/release/SDL2-2.24.2.zip'
	'2.26.0': 'https://www.libsdl.org/release/SDL2-2.26.0.zip'
	'2.26.1': 'https://www.libsdl.org/release/SDL2-2.26.1.zip'
	'2.26.2': 'https://www.libsdl.org/release/SDL2-2.26.2.zip'
	'2.26.3': 'https://www.libsdl.org/release/SDL2-2.26.3.zip'
	'2.26.4': 'https://www.libsdl.org/release/SDL2-2.26.4.zip'
	'2.26.5': 'https://www.libsdl.org/release/SDL2-2.26.5.zip'
	'2.28.0': 'https://www.libsdl.org/release/SDL2-2.28.0.zip'
	'2.28.1': 'https://www.libsdl.org/release/SDL2-2.28.1.zip'
	'2.28.2': 'https://www.libsdl.org/release/SDL2-2.28.2.zip'
	'2.28.3': 'https://www.libsdl.org/release/SDL2-2.28.3.zip'
	'2.28.4': 'https://www.libsdl.org/release/SDL2-2.28.4.zip'
	'2.28.5': 'https://www.libsdl.org/release/SDL2-2.28.5.zip'
	'2.30.0': 'https://www.libsdl.org/release/SDL2-2.30.0.zip'
	'2.30.1': 'https://www.libsdl.org/release/SDL2-2.30.1.zip'
	'2.30.2': 'https://www.libsdl.org/release/SDL2-2.30.2.zip'
	'2.30.3': 'https://www.libsdl.org/release/SDL2-2.30.3.zip'
	'2.30.4': 'https://www.libsdl.org/release/SDL2-2.30.4.zip'
	'2.30.5': 'https://www.libsdl.org/release/SDL2-2.30.5.zip'
	'2.30.6': 'https://www.libsdl.org/release/SDL2-2.30.6.zip'
	'2.30.7': 'https://www.libsdl.org/release/SDL2-2.30.7.zip'
	'2.30.8': 'https://www.libsdl.org/release/SDL2-2.30.8.zip'
}

const sdl2_image_source_downloads = {
	'2.0.5': 'https://www.libsdl.org/projects/SDL_image/release/SDL2_image-2.0.5.zip'
}

const sdl2_mixer_source_downloads = {
	'2.0.4': 'https://www.libsdl.org/projects/SDL_mixer/release/SDL2_mixer-2.0.4.zip'
}

const sdl2_ttf_source_downloads = {
	'2.0.15': 'https://www.libsdl.org/projects/SDL_ttf/release/SDL2_ttf-2.0.15.zip'
}

struct Options {
pub:
	sdl_version string
}

fn highest_patch_version(version string) string {
	mut sem_version := semver.from(version) or { return version }
	if sem_version.satisfies('>=2.24.0') {
		target := version.all_before_last('.') // major.minor
		for sdl_version in supported_sdl2_versions {
			sdl_target := sdl_version.all_before_last('.') // major.minor
			if sdl_target != target {
				continue
			}
			sdl_sem_version := semver.from(sdl_version) or { return version }
			if sdl_sem_version > sem_version {
				sem_version = sdl_sem_version
			}
		}
	}
	return '${sem_version}'
}

// main is a rough reimplementation of `vab`'s main function
fn main() {
	mut args := arguments()

	// NOTE: do not support running sub commands
	// cli.run_vab_sub_command(args)

	// Get input to `vab`.
	mut input := ''
	input, args = cli.input_from_args(args)

	// Collect user flags precedented going from most implicit to most explicit.
	// Start with defaults -> overwrite by .vab file entries -> overwrite by VAB_FLAGS -> overwrite by commandline flags.
	mut opt := cli.Options{
		...default_vab_sdl_options
	}

	opt = cli.options_from_dot_vab(input, opt) or {
		util.vab_error('Could not parse `.vab`', details: '${err}')
		exit(1)
	}

	opt = cli.options_from_env(opt) or {
		util.vab_error('Could not parse `VAB_FLAGS`', details: '${err}')
		util.vab_notice('Use `${cli.exe_short_name} -h` to see all flags')
		exit(1)
	}

	mut unmatched_args := []string{}
	opt, unmatched_args = cli.options_from_arguments(args, opt) or {
		util.vab_error('Could not parse `os.args`', details: '${err}')
		util.vab_notice('Use `${cli.exe_short_name} -h` to see all flags')
		exit(1)
	}

	///////////////////////////////////////////////
	// SDL specific code
	mut sdl_module_version := os.getenv_opt('SDL_VERSION') or {
		highest_patch_version(sdl_version_from_vmod()!)
	}
	sdl_module_semver := semver.from(sdl_module_version) or {
		util.vab_error('Could not convert SDL2 version "${sdl_module_version}" to semantic version (semver)')
		exit(1)
	}
	lowest_supported_sdl_version := supported_sdl2_versions[0] or {
		util.vab_error('No first entry in `supported_sdl2_versions` (${supported_sdl2_versions})')
		exit(1)
	}
	if !sdl_module_semver.satisfies('>=${lowest_supported_sdl_version}') {
		util.vab_error('${exe_short_name} currently only supports SDL2 versions >= ${lowest_supported_sdl_version}. Found ${sdl_module_version}')
		exit(1)
	}
	mut sdl_opt := Options{
		sdl_version: sdl_module_version
	}
	sdl_opt, unmatched_args = sdl_options_from_arguments(unmatched_args, sdl_opt) or {
		util.vab_error('Could not parse `os.args`', details: '${err}')
		util.vab_notice('Use `${cli.exe_short_name} -h` to see all flags')
		exit(1)
	}
	sdl_module_version = sdl_opt.sdl_version
	//
	///////////////////////////////////////////////

	if unmatched_args.len > 0 {
		util.vab_error('Could not parse arguments', details: 'No matches for ${unmatched_args}')
		util.vab_notice('Use `${cli.exe_short_name} -h` to see all flags')
		exit(1)
	}

	if opt.dump_usage {
		documentation := flag.to_doc[cli.Options](cli.vab_documentation_config) or {
			util.vab_error('Could not generate usage documentation via `flag.to_doc[cli.Options](...)` this should not happen',
				details: '${err}'
			)
			exit(1)
		}
		println(documentation)
		exit(0)
	}

	// Call the doctor at this point
	if opt.run_builtin_cmd == 'doctor' {
		// Validate environment
		cli.check_essentials(false)
		opt.resolve(false)
		cli.doctor(opt)
		sdl_doctor(sdl_opt) // Add this extra command's output at the bottom
		exit(0)
	}

	// Validate environment
	cli.check_essentials(true)
	opt.resolve(true)

	cli.validate_input(input) or {
		util.vab_error('${cli.exe_short_name}: ${err}')
		exit(1)
	}
	opt.input = input

	opt.resolve_output()

	// Validate environment after options and input has been resolved
	opt.validate_env()

	opt.ensure_launch_fields()

	// Keystore file
	keystore := opt.resolve_keystore() or {
		util.vab_error('Could not resolve keystore', details: '${err}')
		exit(1)
	}

	///////////////////////////////////////////////
	// SDL specific code
	if !opt.cache {
		opt.verbose(1, 'Clearing cache...')
		os.rmdir_all(cache_path) or {}
	}

	opt.verbose(2, 'Using SDL version ${sdl_module_version}')

	mut sdl2_home := os.getenv_opt('SDL_HOME') or { '' }
	if sdl2_home == '' {
		// Download and extract to a temporary location
		paths.ensure(cache_path) or {
			util.vab_error('could not ensure cache path "${cache_path}"', details: err.msg())
			exit(1)
		}
		sdl2_home = download_and_extract_sdl2(sdl_module_version, cache_path, opt.verbosity) or {
			util.vab_error(err.msg())
			exit(1)
		}
	}

	sdl2_src := SDL2Source.make(sdl2_home)!
	sdl2_sem_version := semver.from(sdl2_src.version) or {
		util.vab_error('could not convert SDL2 version ${sdl2_src.version} to semantic version (semver)')
		exit(1)
	}
	if sdl2_sem_version != sdl_module_semver {
		util.vab_error('SDL2 source version (${sdl2_src.version}) must match the version of the `sdl` V module (${sdl_module_version})')
		exit(1)
	}

	opt.lib_name = 'main' // TODO: currently hardcoded everywhere...
	opt.log_tags << ['SDL', 'SDL/APP']

	// This is the real meat... Compile custom v sources and SDL2 version
	opt.libs_extra << compile_sdl_and_v(opt, sdl2_src) or {
		util.vab_error(err.msg())
		exit(1)
	}

	// Java base files will change based on what version of SDL2 we are building for
	// so we use a *fresh* custom base_files structure outside the project directory to
	// avoid leftover files from previous builds etc.
	base_files_path := os.join_path(opt.work_dir, 'base_files')
	os.rmdir_all(base_files_path) or {}
	os.mkdir_all(base_files_path) or { panic(err) }
	// Copy this project's base files as a starting point
	// `vab` implicitly resolves default_base_files_path if there is an `platform/android` directory next to the executable
	os.cp_all(android.default_base_files_path, base_files_path, true) or { panic(err) }
	// Copy needed files from SDL2 sources to base_files
	os.cp_all(sdl2_src.path_android_java_sources() or { panic(err) }, os.join_path(base_files_path,
		'src'), true) or { panic(err) }

	// TODO: some weird error when compiling.
	// error: lambda expressions are not supported in -source 7
	// Which leads to:
	// SDLAudioManager.java:37: error: cannot find symbol / Fatal Error: Unable to find method metafactory
	// PATCH / HACK: results in no audio *device* selection available
	// TODO: Check with >=2.30.7 since it might be fixed
	if sdl2_sem_version.satisfies('>=2.28.0') {
		if opt.verbosity > 0 {
			util.vab_notice('(HACK) Patching weird Java bug audio device selection will *not* work')
		}
		patches_path := os.join_path(os.dir(os.real_path(os.executable())), 'patches')
		patch_file := os.join_path(patches_path, 'PATCH_1.SDLAudioManager.java')
		patch_target_file := os.join_path(base_files_path, 'src', 'org', 'libsdl', 'app',
			'SDLAudioManager.java')
		os.cp(patch_file, patch_target_file) or { panic(err) }
	}
	//
	//////////////////////////////////////////////

	ado := opt.as_android_deploy_options() or {
		util.vab_error('Could not create deploy options', details: '${err}')
		exit(1)
	}
	deploy_opt := android.DeployOptions{
		...ado
		keystore: keystore
	}

	opt.verbose(2, 'Output will be signed with keystore at "${deploy_opt.keystore.path}"')

	screenshot_opt := opt.as_android_screenshot_options(deploy_opt)

	input_ext := os.file_ext(opt.input)

	// Early deployment of existing packages.
	if input_ext in ['.apk', '.aab'] {
		if deploy_opt.device_id != '' {
			deploy(deploy_opt)
			android.screenshot(screenshot_opt) or {
				util.vab_error('Screenshot did not succeed', details: '${err}')
				exit(1)
			}
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
	// 	util.vab_error('Compiling did not succeed', details: '${err}')
	// 	exit(1)
	// }

	apo := opt.as_android_package_options()
	pck_opt := android.PackageOptions{
		...apo
		keystore:   keystore
		base_files: base_files_path // NOTE: these are implicitly picked up by `vab` relative to the executable, this project uses a dynamic approach. See also: default_base_files_path in vab sources
		// prepare_base_fn:
	}
	android.package(pck_opt) or {
		util.vab_error('Packaging did not succeed', details: '${err}')
		cli.doctor_remedy(pck_opt, err.msg()) // Suggest possible fixes to known errors
		exit(1)
	}

	if deploy_opt.device_id != '' {
		deploy(deploy_opt)
		android.screenshot(screenshot_opt) or {
			util.vab_error('Screenshot did not succeed', details: '${err}')
			exit(1)
		}
	} else {
		if opt.verbosity > 0 {
			opt.verbose(1, 'Generated ${os.real_path(opt.output)}')
			util.vab_notice('Use `${cli.exe_short_name} --device <id> ${os.real_path(opt.output)}` to deploy package')
			util.vab_notice('Use `${cli.exe_short_name} --device <id> run ${os.real_path(opt.output)}` to both deploy and run the package')
			if deploy_opt.run != '' {
				util.vab_notice('Use `adb -s "<DEVICE ID>" shell am start -n "${deploy_opt.run}"` to run the app on the device, via adb')
			}
		}
	}
}

fn deploy(deploy_opt android.DeployOptions) {
	android.deploy(deploy_opt) or {
		util.vab_error('Deployment did not succeed', details: '${err}')
		if deploy_opt.kill_adb {
			cli.kill_adb()
		}
		exit(1)
	}
	deploy_opt.verbose(1, 'Deployed to ${deploy_opt.device_id} successfully')
	if deploy_opt.kill_adb {
		cli.kill_adb()
	}
}

fn sdl_version_from_vmod() !string {
	sdl_v_module_path := os.join_path(vxt.vmodules()!, 'sdl')
	if !os.is_dir(sdl_v_module_path) {
		return error('${exe_short_name} need the `vlang/sdl` module installed in "${sdl_v_module_path}"')
	}
	sdl_v_module_vmod_file := os.join_path(sdl_v_module_path, 'v.mod')
	vmod_contents := os.read_file(sdl_v_module_vmod_file)!
	mut sdl_module_version := vmod_contents.all_after('version:').all_before('\n').trim(" '")
	return sdl_module_version
}

fn compile_sdl_and_v(opt cli.Options, sdl2_src SDL2Source) ![]string {
	mut collect_libs := []string{}

	cache_base_path := cache_path

	// Dump meta data from V
	if opt.verbosity > 0 {
		opt.verbose(1, 'Analyzing V source')
		if opt.v_flags.len > 0 {
			println('V flags: `${opt.v_flags}`')
		}
	}

	v_meta_opt := android.VCompileOptions{
		verbosity: opt.verbosity
		cache:     opt.cache
		flags:     opt.v_flags
		work_dir:  os.join_path(opt.work_dir, 'v')
		input:     opt.input
	}

	v_meta_dump := android.v_dump_meta(v_meta_opt) or { return error(@FN + ': ${err}') }
	imported_modules := v_meta_dump.imports
	if 'sdl' !in imported_modules {
		return error('v project "${opt.input}" does not import `sdl`')
	}

	// Construct *base* build options
	base_abo := AndroidBuildOptions{
		verbosity:   opt.verbosity
		cache:       opt.cache
		work_dir:    opt.work_dir
		flags:       opt.c_flags
		ndk_version: opt.ndk_version
		api_level:   opt.api_level // sdk.default_api_level
	}

	sdl2_home := sdl2_src.root
	sdl2_version := sdl2_src.version
	sdl2_sem_version := semver.from(sdl2_src.version) or {
		return error('could not convert SDL2 version ${version} to semantic version (semver)')
	}

	opt.verbose(2, 'Using SDL2 at "${sdl2_home}" detected version: ${sdl2_version}')

	paths.ensure(cache_base_path) or {
		return error('could not ensure cache path "${cache_base_path}"')
	}

	mut sdl2_image_home := os.getenv_opt('SDL_IMAGE_HOME') or { '' }
	mut sdl2_image_version := '0.0.0'
	if 'sdl.image' in imported_modules {
		sdl2_image_home = download_and_extract_sdl2_image('2.0.5', cache_base_path, opt.verbosity)!
		sdl2_image_version = os.file_name(sdl2_image_home).all_after('SDL2_image-') // TODO: FIXME Detect version in V code
		opt.verbose(2, 'Using SDL2_image at "${sdl2_image_home}" detected version: ${sdl2_image_version}')
	}

	mut sdl2_mixer_home := os.getenv_opt('SDL_MIXER_HOME') or { '' }
	mut sdl2_mixer_version := '0.0.0'
	if 'sdl.mixer' in imported_modules {
		sdl2_mixer_home = download_and_extract_sdl2_mixer('2.0.4', cache_base_path, opt.verbosity)!
		sdl2_mixer_version = os.file_name(sdl2_mixer_home).all_after('SDL2_mixer-') // TODO: FIXME Detect version in V code
		opt.verbose(2, 'Using SDL2_mixer at "${sdl2_mixer_home}" detected version: ${sdl2_mixer_version}')
	}

	mut sdl2_ttf_home := os.getenv_opt('SDL_TTF_HOME') or { '' }
	mut sdl2_ttf_version := '0.0.0'
	if 'sdl.ttf' in imported_modules {
		sdl2_ttf_home = download_and_extract_sdl2_ttf('2.0.15', cache_base_path, opt.verbosity)!
		sdl2_ttf_version = os.file_name(sdl2_ttf_home).all_after('SDL2_ttf-') // TODO: FIXME Detect version in V code
		opt.verbose(2, 'Using SDL2_ttf at "${sdl2_ttf_home}" detected version: ${sdl2_ttf_version}')
	}

	os.rmdir_all(product_cache_path()) or {}

	apis := ndk.available_apis_by_arch(opt.ndk_version)
	for arch in opt.archs {
		mut sdl2_configs := []SDL2ConfigType{}

		mut sdl_build := &Node{
			id:   'SDL2.all.${arch}'
			note: 'Build SDL2 and SDL2 modules for ${arch} variant'
		}

		if apis[arch].len == 0 {
			return error('NDK apis for arch "${arch}" is empty: ${apis}')
		}
		min_api_level_available := apis[arch][0] // TODO
		mut sdl2_abo := AndroidBuildOptions{
			...base_abo
			version:   sdl2_version
			arch:      arch
			api_level: min_api_level_available
			work_dir:  os.join_path(base_abo.work_dir)
		}
		collect_libs << sdl2_abo.path_product_libs('SDL2') // TODO: add only once...

		// libhidapi.so must be distributed along with libc++_shared.so with SDL2 >2.0.12 <= 2.0.16
		if sdl2_sem_version.satisfies('>2.0.12 <=2.0.16') {
			opt.verbose(2, 'Should collect libhidapi.so via "${sdl2_abo.path_product_libs('hidapi')}"')
			collect_libs << sdl2_abo.path_product_libs('hidapi')

			cxx_stl_root := os.join_path(ndk.root_version(base_abo.ndk_version), 'sources',
				'cxx-stl')
			cxx_stl_libs := os.join_path(cxx_stl_root, 'llvm-libc++', 'libs')
			cxx_libcpp_shared_so := os.join_path(cxx_stl_libs, arch, 'libc++_shared.so')
			if !os.is_file(cxx_libcpp_shared_so) {
				return error('can not collect "${cxx_libcpp_shared_so}" dependency of "libhidapi.so"')
			}
			// TODO: this is a bit of a hack
			cxxstl_product_path := os.join_path(sdl2_abo.path_product_libs('cxxstl'),
				arch)
			paths.ensure(cxxstl_product_path) or { return error(@FN + ': ${err}') }
			os.cp(cxx_libcpp_shared_so, os.join_path(cxxstl_product_path, 'libc++_shared.so')) or {
				return error(@FN + ': ${err}')
			}
			collect_libs << sdl2_abo.path_product_libs('cxxstl')
		}

		sdl2_config := SDL2Config{
			abo: sdl2_abo
			src: sdl2_src
		}
		mut libsdl2 := libsdl2_node(sdl2_config) or { return error(@FN + ': ${err}') }
		sdl2_configs << sdl2_config

		if 'sdl.image' in imported_modules {
			mut abo := AndroidBuildOptions{
				...sdl2_abo
				version:  sdl2_image_version
				work_dir: os.join_path(base_abo.work_dir)
			}
			collect_libs << abo.path_product_libs('SDL2_image')
			sdl2_image_config := SDL2ImageConfig{
				abo:  abo
				root: sdl2_image_home
			}
			sdl2_configs << sdl2_image_config
			libsdl2_image := libsdl2_image_node(sdl2_image_config) or {
				return error(@FN + ': ${err}')
			}

			libsdl2.add('tasks', libsdl2_image)
		}
		if 'sdl.mixer' in imported_modules {
			mut abo := AndroidBuildOptions{
				...sdl2_abo
				version:  sdl2_mixer_version
				work_dir: os.join_path(base_abo.work_dir)
			}
			collect_libs << abo.path_product_libs('SDL2_mixer')
			collect_libs << abo.path_product_libs('mpg123')

			sdl2_mixer_config := SDL2MixerConfig{
				abo:  abo
				root: sdl2_mixer_home
			}
			sdl2_configs << sdl2_mixer_config
			libsdl2_mixer := libsdl2_mixer_node(sdl2_mixer_config) or {
				return error(@FN + ': ${err}')
			}

			libsdl2.add('tasks', libsdl2_mixer)
		}
		if 'sdl.ttf' in imported_modules {
			mut abo := AndroidBuildOptions{
				...sdl2_abo
				version:  sdl2_ttf_version
				work_dir: os.join_path(base_abo.work_dir, '${sdl2_ttf_version}')
			}
			collect_libs << abo.path_product_libs('SDL2_ttf')

			sdl2_ttf_config := SDL2TTFConfig{
				abo:  abo
				root: sdl2_ttf_home
			}
			sdl2_configs << sdl2_ttf_config
			libsdl2_ttf := libsdl2_ttf_node(sdl2_ttf_config) or { return error(@FN + ': ${err}') }

			libsdl2.add('tasks', libsdl2_ttf)
		}

		sdl_build.add('tasks', libsdl2)

		mut v_build := AndroidNode{
			id:   'V.${arch}'
			Node: &Node{
				id:   'V.${arch}'
				note: 'Build V sources for ${arch} variant'
			}
		}

		aco := opt.as_android_compile_options()
		v_config := VSDL2Config{
			sdl2_configs: sdl2_configs
			abo:          AndroidBuildOptions{
				...sdl2_abo
				cache: false // TODO: hack, always rebuild "libmain.so"
			}
			aco:          aco
		}
		mut libv := libv_node(v_config) or { return error(@FN + ': ${err}') }

		collect_libs << v_config.abo.path_product_libs(opt.lib_name)
		v_build.add('dependencies', sdl_build)
		v_build.add('tasks', libv)

		v_build.build() or { return error(@FN + ': ${err}') }
	}
	return collect_libs
}

// sdl_options_from_arguments returns an `Options` merged from (CLI/Shell -style) `arguments` using `defaults` as
// values where no value can be matched in `arguments`.
fn sdl_options_from_arguments(arguments []string, defaults Options) !(Options, []string) {
	mut options, unmatched := flag.using[Options](defaults, arguments,
		style: .v_flag_parser
		mode:  .relaxed
	)!
	return options, unmatched
}

fn download_and_extract_archive(version string, source_archive_url string, path string, verbosity int) !string {
	source_archive := os.file_name(source_archive_url)
	source_archive_temp_path := os.join_path(path, source_archive)
	if !os.exists(source_archive_temp_path) {
		if verbosity > 1 {
			println('Downloading `${source_archive}` from "${source_archive_url}" to "${source_archive_temp_path}"...')
		}
		http.download_file(source_archive_url, source_archive_temp_path) or {
			return error('failed to download `${source_archive_url}` needed for automatic SDL2 Android support: ${err}')
		}
	}
	// Unpack
	unpack_path := os.join_path(path, version)
	extract_root := os.join_path(unpack_path, source_archive.all_before_last('.'))
	if !os.exists(extract_root) {
		if verbosity > 1 {
			println('Unpacking "${source_archive_temp_path}" to "${unpack_path}"...')
		}
		os.rmdir_all(unpack_path) or {}
		os.mkdir_all(unpack_path) or {
			return error('failed create unpack directory "${unpack_path}" for "${source_archive}": ${err}')
		}
		vabutil.unzip(source_archive_temp_path, unpack_path) or {
			return error('failed to extract "${source_archive_temp_path}" to "${unpack_path}": ${err}')
		}
	}
	return extract_root
}

fn download_and_extract_sdl2(sdl_version string, path string, verbosity int) !string {
	source_archive_url := sdl2_source_downloads[sdl_version] or {
		return error('SDL2 source archive for ${sdl_version} could not be found for download')
	}
	extract_root := download_and_extract_archive(sdl_version, source_archive_url, path,
		verbosity)!
	return extract_root
}

fn download_and_extract_sdl2_image(sdl_image_version string, path string, verbosity int) !string {
	source_archive_url := sdl2_image_source_downloads[sdl_image_version] or {
		return error('SDL2_Image source archive for ${sdl_image_version} could not be found for download')
	}
	final_path := os.join_path(path, 'SDL2_image')
	paths.ensure(final_path) or { return error('could not ensure cache path "${final_path}"') }
	extract_root := download_and_extract_archive(sdl_image_version, source_archive_url,
		final_path, verbosity)!
	return extract_root
}

fn download_and_extract_sdl2_mixer(sdl_mixer_version string, path string, verbosity int) !string {
	source_archive_url := sdl2_mixer_source_downloads[sdl_mixer_version] or {
		return error('SDL2_mixer source archive for ${sdl_mixer_version} could not be found for download')
	}
	final_path := os.join_path(path, 'SDL2_mixer')
	paths.ensure(final_path) or { return error('could not ensure cache path "${final_path}"') }
	extract_root := download_and_extract_archive(sdl_mixer_version, source_archive_url,
		final_path, verbosity)!
	return extract_root
}

fn download_and_extract_sdl2_ttf(sdl_ttf_version string, path string, verbosity int) !string {
	source_archive_url := sdl2_ttf_source_downloads[sdl_ttf_version] or {
		return error('SDL2_ttf source archive for ${sdl_ttf_version} could not be found for download')
	}
	final_path := os.join_path(path, 'SDL2_ttf')
	paths.ensure(final_path) or { return error('could not ensure cache path "${final_path}"') }
	extract_root := download_and_extract_archive(sdl_ttf_version, source_archive_url,
		final_path, verbosity)!
	return extract_root
}

// sdl_doctor prints various information related to the SDL setup that will be used
// for the Android compilation.
fn sdl_doctor(opt Options) {
	println('SDL')
	println('\tenv')
	if env_version := os.getenv_opt('SDL_VERSION') {
		println('\t\tSDL_VERSION ${env_version}')
	}
	if sdl_home := os.getenv_opt('SDL_HOME') {
		println('\t\tSDL_HOME ${sdl_home}')
	}
	if sdl_image_home := os.getenv_opt('SDL_IMAGE_HOME') {
		println('\t\tSDL_IMAGE_HOME ${sdl_image_home}')
	}
	if sdl_mixer_home := os.getenv_opt('SDL_MIXER_HOME') {
		println('\t\tSDL_MIXER_HOME ${sdl_mixer_home}')
	}
	if sdl_ttf_home := os.getenv_opt('SDL_TTF_HOME') {
		println('\t\tSDL_TTF_HOME ${sdl_ttf_home}')
	}
	println('\tVersion')
	if vmod_version := sdl_version_from_vmod() {
		println('\t\tv.mod  ${vmod_version}')
	}
	println('\t\tTarget ${opt.sdl_version}')
	println('\tENV')
	println('\t\tCache path ${cache_path}')
}

fn ab_commit_hash() string {
	mut hash := ''
	git_exe := os.find_abs_path_of_executable('git') or { '' }
	if git_exe != '' {
		mut git_cmd := 'git -C "${exe_dir}" rev-parse --short HEAD'
		$if windows {
			git_cmd = 'git.exe -C "${exe_dir}" rev-parse --short HEAD'
		}
		res := os.execute(git_cmd)
		if res.exit_code == 0 {
			hash = res.output
		}
	}
	return hash
}

fn version_full() string {
	return '${exe_version} ${exe_git_hash}'
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
