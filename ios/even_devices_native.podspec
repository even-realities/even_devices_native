Pod::Spec.new do |s|
  s.name             = 'even_devices_native'
  s.version          = '0.1.0-beta.11'
  s.summary          = 'Flutter adapter for the native Even G2 enterprise SDK.'
  s.description      = 'Native Swift owns license validation, G2 authorization and connection sessions.'
  s.homepage         = 'https://www.evenrealities.com'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Even Realities' => 'developer@evenrealities.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  # This package links the standalone SDK only, without a legacy BLE plugin.
  s.vendored_frameworks = 'Frameworks/EvenDevicesSDK.xcframework'
  s.frameworks       = 'CoreBluetooth'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = { 'even_devices_native_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
end
