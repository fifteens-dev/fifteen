#!/usr/bin/env ruby
# frozen_string_literal: true

# ios/Runner/LiveActivityChannel.swift を Runner ターゲットのソースに追加する。
# 冪等: 既に追加済みなら何もしない。

require 'xcodeproj'

project = Xcodeproj::Project.open(File.expand_path('../Runner.xcodeproj', __dir__))
target  = project.targets.find { |t| t.name == 'Runner' }
raise 'Runner target not found' unless target

name = 'LiveActivityChannel.swift'
if target.source_build_phase.files.any? { |f| f.file_ref&.path == name }
  puts "[skip] #{name} already in Runner"
  exit 0
end

group = project.main_group.find_subpath('Runner', true)
ref = group.files.find { |f| f.path == name } || group.new_reference(name)
target.source_build_phase.add_file_reference(ref)
project.save
puts "[ok] added #{name} to Runner"
