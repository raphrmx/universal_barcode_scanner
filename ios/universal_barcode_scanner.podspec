#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'universal_barcode_scanner'
  s.version          = '1.1.0'
  s.summary          = 'Barcode and QR code scanner for Flutter.'
  s.description      = <<-DESC
Barcode and QR code scanner for Flutter, on Android, iOS, web and Windows,
from one widget and one callback.
                       DESC
  s.homepage         = 'https://github.com/raphrmx/universal_barcode_scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'COMAPPS.be'
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.resources = 'Assets/*.png'
  s.dependency 'Flutter'

  s.ios.deployment_target = '12.0'
  s.swift_version = '5.0'
end
