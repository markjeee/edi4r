require 'rubygems'
gem 'echoe'
require 'echoe'

Echoe.new("edi4r") do |p|
  p.author = "Heinz W. Werntges / palmade"
  p.project = "palmade"
  p.summary = "EDI parser written in Ruby. Stolen from the original edi4r rubygem. See http://edi4r.rubyforge.org"

  p.dependencies = [ ]

  p.need_tar_gz = false
  p.need_tgz = true

  p.clean_pattern += [ "pkg", "lib/*.bundle", "*.gem", ".config" ]
  p.rdoc_pattern = [ 'README', 'LICENSE', 'COPYING', 'lib/**/*.rb', 'doc/**/*.rdoc' ]
end

gem 'rspec'
