#!/usr/bin/env ruby
# :include: ../AuthorCopyright

# Load path magic...
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'
#require "rubygems"
#require_gem "edi4r"
require "edi4r"
require "edi4r/edifact"
require 'tempfile'


class EDIFACT_Minitests < Test::Unit::TestCase

  def setup
    @ic = EDI::E::Interchange.new({
                                    :show_una	=> true,
                                    :charset	=> 'UNOC',
                                    :version	=> 3,
                                    :interchange_control_reference => '12345',
                                    :output_mode	=> :verbatim})

    cde = @ic.header.cS002
    cde.d0004 = '2965197000005'
    cde.d0007 = '14'
    cde = @ic.header.cS003
    cde.d0010 = '2165197000009'
    cde.d0007 = '14'

    # ic.write $stdout

    params = {
      :msg_type	=> 'ORDERS',
      :version	=> 'D',
      :release	=> '01B',
      :resp_agency	=> 'UN',
      :assigned_code	=> 'EAN010'
    }

    msg = @ic.new_message params

    # print msg

    seg = msg.new_segment('BGM')
    seg.cC002.d1001 = '220'
    seg.cC106.d1004 = '1234567'
    seg.d1225 = '9'
    msg.add seg

    seg = msg.new_segment('DTM')
    cde = seg.cC507
    cde.d2005 = '137'
    cde.d2380 = '20050603'
    cde.d2379 = '102'
    msg.add seg

    seg = msg.new_segment('UNS')
    seg.d0081='S'

    msg.add seg

    @ic.add msg
  end

  def test_validation
    rc = 0
    assert_nothing_raised { rc=@ic.validate }
    assert_equal( 0, rc)
  end

  def test_write_parse_validate
    tf = Tempfile.new("minitest_edi")
    tf.print @ic
    tf.close
    rc = 0
    ic2 = EDI::E::Interchange.parse(tf.open)
    assert_nothing_raised { rc=ic2.validate }
    assert_equal( 0, rc)
    assert_equal( @ic.to_s, ic2.to_s)
    tf.close(true) unless tf.closed?
  end
end
