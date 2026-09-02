#!/usr/bin/env ruby
# frozen_string_literal: true

# Runner.xcodeproj に Live Activity 用の Widget Extension ターゲットを追加する。
#
#   GEM_HOME=<cocoapods libexec> ruby ios/scripts/add_live_activity_target.rb
#
# 冪等: 既に FifteensWidget ターゲットがある場合は何もしない。
# 実行前に project.pbxproj のバックアップを取ること（呼び出し側で実施）。

require 'xcodeproj'

PROJECT_PATH   = File.expand_path('../Runner.xcodeproj', __dir__)
TARGET_NAME    = 'FifteensWidget'
APP_TARGET     = 'Runner'
APP_BUNDLE_ID  = 'com.fifteens.sns'
WIDGET_BUNDLE  = "#{APP_BUNDLE_ID}.#{TARGET_NAME}"
DEPLOYMENT     = '16.2'
SHARED_GROUP   = 'LiveActivityShared'

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "[skip] target #{TARGET_NAME} already exists"
  exit 0
end

app_target = project.targets.find { |t| t.name == APP_TARGET }
raise "#{APP_TARGET} target not found" unless app_target

# ── 1) ターゲット本体 ─────────────────────────────────────────
widget = project.new_target(
  :app_extension,
  TARGET_NAME,
  :ios,
  DEPLOYMENT,
  nil,
  :swift
)

# ── 2) ファイルグループ（拡張のソース） ──────────────────────
widget_group = project.main_group.find_subpath(TARGET_NAME, true)
widget_group.set_source_tree('SOURCE_ROOT')
widget_group.set_path(TARGET_NAME)

%w[FifteensWidgetBundle.swift MusicMemoryLiveActivity.swift].each do |name|
  ref = widget_group.new_reference(name)
  widget.source_build_phase.add_file_reference(ref)
end

# Info.plist / entitlements はビルド設定から参照するだけ（ビルドフェーズには入れない）
%w[Info.plist FifteensWidget.entitlements].each { |name| widget_group.new_reference(name) }

assets = widget_group.new_reference('Assets.xcassets')
widget.resources_build_phase.add_file_reference(assets)

# ── 3) 共有ソース（アプリ本体と拡張の両方に入れる） ──────────
shared_group = project.main_group.find_subpath(SHARED_GROUP, true)
shared_group.set_source_tree('SOURCE_ROOT')
shared_group.set_path(SHARED_GROUP)
shared_ref = shared_group.files.find { |f| f.path == 'MusicMemoryActivityAttributes.swift' } ||
             shared_group.new_reference('MusicMemoryActivityAttributes.swift')
[widget, app_target].each do |t|
  next if t.source_build_phase.files_references.include?(shared_ref)
  t.source_build_phase.add_file_reference(shared_ref)
end

# ── 4) ビルド設定 ────────────────────────────────────────────
widget.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER']          = WIDGET_BUNDLE
  s['PRODUCT_NAME']                       = '$(TARGET_NAME)'
  s['INFOPLIST_FILE']                     = "#{TARGET_NAME}/Info.plist"
  s['CODE_SIGN_ENTITLEMENTS']             = "#{TARGET_NAME}/#{TARGET_NAME}.entitlements"
  s['IPHONEOS_DEPLOYMENT_TARGET']         = DEPLOYMENT
  s['SWIFT_VERSION']                      = '5.0'
  s['TARGETED_DEVICE_FAMILY']             = '1,2'
  s['SKIP_INSTALL']                       = 'YES'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  s['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = 'WidgetBackground'
  s['GENERATE_INFOPLIST_FILE']            = 'NO'
  s['MARKETING_VERSION']                  = '$(MARKETING_VERSION)'
  s['CURRENT_PROJECT_VERSION']            = '$(CURRENT_PROJECT_VERSION)'
  s['CODE_SIGN_STYLE']                    = 'Automatic'
  s['ENABLE_USER_SCRIPT_SANDBOXING']      = 'NO'
  # Flutter の Runner と同じ Team を引き継ぐ（未設定なら Xcode で選択する）
  team = app_target.build_configurations.first.build_settings['DEVELOPMENT_TEAM']
  s['DEVELOPMENT_TEAM'] = team if team && !team.to_s.empty?
end

# ── 5) アプリ本体に埋め込む（Embed App Extensions） ──────────
embed = app_target.build_phases.find do |phase|
  phase.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) &&
    phase.name == 'Embed App Extensions'
end
embed ||= begin
  phase = app_target.new_copy_files_build_phase('Embed App Extensions')
  phase.symbol_dst_subfolder_spec = :plug_ins
  phase
end
build_file = embed.add_file_reference(widget.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# 拡張は本体より先にビルドする
app_target.add_dependency(widget)

# Embed フェーズは「Thin Binary」(Flutter)より後ろだと署名で問題が出ることがあるため、
# Copy Bundle Resources の直後に置く。
phases = app_target.build_phases
if (idx = phases.index(embed))
  phases.delete_at(idx)
  resources_idx = phases.index(app_target.resources_build_phase) || (phases.size - 1)
  phases.insert(resources_idx + 1, embed)
end

project.save
puts "[ok] added target #{TARGET_NAME} (#{WIDGET_BUNDLE})"
