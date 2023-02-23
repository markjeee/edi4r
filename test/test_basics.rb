#!/usr/bin/env ruby
# -*- encoding: iso-8859-1 -*-
# :include: ../AuthorCopyright

# Load path magic...
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'

require 'edi4r'
require 'edi4r/edifact'

class EDIFACT_Tests < Test::Unit::TestCase

  # Utilities: Fill in just the required segments

  def fill_ORDERS( msg )
    seg = msg.new_segment('BGM')
    msg.add seg
    seg.d1004 = '220'
    assert_equal(["C002", "1004", "1225", "4343"], seg.names )
    seg = msg.new_segment('DTM')
    msg.add seg
    seg.cC507.d2005 = '137'
    t = EDI::Time.edifact('20060703', 102)
    assert_equal('20060703', t.to_s)
    seg.cC507.d2380 = t
    seg.cC507.d2379 = t.format

    assert_equal( ["2005", "2380", "2379"], seg.cC507.names )
    seg = msg.new_segment('UNS')
    seg.d0081 = 'S'
    msg.add seg
#    p seg.names
  end


  def fill_INVOIC( msg )
    seg = msg.new_segment('BGM')
    msg.add seg
    seg.cC002.d1001 = '380'
    assert_equal(["C002", "C106", "1225", "4343"], seg.names )
    seg = msg.new_segment('DTM')
    msg.add seg
    seg.cC507.d2005 = '137'
    t = EDI::Time.new
    t.format = 204
    seg.cC507.d2380 = t
    seg.cC507.d2379 = t.format

    assert_equal( ["2005", "2380", "2379"], seg.cC507.names )
    seg = msg.new_segment('UNS')
    seg.d0081 = 'S'
    msg.add seg

    seg = msg.new_segment('MOA')
    msg.add seg
    seg.cC516.d5025 = '86'
    seg.cC516.d5004 = 0.0
