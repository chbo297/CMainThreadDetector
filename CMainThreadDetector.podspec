Pod::Spec.new do |s|
  s.name         = "CMainThreadDetector"
  s.version      = "0.0.1"
  s.summary      = "detect main thread slow, dump stack symbols."
  s.description  = <<-DESC
	detect main thread slow, dump stack symbols, use timer ping/pong main thread.
                   DESC

  s.homepage     = "https://github.com/chbo297/CMainThreadDetector"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author             = { "ChengBo" => "chbo297@gmail.com" }
  s.authors            = { "ChengBo" => "chbo297@gmail.com" }
  s.social_media_url   = "http://twitter.com/booooo07"
  s.platform     = :ios, "7.0"
  s.source       = { :git => "https://github.com/chbo297/CMainThreadDetector.git", :tag => s.version }
  s.source_files  = "CMainThreadDetector/*.{h,m}"

end
