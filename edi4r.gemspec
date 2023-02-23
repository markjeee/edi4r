# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'edi4r'
  s.version     = '0.9.6.3'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Heinz W. Werntges']
  s.email       = []
  s.homepage    = 'http://github.com/marketplacer/edi4r'
  s.summary     = 'Universal Ruby library to handle WebSocket protocol'
  s.description = 'edi4r turns Ruby into a powerful EDI mapping language: - create or process UN/EDIFACT interchanges intuitively - validate messages with information from the original UN/TDIDs - integrate classical EDI data and XML documents through a generic EDI/XML translator (add-on gem, DTD provided).
'
  s.license     = 'Ruby'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths = ['lib']
end
