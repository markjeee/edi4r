#!/usr/bin/env ruby
# :include: ../AuthorCopyright

require 'test/unit'

#######################################################################
# Test the accompanying standalone mapping tools
#
# Mapping to EANCOM and back should yield the original inhouse data.

class EDIFACT_Tests < Test::Unit::TestCase

  def test_loopback
    s1 = nil
    File.open('in1.inh') {|hnd| hnd.binmode; s1 = hnd.read}
    s2 = `ruby ./webedi2eancom.rb -a in1.inh | ruby ./eancom2webedi.rb`
    assert_equal( 0, $? )
    assert_match( s1, s2 )
  end

end
