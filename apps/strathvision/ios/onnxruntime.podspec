# Same ONNX Runtime 1.15.1 C API used by the Dart plugin. Microsoft's NuGet
# package retains the official device/simulator XCFramework after the old
# CocoaPods archive endpoint stopped serving it. See docs/DISTRIBUTION.md.
Pod::Spec.new do |s|
  s.name = 'onnxruntime'
  s.version = '1.15.1'
  s.summary = 'ONNX Runtime native C API for STRATHVISION Flutter FFI.'
  s.homepage = 'https://onnxruntime.ai/'
  s.author = { 'Microsoft' => 'onnxruntime@microsoft.com' }
  s.license = { :type => 'MIT', :file => 'LICENSE.txt' }
  s.source = {
    :http => 'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.15.1/microsoft.ml.onnxruntime.1.15.1.nupkg',
    :type => 'zip',
    :sha256 => 'da45c9bf6472637fc97eec243eac979cdc3456d0e4380ecfeffdeec75a627431'
  }
  s.ios.deployment_target = '15.0'
  s.vendored_frameworks = 'runtimes/ios/native/onnxruntime.xcframework'
  s.preserve_paths = 'LICENSE.txt'
  s.static_framework = true
  s.libraries = 'c++'
  s.weak_frameworks = 'CoreML'
  s.dependency 'Flutter'
  # Keep the code linked; Runner's Release.xcconfig also preserves its exported
  # name through archive stripping so Dart's DynamicLibrary.process can find it.
  s.user_target_xcconfig = { 'OTHER_LDFLAGS' => '$(inherited) -Wl,-u,_OrtGetApiBase' }
end
