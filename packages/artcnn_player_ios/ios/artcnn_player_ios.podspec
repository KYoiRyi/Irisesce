Pod::Spec.new do |s|
  s.name             = 'artcnn_player_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS ArtCNN AVPlayer FlutterTexture bridge.'
  s.description      = 'Native iOS AVPlayer frame extraction, Core ML ArtCNN inference, and FlutterTexture output.'
  s.homepage         = 'https://example.invalid/irisesce'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Irisesce' => 'dev@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.resources        = 'Resources/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
