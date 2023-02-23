# #!/usr/bin/env ruby
# -*- encoding: iso-8859-1 -*-
# :include: ../AuthorCopyright

require 'test/unit'
require 'rbconfig'
$ruby_cmd = File.join(RbConfig::CONFIG["bindir"],
			RbConfig::CONFIG["RUBY_INSTALL_NAME"] + RbConfig::CONFIG["EXEEXT"])
$ruby_cmd << " -E iso-8859-1" if RUBY_VERSION >= '1.9'

#######################################################################
# Test the accompanying standalone mapping tools
#
# Mapping to EANCOM and back should yield the original inhouse data.

class EDIFACT_Tests < Test::Unit::TestCase

  def test_loopback
    s1 = nil
    File.open('in1.inh') {|hnd| hnd.binmode; s1 = hnd.read}
    s2 = `#$ruby_cmd ./webedi2eancom.rb -a in1.inh | #$ruby_cmd ./eancom2webedi.rb`
    assert_equal( 0, $? )
    assert_match( s1, s2 )
  end

end
