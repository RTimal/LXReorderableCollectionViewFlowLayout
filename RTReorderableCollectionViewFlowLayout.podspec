Pod::Spec.new do |s|
  s.name = 'RTReorderableCollectionViewFlowLayout'
  s.version = '0.1.1'
  s.summary = 'Extends UICollectionViewFlowLayout to support reordering of cells. Similar to long press and pan on books in iBooks.'
  s.homepage = 'https://github.com/RTimal/RTReorderableCollectionViewFlowLayout'
  s.license = {
    :type => 'MIT',
    :file => 'LICENSE'
  }
  s.author = 'Rajiev Timal'
  s.source = {
    :git => 'https://github.com/RTimal/RTReorderableCollectionViewFlowLayout.git',
    :tag => '0.1.1'
  }
  s.platform = :ios, '7.0'
  s.source_files = 'RTReorderableCollectionViewFlowLayout/'
  s.public_header_files = 'RTReorderableCollectionViewFlowLayout/'
  s.frameworks = 'UIKit', 'CoreGraphics'
  s.requires_arc = true
end
