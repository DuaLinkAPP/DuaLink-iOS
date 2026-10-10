# SPDX-License-Identifier: MPL-2.0
# Optional maintainer tool; Xcode users open the generated project directly.
require 'pathname'
require 'xcodeproj'

root = Pathname.new(__dir__).parent
output = root.join('DuaLink.xcodeproj')
abort 'Project already exists; review it before regenerating.' if output.exist?
project = Xcodeproj::Project.new(output)
config = project.main_group.new_group('Config', 'Config')
public_config = config.new_file('Public.xcconfig')
config.new_file('Local.xcconfig.example')
project.build_configurations.each { |item| item.base_configuration_reference = public_config }

def configure(target, bundle_suffix, info, entitlements)
  target.build_configurations.each do |item|
    settings = item.build_settings
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = '$(DUALINK_BUNDLE_ID_PREFIX)' + bundle_suffix
    settings['INFOPLIST_FILE'] = info
    settings['CODE_SIGN_ENTITLEMENTS'] = entitlements
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['SWIFT_VERSION'] = '5.0'
    settings['SWIFT_STRICT_CONCURRENCY'] = 'complete'
    settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DUALINK_NOTIFICATIONS_PRODUCT' + (item.name == 'Debug' ? ' DEBUG' : '')
    settings['IPHONEOS_DEPLOYMENT_TARGET'] = '26.5'
    settings['TARGETED_DEVICE_FAMILY'] = '1'
    settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
    settings['CURRENT_PROJECT_VERSION'] = '1'
    settings['MARKETING_VERSION'] = '1.0.0'
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
    settings['SUPPORTS_MACCATALYST'] = 'NO'
    settings['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
    settings.delete('DEVELOPMENT_TEAM')
    settings.delete('PROVISIONING_PROFILE_SPECIFIER')
    settings.delete('PROVISIONING_PROFILE')
    settings.delete('CODE_SIGN_IDENTITY')
    settings['SKIP_INSTALL'] = 'YES' unless target.name == 'DuaLink'
  end
end

references = {}
%w[App NotificationLab].each do |directory|
  group = project.main_group.new_group(directory, directory)
  Dir[root.join(directory, '**/*')].sort.each do |path|
    next unless File.file?(path)
    relative = Pathname.new(path).relative_path_from(root.join(directory)).to_s
    next if relative.split('/').any? { |part| part.start_with?('.') }
    next unless %w[.swift .plist .entitlements .xcprivacy].include?(File.extname(path))
    references["#{directory}/#{relative}"] = group.new_file(relative)
  end
end

main = project.new_target(:application, 'DuaLink', :ios, '26.5')
configure(main, '', 'App/Info.plist', 'App/DuaLink.entitlements')
app_sources = references.select { |path, _| path.start_with?('App/') && path.end_with?('.swift') }.values
shared = %w[LabBuildConfiguration InteropMessageMode InteropModeStore LabProtocol LabReconnectPolicy]
app_sources += shared.map { |name| references.fetch("NotificationLab/Shared/#{name}.swift") }
app_sources += references.select { |path, _| path.start_with?('NotificationLab/ProductCore/') && path.end_with?('.swift') }.values
main.add_file_references(app_sources)
app_group = project.main_group.groups.find { |group| group.path == 'App' }
%w[Assets.xcassets DuaLink.icon].each do |name|
  main.resources_build_phase.add_file_reference(app_group.new_file(name))
end
main.resources_build_phase.add_file_reference(references.fetch('App/PrivacyInfo.xcprivacy'))
main.build_configurations.each do |item|
  item.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'DuaLink'
  item.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'DuaLink'
  item.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
end

# Explicit public source lists avoid copying private project settings or history.
common = %w[LabBuildConfiguration InteropMessageMode InteropModeStore LabMessageModeGate LabProtocol LabDiagnostics LabResponseLedger LabFrameCodec]
connections = %w[LabP256PublicKey LabReconnectPolicy LabReceiveBuffer LabSubscriptionState]
groups = {
  'DataProvider' => common + %w[LabLiveActivityPipeline],
  'Security' => common + connections,
  'Transport' => common + connections.reject { |name| name == 'LabP256PublicKey' }
}
embed = main.new_copy_files_build_phase('Embed Notification Extensions')
embed.dst_subfolder_spec = '16'
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Extensions'
groups.each do |name, shared_names|
  target = project.new_target(:app_extension, "DuaLink#{name}", :ios, '26.5')
  target.product_type = 'com.apple.product-type.extensionkit-extension'
  target.product_reference.explicit_file_type = 'wrapper.app-extension'
  configure(target, ".#{name.downcase}", "NotificationLab/ProductExtensions/#{name}/Info.plist", "NotificationLab/ProductExtensions/#{name}/Product.entitlements")
  target.build_configurations.each do |item|
    item.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    item.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  end
  sources = shared_names.map { |item| references.fetch("NotificationLab/Shared/#{item}.swift") }
  sources += references.select { |path, _| path.start_with?("NotificationLab/Extensions/#{name}/") && path.end_with?('.swift') }.values
  sources += references.select { |path, _| path.start_with?("NotificationLab/ProductExtensions/#{name}/") && path.end_with?('.swift') }.values
  if name != 'DataProvider'
    sources += references.select { |path, _| path.start_with?('NotificationLab/Bluetooth/') && path.end_with?('.swift') }.values
  end
  target.add_file_references(sources)
  target.resources_build_phase.add_file_reference(references.fetch("NotificationLab/ProductExtensions/#{name}/PrivacyInfo.xcprivacy"))
  main.add_dependency(target)
  file = embed.add_file_reference(target.product_reference, true)
  file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(main)
scheme.set_launch_target(main)
scheme.save_as(output, 'DuaLink', true)
puts 'Generated neutral project: one companion app and three extensions.'
