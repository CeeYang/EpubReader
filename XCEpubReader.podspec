Pod::Spec.new do |s|
    s.name               = "XCEpubReader"
    s.version            = "0.0.1"
    s.summary            = "An EpubReader of iOS."
    s.homepage           = "https://github.com/CeeYang/EpubReader"
    s.license            = "MIT"
    s.author             = { "CeeYang" => "767781606@qq.com" }
    s.ios.deployment_target = "7.0"
    s.source             = { :git => "https://github.com/CeeYang/EpubReader.git", :tag => "#{s.version}" }
    s.source_files       = "XCReader", "XCEpubReader/XCReader/**/*.{h,m}"
    s.exclude_files      = "Classes/Exclude"
    s.resources          = "XCEpubReader/XCReader/Resources/*.png"
    s.requires_arc       = true
    s.dependency           "GDataXML-HTML"
    s.dependency           "Masonry"
    s.dependency           "ZipArchive"
    s.dependency           "MBProgressHUD"
end
