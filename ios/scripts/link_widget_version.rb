#!/usr/bin/env ruby
# frozen_string_literal: true

# FifteensWidget の各ビルド構成に Flutter の Generated.xcconfig を base configuration
# として設定する。これで拡張の Info.plist からも $(FLUTTER_BUILD_NAME) /
# $(FLUTTER_BUILD_NUMBER) が解決でき、アプリ本体とバージョンが常に一致する
# （App Store の検証は本体と拡張のバージョン一致を要求する）。

require 'xcodeproj'

project = Xcodeproj::Project.open(File.expand_path('../Runner.xcodeproj', __dir__))
widget  = project.targets.find { |t| t.name == 'FifteensWidget' }
raise 'FifteensWidget target not found' unless widget

generated = project.files.find { |f| f.path.to_s.end_with?('Generated.xcconfig') }
unless generated
  flutter_group = project.main_group.find_subpath('Flutter', true)
  generated = flutter_group.new_file('Flutter/Generated.xcconfig')
end

widget.build_configurations.each do |config|
  config.base_configuration_reference = generated
  # Info.plist 側で参照するため、ターゲット固有の定義は置かない。
  config.build_settings.delete('MARKETING_VERSION')
  config.build_settings.delete('CURRENT_PROJECT_VERSION')
end

project.save
puts '[ok] linked FifteensWidget build configurations to Generated.xcconfig'
