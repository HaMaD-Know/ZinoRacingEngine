class_name ZinoBuildService
extends RefCounted
## Build Center backend: validates a project for iOS/Windows, generates icons and export presets,
## and runs Godot's official exporter. iOS export on Windows produces the Xcode project; compiling
## and signing happen on macOS (Xcode locally, or the generated GitHub Actions workflow).
## No signing credentials are ever written: the Apple Team ID is a public identifier, certificates
## and profiles stay in Xcode / CI secrets.

const PLATFORMS := {"ios": "iOS", "windows": "Windows Desktop"}
const INCLUDE := "*.zscene, *.zblocks, *.zino, *.json"
const EXCLUDE := "Builds/*, Cache/*, .github/*"
const MOBILE_MEMORY_WARN_MB := 900.0

## Godot editor binary used for exports (set by the app from Settings; falls back to the running binary in development).
static var godot_override := ""

static func godot_exe() -> String:
	var exe := godot_override if godot_override != "" else OS.get_executable_path()
	var console := exe.get_basename() + "_console.exe"
	return console if FileAccess.file_exists(console) else exe

static func templates_dir() -> String:
	var v := Engine.get_version_info()
	var ver := "%d.%d.%d.%s" % [v.major, v.minor, v.patch, v.status]
	var sc := godot_exe().get_base_dir().path_join("editor_data/export_templates").path_join(ver)
	if DirAccess.dir_exists_absolute(sc):
		return sc
	return OS.get_data_dir().get_base_dir().path_join("Godot/export_templates").path_join(ver)

static func templates_installed(platform: String) -> bool:
	var f := "ios.zip" if platform == "ios" else "windows_release_x86_64.exe"
	return FileAccess.file_exists(templates_dir().path_join(f))

## Returns [{level: "error"|"warning"|"ok", message}] — errors block the export.
static func validate(dir: String, manifest: Dictionary, platform: String) -> Array:
	var out: Array = []
	var add := func(level, msg): out.append({"level": level, "message": msg})
	var proj: Dictionary = manifest.get("project", {})
	if not templates_installed(platform):
		add.call("error", "Godot export templates for %s are not installed (%s)." % [PLATFORMS[platform], templates_dir()])
	var version := str(proj.get("version", ""))
	var vr := RegEx.new()
	vr.compile("^\\d+(\\.\\d+){0,2}$")
	if vr.search(version) == null:
		add.call("error", "Version must look like 1.0 or 1.0.0 (Project Settings).")
	if platform == "ios":
		var bid := str(proj.get("bundleIdentifier", ""))
		var br := RegEx.new()
		br.compile("^[A-Za-z][A-Za-z0-9-]*(\\.[A-Za-z0-9-]+)+$")
		if br.search(bid) == null:
			add.call("error", "Bundle identifier '%s' is invalid (reverse-DNS, e.g. com.studio.game)." % bid)
		elif bid.begins_with("com.example."):
			add.call("warning", "Bundle identifier still uses com.example — change it before publishing.")
		var team := str(manifest.get("ios", {}).get("teamId", ""))
		var tr := RegEx.new()
		tr.compile("^[A-Z0-9]{10}$")
		if tr.search(team) == null:
			add.call("error", "Apple Team ID missing or invalid (10 characters from developer.apple.com › Membership). It is an identifier, not a password.")
		var godot := FileAccess.get_file_as_string(dir.path_join("project.godot"))
		if not godot.contains("rendering_method.mobile"):
			add.call("warning", "project.godot has no Mobile renderer override; iOS will use Forward+ (slower).")
		if not godot.contains("import_etc2_astc=true"):
			add.call("error", "ETC2/ASTC texture compression is off (required for iOS).")
		var preset := str(manifest.get("graphics", {}).get("gameOutput", "ultraMax"))
		if preset in ["ultraMax", "ultra", "high"]:
			add.call("warning", "Game output is %s: SDFGI, SSR, SSIL and volumetric fog are unavailable on the iOS Mobile renderer; the rest of the preset applies." % ZinoGraphics.label(preset))
	# Assets: size, big textures, missing references.
	var total := 0
	var big: Array = []
	for f in _files(dir.path_join("Assets")):
		var size := FileAccess.get_size(f)
		total += size
		if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "exr", "hdr"] and size > 12 * 1048576:
			big.append(f.get_file())
	if not big.is_empty():
		add.call("warning", "Very large textures (%s) — consider 2K versions for mobile." % ", ".join(big.slice(0, 5)))
	var est_mb := 150.0 + total / 1048576.0 * 1.6
	if platform == "ios" and est_mb > MOBILE_MEMORY_WARN_MB:
		add.call("warning", "Estimated memory use %.0f MB may be too high for older iPhones." % est_mb)
	for miss in missing_references(dir, manifest):
		add.call("error", "Missing asset: " + miss)
	var start := str(manifest.get("startScene", ""))
	if not FileAccess.file_exists(dir.path_join(start)):
		add.call("error", "Start scene missing: " + start)
	if out.filter(func(x): return x.level == "error").is_empty():
		add.call("ok", "Ready to export for %s (assets %.1f MB, estimated memory %.0f MB)." % [PLATFORMS[platform], total / 1048576.0, est_mb])
	return out