#    p seg.names
  end


  def test_interchange_creation
    ic = nil

    # All defaults working?
    assert_nothing_raised { ic = EDI::E::Interchange.new() }
    assert_match( /^UNA:\+\.\? 'UNB\+UNOB:3\+\+\+\d{6}:\d{4}\+1'UNZ\+0\+1'$/, ic.to_s )

    # Change some parameters: Switch off UNA, try a different charset
    assert_nothing_raised {
      ic = EDI::E::Interchange.new({
                                     :show_una=>false, :charset=>'UNOC',
                                     :interchange_control_reference=>123,
                                     :test_indicator=>1 })
    }
    assert_match( /^UNB\+UNOC:3\+\+\+\d{6}:\d{4}\+(123)\+{6}1'UNZ\+0\+\1'$/, ic.to_s )


    # Now test special separator case SV2, UNOB. Is UNA on by default?
    assert_nothing_raised {
      ic = EDI::E::Interchange.new({:version=>2})
    }
    assert_match( /^UNA\021\022\.\? \024UNB\022UNOB\0212\022\022\022\d{6}\021\d{4}\0221\024UNZ\0220\0221\024$/, ic.to_s )

    # Same again, now with a few defaults set explicitly
    assert_nothing_raised {
      ic = EDI::E::Interchange.new({:show_una=>true,:version=>2, :charset=>'UNOB'})
    }
    assert_match( /^UNA\021\022\.\? \024UNB\022UNOB\0212\022\022\022\d{6}\021\d{4}\0221\024UNZ\0220\0221\024$/, ic.to_s )

    # SV4 working?
    assert_nothing_raised { ic = EDI::E::Interchange.new({:version=>4, :charset=>'UNOC'}) }
    assert_match( /^UNA:\+\.\?\*'UNB\+UNOC:4\+\+\+\d{8}:\d{4}\+1'UNZ\+0\+1'$/, ic.to_s )

    # SV4 & I-EDI working?
    assert_raise( RuntimeError) {
      ic = EDI::E::Interchange.new({:version=>4, :charset=>'UNOC', :i_edi => true})
    }
#    assert_match( /^UNA:\+\.\?\*'UIB\+UNOC:4\+\+\+\d{8}:\d{4}\+1'UIZ\+0\+1'$/, ic.to_s )
  end


  def test_group_creation
    ic = n = nil
    assert_nothing_raised { ic = EDI::E::Interchange.new() }

    # First group: No sender/recipient there to inherit: 
    # Expect 4 validation errors (2 x UNB, 2 x UNG)
    grp = ic.new_msggroup
    ic.add( grp, false )
    assert_equal( 4, ic.validate )

    # Second group: Now let's see if sender/recipient inheritance works: 
    # Expect no more validation errors
    grp.header.cS006.d0040 = 'sender-g'
    grp.header.cS007.d0044 = 'recipient-g'

    ic.header.cS002.d0004 = 'sender'
    ic.header.cS003.d0010 = 'recipient'
    grp = ic.new_msggroup
    assert_nothing_raised{ n = ic.validate}
    assert_equal( 0, n )

    msg = grp.new_message
    fill_ORDERS(msg)
    grp.add( msg )

    # See if reference in trailer is updated when header ref. changes:
    grp.header.d0048 = 5
    ic.add( grp, false )

    assert_nothing_raised{ n = ic.validate}
    assert_equal( 0, n )

    grp = ic.new_msggroup(:msg_type=>'INVOIC', :version=>'D', :release=>'01B',
                          :resp_agency=>'UN', :assigned_code=>'EAN010')
    ic.add( grp, false )
    msg = grp.new_message
    fill_INVOIC(msg)
    grp.add msg
    assert_nothing_raised{ n = ic.validate}
    assert_equal( 0, n )
    assert_nothing_raised{ File.open("groups.edi",'w') {|f| f.print ic} }

    msg.header.cS009.d0057 = 'EAN011' # provoke a grp/msg difference 
    assert_nothing_raised{ n = ic.validate}
    assert_equal( 1, n )
#    puts ic
  end


  def test_message_creation

    ic = nil
    assert_nothing_raised { ic = EDI::E::Interchange.new() }
    msg = ic.new_message
    fill_ORDERS(msg)

    ic.add msg
    ic.add msg
    assert_equal( 1, msg.header.first.value ) # value of DE 0062
    assert_equal( "ORDERS:D:96A:UN", msg.header[1].to_s ) # S009
    assert_equal( "UNH+1+ORDERS:D:96A:UN", msg.header.to_s ) # UNH
    assert_equal( "BGM++220", msg.first.to_s ) # BGM

#    puts msg
#    puts msg.inspect
    ic.header.d0035 = 1  # Test indicator
#    puts ic
  end

  def test_una_changes
    ic = nil
    assert_nothing_raised { ic = EDI::E::Interchange.new() }
    msg = ic.new_message
    pri = msg.parse_segment('PRI+AAA:30,0::LIU', 'PRI')
    assert_equal( pri.to_s, 'PRI+AAA:30::LIU')
    pri = msg.parse_segment('PRI+AAA:30.1::LIU', 'PRI')
    assert_equal( pri.to_s, 'PRI+AAA:30.1::LIU')
    ic.una.decimal_sign = ?,
    pri = msg.parse_segment('PRI+AAA:30.1::LIU', 'PRI')
    assert_equal( 'PRI+AAA:30,1::LIU', pri.to_s)
    ic.una.decimal_sign = ?.
    ic.una.ce_sep = ?-
    assert_equal( 'PRI+AAA-30.1--LIU', pri.to_s)
    pri.cC509.d5118 = -pri.cC509.d5118
    assert_equal( 'PRI+AAA-?-30.1--LIU', pri.to_s)
    ic.una.esc_char = ?#
    assert_equal( 'PRI+AAA-#-30.1--LIU', pri.to_s)
    ic.una.esc_char = ?\\
    assert_equal( 'PRI+AAA-\\-30.1--LIU', pri.to_s)
  end

  def test_interchange_parsing
    mode = RUBY_VERSION >= '1.9' ? 'rb:iso-8859-15' : 'rb'
    assert_nothing_raised {
      # ic = EDI::E::Interchange.parse( File.open( './marius1.edi','r' ), true )
      file = File.open './O0002248720', mode
      ic = EDI::E::Interchange.parse file, false
      file.close
      ic.output_mode = :indented
      File.open("invoic.out", "w") {|hnd| hnd.print ic}
    }
    # assert_nothing_raised {
      file = File.open './remadv101.edi', mode 
      ic = EDI::E::Interchange.parse file
      # ic.output_mode = :indented
      file.close
      File.open("remadv.out", "w") {|hnd| hnd.print ic}
#      $stdout.write ic
      ic.validate
    # }
  end
end 
