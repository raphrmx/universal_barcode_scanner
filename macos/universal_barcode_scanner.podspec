#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'universal_barcode_scanner'
  s.version          = '1.2.0'
  s.summary          = 'Barcode and QR code scanner for Flutter.'
  s.description      = <<-DESC
Barcode and QR code scanner for Flutter, on Android, iOS, macOS, web and
Windows, from one widget and one callback.
                       DESC
  s.homepage         = 'https://github.com/raphrmx/universal_barcode_scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'COMAPPS.be'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
