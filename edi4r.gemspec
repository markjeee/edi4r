# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{edi4r}
  s.version = "0.9.4.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Heinz W. Werntges / palmade"]
  s.date = %q{2011-03-28}
  s.description = %q{EDI parser written in Ruby. Stolen from the original edi4r rubygem. See http://edi4r.rubyforge.org}
  s.email = %q{}
  s.executables = ["xml2edi.rb", "editool.rb", "edi2xml.rb"]
  s.extra_rdoc_files = ["lib/edi4r.rb", "lib/edi4r/diagrams.rb", "lib/edi4r/edifact.rb", "lib/edi4r/standards.rb", "lib/edi4r/edifact-rexml.rb", "lib/edi4r/rexml.rb", "COPYING", "README"]
  s.files = ["ChangeLog", "test/test_edi_split.rb", "test/test_loopback.rb", "test/in1.inh", "test/test_tut_examples.rb", "test/test_minidemo.rb", "test/test_rexml.rb", "test/in1.edi", "test/test_basics.rb", "test/in2.xml", "test/eancom2webedi.rb", "test/in2.edi", "test/webedi2eancom.rb", "test/groups.edi", "VERSION", "AuthorCopyright", "data/edifact/untdid/EDED.d96a.csv", "data/edifact/untdid/IDSD.d01b.csv", "data/edifact/untdid/IDMD.d01b.csv", "data/edifact/untdid/EDED.d01b.csv", "data/edifact/untdid/EDMD.d96a.csv", "data/edifact/untdid/EDSD.d96a.csv", "data/edifact/untdid/EDMD.d01b.csv", "data/edifact/untdid/IDCD.d01b.csv", "data/edifact/untdid/EDSD.d01b.csv", "data/edifact/untdid/EDCD.d96a.csv", "data/edifact/untdid/EDCD.d01b.csv", "data/edifact/iso9735/SDED.40000.csv", "data/edifact/iso9735/SDMD.40000.csv", "data/edifact/iso9735/SDCD.20000.csv", "data/edifact/iso9735/SDSD.20000.csv", "data/edifact/iso9735/SDSD.40000.csv", "data/edifact/iso9735/SDCD.10000.csv", "data/edifact/iso9735/SDCD.40000.csv", "data/edifact/iso9735/SDMD.20000.csv", "data/edifact/iso9735/SDSD.10000.csv", "data/edifact/iso9735/SDED.20000.csv", "data/edifact/iso9735/SDED.10000.csv", "data/edifact/iso9735/SDED.40100.csv", "data/edifact/iso9735/SDMD.30000.csv", "data/edifact/iso9735/SDMD.10000.csv", "data/edifact/iso9735/SDCD.30000.csv", "data/edifact/iso9735/SDCD.40100.csv", "data/edifact/iso9735/SDSD.40100.csv", "data/edifact/iso9735/SDED.30000.csv", "data/edifact/iso9735/SDSD.30000.csv", "data/edifact/iso9735/SDMD.40100.csv", "lib/edi4r.rb", "lib/edi4r/diagrams.rb", "lib/edi4r/edifact.rb", "lib/edi4r/standards.rb", "lib/edi4r/edifact-rexml.rb", "lib/edi4r/edi4r-1.2.dtd", "lib/edi4r/rexml.rb", "TO-DO", "COPYING", "bin/xml2edi.rb", "bin/editool.rb", "bin/edi2xml.rb", "Manifest", "README", "Rakefile", "CHANGELOG", "Tutorial", "edi4r.gemspec"]
  s.homepage = %q{}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Edi4r", "--main", "README"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{palmade}
  s.rubygems_version = %q{1.5.0}
  s.summary = %q{EDI parser written in Ruby. Stolen from the original edi4r rubygem. See http://edi4r.rubyforge.org}
  s.test_files = ["test/test_edi_split.rb", "test/test_loopback.rb", "test/test_tut_examples.rb", "test/test_minidemo.rb", "test/test_rexml.rb", "test/test_basics.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