## Asset paths referenced by scenes that do not exist in the project.
static func missing_references(dir: String, manifest: Dictionary) -> Array:
	var missing: Array = []
	for rel in manifest.get("scenes", []):
		var r := ZinoFormat.read_json_file(dir.path_join(str(rel)))
		if not r.ok:
			continue
		var refs: Array = []
		var st: Dictionary = r.data.get("settings", {})
		for k in ["skyHdri"]:
			if str(st.get(k, "")) != "":
				refs.append(str(st[k]))
		if str(st.get("audio", {}).get("music", "")) != "":
			refs.append(str(st.audio.music))
		for e in r.data.get("entities", []):
			var m = e.get("vehicle", {}).get("spec", {}).get("model")
			if m is Dictionary:
				refs.append(str(m.get("path", "")))
			if e.get("model") is Dictionary:
				refs.append(str(e.model.get("path", "")))
			var mat = e.get("mesh", {}).get("material", {})
			for k in ["albedoTexture", "normalTexture", "roughnessTexture"]:
				if mat is Dictionary and str(mat.get(k, "")) != "":
					refs.append(str(mat[k]))
		for p in refs:
			if p != "" and not FileAccess.file_exists(dir.path_join(p)) and not p in missing:
				missing.append(p)
	return missing

static func _files(root: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".import"):
			out.append(root.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files(root.path_join(sub)))
	return out

## Renders icon.svg to Config/icon_1024.png (iOS needs PNG icons).
static func make_icon(dir: String) -> String:
	var svg := FileAccess.get_file_as_string(dir.path_join("icon.svg"))
	var img := Image.new()
	if svg == "" or img.load_svg_from_string(svg, 1024.0 / 128.0) != OK:
		img = Image.create(1024, 1024, false, Image.FORMAT_RGB8)
		img.fill(Color("1e1e1e"))
	img.resize(1024, 1024)
	img.convert(Image.FORMAT_RGB8)   # App Store icons must not have alpha
	DirAccess.make_dir_recursive_absolute(dir.path_join("Config"))
	img.save_png(dir.path_join("Config/icon_1024.png"))
	return "res://Config/icon_1024.png"

static func output_path(dir: String, manifest: Dictionary, platform: String) -> String:
	var name := str(manifest.get("project", {}).get("name", "Game")).validate_filename().replace(" ", "")
	return dir.path_join("Builds/%s/%s.%s" % ["iOS" if platform == "ios" else "Windows", name, "ipa" if platform == "ios" else "exe"])

## Writes export_presets.cfg (iOS + Windows). Signing secrets are never written.
static func write_export_presets(dir: String, manifest: Dictionary) -> Error:
	var icon := make_icon(dir)
	var proj: Dictionary = manifest.get("project", {})
	var ios: Dictionary = manifest.get("ios", {})
	var name := str(proj.get("name", "Game")).replace("\"", "")
	var ver := str(proj.get("version", "1.0.0"))
	var family: int = {"iphone": 0, "ipad": 1, "both": 2}.get(str(ios.get("devices", "both")), 2)
	var text := """[preset.0]

name="iOS"
platform="iOS"
runnable=false
export_filter="all_resources"
include_filter="%s"
exclude_filter="%s"
export_path="%s"

[preset.0.options]

application/app_store_team_id="%s"
application/bundle_identifier="%s"
application/short_version="%s"
application/version="%s"
application/export_project_only=true
application/targeted_device_family=%d
application/min_ios_version="15.0"
icons/icon_1024x1024="%s"
capabilities/access_wifi=false

[preset.1]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="%s"
exclude_filter="%s"
export_path="%s"

[preset.1.options]

binary_format/embed_pck=true
application/product_name="%s"
application/file_version="%s"
application/product_version="%s"
""" % [INCLUDE, EXCLUDE, output_path(dir, manifest, "ios").replace(dir + "/", ""), str(ios.get("teamId", "")),
		str(proj.get("bundleIdentifier", "")), ver, ver, family, icon, INCLUDE, EXCLUDE,
		output_path(dir, manifest, "windows").replace(dir + "/", ""), name, _win_version(ver), _win_version(ver)]
	var godot_path := dir.path_join("project.godot")
	var godot := FileAccess.get_file_as_string(godot_path)
	if godot.contains("config/icon=\"res://icon.svg\""):
		ZinoFormat.write_text_atomic(godot_path, godot.replace("config/icon=\"res://icon.svg\"", "config/icon=\"%s\"" % icon), false)
	return ZinoFormat.write_text_atomic(dir.path_join("export_presets.cfg"), text, false)

