Pod::Spec.new do |s|
  s.name = 'EncryptedCoreData'
  s.version = '2.0'
  s.license = 'Apache-2.0'
  
  s.summary = 'iOS Core Data encrypted SQLite store using SQLCipher'
  s.homepage = 'https://github.com/project-imas/encrypted-core-data/'
  s.author = 'iMAS - iOS Mobile Application Security'
  
  s.source = { :git => 'git@github.com:project-imas/encrypted-core-data.git', :tag => '2.0' }
  
  s.frameworks = ['CoreData', 'Security']
  s.requires_arc = true

  s.ios.deployment_target = '7.0'
  s.osx.deployment_target = '10.9'
  s.source_files = 'Incremental Store/**/*.{h,m}'
  s.public_header_files = 'Incremental Store/EncryptedStore.h'
  
  s.dependency 'SQLCipher', '~> 3.1.0'
  
  s.xcconfig = { 'OTHER_CFLAGS' => '$(inherited) -DSQLITE_HAS_CODEC' }
  
end