static func _win_version(v: String) -> String:
	var parts := v.split(".")
	while parts.size() < 4:
		parts.append("0")
	return ".".join(parts.slice(0, 4))

## Runs a blocking export (call from a thread). Returns {ok, code, log, output}.
static func export(dir: String, manifest: Dictionary, platform: String) -> Dictionary:
	var out := output_path(dir, manifest, platform)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var exe := godot_exe()
	var log: Array = []
	OS.execute(exe, ["--headless", "--path", dir, "--import"], log, true)
	var log2: Array = []
	var code := OS.execute(exe, ["--headless", "--path", dir, "--export-release", PLATFORMS[platform], out], log2, true)
	var text := "\n".join(log2)
	var ok := code == 0 and not text.contains("failed") and (FileAccess.file_exists(out) or DirAccess.dir_exists_absolute(out.get_base_dir().path_join(out.get_file().get_basename() + ".xcodeproj")))
	return {"ok": ok, "code": code, "log": text, "output": out}

## GitHub Actions workflow that builds the iPhone app on a macOS runner.
## Without secrets it makes an UNSIGNED .ipa (proves the build works; a sideloading tool can re-sign it).
## With the Apple secrets it makes a SIGNED .ipa (TestFlight/App Store, ad-hoc or development).
## Signing material lives only in GitHub repository secrets, never in the project.
static func write_ci_workflow(dir: String, manifest: Dictionary) -> Error:
	var name := str(manifest.get("project", {}).get("name", "Game")).validate_filename().replace(" ", "")
	var yml := """# Generated by Zino Racing Engine — builds your iPhone app (.ipa) on GitHub's macOS runners.
# Run it: GitHub › Actions › "iOS build" › Run workflow. The .ipa is attached to the finished run.
#
# No secrets  → UNSIGNED .ipa (checks that everything builds; re-sign it with a sideloading tool).
# With these repository secrets (Settings › Secrets and variables › Actions) → SIGNED .ipa:
#   APPLE_TEAM_ID                    10-character Team ID from developer.apple.com › Membership
#   IOS_CERTIFICATE_P12_BASE64       your signing certificate (.p12), base64-encoded
#   IOS_CERTIFICATE_PASSWORD         the password you gave the .p12
#   IOS_PROVISIONING_PROFILE_BASE64  the provisioning profile (.mobileprovision), base64-encoded
# Never commit certificates, profiles or passwords to the repository.
name: iOS build
on:
  workflow_dispatch:
    inputs:
      method:
        description: "Signed build type (only used when the signing secrets are set)"
        type: choice
        options: [app-store-connect, ad-hoc, development]
        default: app-store-connect
env:
  APP: %s
  GODOT: "%s"
jobs:
  ios:
    runs-on: macos-26
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - name: Use the newest Xcode (Godot 4.7 needs the iOS 26 SDK)
        run: |
          X="$(ls -d /Applications/Xcode_2[6-9]*.app 2>/dev/null | grep -v -i beta | sort -V | tail -1)"
          if [ -z "$X" ]; then X="$(ls -d /Applications/Xcode*.app | sort -V | tail -1)"; fi
          sudo xcode-select -s "$X"
          xcodebuild -version
      - name: Install Godot and export templates
        run: |
          curl -fsSL -o godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT}-stable/Godot_v${GODOT}-stable_macos.universal.zip"
          unzip -q godot.zip -d "$RUNNER_TEMP"
          curl -fsSL -o tpl.tpz "https://github.com/godotengine/godot/releases/download/${GODOT}-stable/Godot_v${GODOT}-stable_export_templates.tpz"
          T="$HOME/Library/Application Support/Godot/export_templates/${GODOT}.stable"
          mkdir -p "$T"
          unzip -q tpl.tpz -d "$RUNNER_TEMP/tpl"
          mv "$RUNNER_TEMP"/tpl/templates/* "$T/"
          rm -f godot.zip tpl.tpz
      - name: Export Xcode project
        env:
          TEAM: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          sed -i '' "s/^application\\/app_store_team_id=.*/application\\/app_store_team_id=\\"${TEAM:-AAAAAAAAAA}\\"/" export_presets.cfg
          mkdir -p Builds/iOS
          "$RUNNER_TEMP/Godot.app/Contents/MacOS/Godot" --headless --path . --import || true
          "$RUNNER_TEMP/Godot.app/Contents/MacOS/Godot" --headless --path . --export-release "iOS" "Builds/iOS/${APP}.ipa"
          test -d "Builds/iOS/${APP}.xcodeproj"
      - name: Choose signed or unsigned
        id: mode
        env:
          P12: ${{ secrets.IOS_CERTIFICATE_P12_BASE64 }}
          TEAM: ${{ secrets.APPLE_TEAM_ID }}
          PROFILE: ${{ secrets.IOS_PROVISIONING_PROFILE_BASE64 }}
        run: |
          if [ -n "$P12" ] && [ -n "$TEAM" ] && [ -n "$PROFILE" ]; then echo "signed=true" >> "$GITHUB_OUTPUT"; else echo "signed=false" >> "$GITHUB_OUTPUT"; echo "::notice::No signing secrets: building an UNSIGNED .ipa"; fi
      - name: Build unsigned .ipa
        if: steps.mode.outputs.signed != 'true'
        run: |
          xcodebuild -project "Builds/iOS/${APP}.xcodeproj" -scheme "$APP" -configuration Release -destination "generic/platform=iOS" -archivePath "build/${APP}.xcarchive" archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""
          mkdir -p build/ipa/Payload
          cp -R "build/${APP}.xcarchive/Products/Applications/"*.app build/ipa/Payload/
          cd build/ipa && zip -qry "${APP}-unsigned.ipa" Payload && rm -rf Payload
      - name: Build signed .ipa
        if: steps.mode.outputs.signed == 'true'
        env:
          P12: ${{ secrets.IOS_CERTIFICATE_P12_BASE64 }}
          P12_PASSWORD: ${{ secrets.IOS_CERTIFICATE_PASSWORD }}
          PROFILE: ${{ secrets.IOS_PROVISIONING_PROFILE_BASE64 }}
          TEAM: ${{ secrets.APPLE_TEAM_ID }}
          METHOD: ${{ inputs.method }}
        run: |
          KC="$RUNNER_TEMP/build.keychain-db"
          KC_PW="$(uuidgen)"
          echo "$P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security create-keychain -p "$KC_PW" "$KC"
          security set-keychain-settings -lut 21600 "$KC"
          security unlock-keychain -p "$KC_PW" "$KC"
          security import "$RUNNER_TEMP/cert.p12" -k "$KC" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PW" "$KC"
          security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
          echo "$PROFILE" | base64 --decode > "$RUNNER_TEMP/app.mobileprovision"
          UUID="$(security cms -D -i "$RUNNER_TEMP/app.mobileprovision" | plutil -extract UUID raw -)"
          mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
          cp "$RUNNER_TEMP/app.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$UUID.mobileprovision"
          BUNDLE="$(grep '^application/bundle_identifier=' export_presets.cfg | cut -d'"' -f2)"
          if [ "$METHOD" = "development" ]; then IDENTITY="Apple Development"; else IDENTITY="Apple Distribution"; fi
          xcodebuild -project "Builds/iOS/${APP}.xcodeproj" -scheme "$APP" -configuration Release -destination "generic/platform=iOS" -archivePath "build/${APP}.xcarchive" archive CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="$IDENTITY" PROVISIONING_PROFILE_SPECIFIER="$UUID" OTHER_CODE_SIGN_FLAGS="--keychain $KC"
          rm -f ExportOptions.plist
          /usr/libexec/PlistBuddy -c "Add :method string $METHOD" -c "Add :teamID string $TEAM" -c "Add :signingStyle string manual" -c "Add :signingCertificate string $IDENTITY" -c "Add :provisioningProfiles dict" -c "Add :provisioningProfiles:$BUNDLE string $UUID" ExportOptions.plist
          xcodebuild -exportArchive -archivePath "build/${APP}.xcarchive" -exportPath build/ipa -exportOptionsPlist ExportOptions.plist
          security delete-keychain "$KC"
          rm -f "$RUNNER_TEMP/cert.p12" "$RUNNER_TEMP/app.mobileprovision"
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ env.APP }}-ipa
          path: build/ipa
          if-no-files-found: error
""" % [name, _gv()]
	DirAccess.make_dir_recursive_absolute(dir.path_join(".github/workflows"))
	return ZinoFormat.write_text_atomic(dir.path_join(".github/workflows/zino-ios.yml"), yml, false)

static func _gv() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v.major, v.minor, v.patch]
