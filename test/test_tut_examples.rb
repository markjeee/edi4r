#!/usr/bin/env ruby
# :include: ../AuthorCopyright

# Load path magic...
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '..', '..', 'tdid', 'lib')

require 'test/unit'

require 'edi4r'
require 'edi4r/edifact'
require 'edi4r-tdid'

# require "rubygems"
# require_gem "edi4r"
# require_gem "edi4r-tdid"

class Tutorial_Tests < Test::Unit::TestCase

  def test_tutorial_samples
    ic = ic2 = nil
    assert_nothing_raised do
      ic  = EDI::E::Interchange.new
      ic2 = EDI::E::Interchange.new( :version => 3, :charset => 'UNOB' )
    end
    assert_equal( ic.to_s, ic2.to_s )

    msg = msg1 = nil
    assert_nothing_raised do
      msg1 = ic.new_message
      msg = ic.new_message(:msg_type=>'ORDERS', :version=>'D', :release=>'96A',
                           :resp_agency=>'UN' )
    end

    assert_raise(EDI::EDILookupError) { ic.add( msg ) }
    assert_nothing_raised { ic.add( msg, false ) }


    assert_nothing_raised do
      seg = msg.new_segment( 'BGM' )
      msg.add( seg )
    end
    assert_equal( 1, msg.size )

    order_number = nil
    assert_nothing_raised do
      bgm = msg.new_segment( 'BGM' )
      bgm.d1004 = '123456ABC'
      bgm.cC002.d1001 = 220

      cde = bgm.cC002
      order_number = bgm.d1004  if cde.d1001 == 220
    end
    assert_equal( '123456ABC', order_number )

  
    assert_nothing_raised do
      seg = msg.new_segment('PIA')
      cde_list = seg.aC212
      cde_list[0].d7140 = '54321'
      cde_list[0].d7143 = 'SA'
      cde_list[0].d3055 = 91
      cde_list[1].d7140 = '12356'  # etc

      seg = msg.new_segment('NAD')
      seg.cC080.a3036[0].value = 'E. X. Ample'
      seg.cC080.a3036[1].value = 'Sales dept.'
    end

  
    assert_nothing_raised do
      ic.header.cS002.d0004 = '1234567'
      ic.header.d0035 = 1
      ic.show_una = false
      ic.show_una = true
    end
    assert_equal( 'UNA:+.? \'', ic.una.to_s )

    assert_nothing_raised do
      pri = msg.parse_segment("PRI+AAA:123::LIU", 'PRI')
      pri.cC509.d5118 = 30.1
      assert_equal( "PRI+AAA:30.1::LIU", pri.to_s )
      ic.una.decimal_sign = ?,
      assert_equal( "PRI+AAA:30,1::LIU", pri.to_s )
      ic.una.ce_sep = ?/
      assert_equal( "PRI+AAA/30,1//LIU", pri.to_s )
    end

    assert_raise(EDI::EDILookupError) {ic.validate}

    ic = nil
    assert_nothing_raised do
      File.open("remadv101.edi") {|hnd| ic = EDI::E::Interchange.parse( hnd )}

      ic.each do |msg|

        msg.each do |seg|
          seg_name = seg.name
          seg_name += ' ' + seg.sg_name if seg.sg_name
          case seg_name
          when "BGM"
            # do this ...
          when "DTM"
            # do that ...
          when 'NAD SG2'
            # react only if NAD occurs in segment group 2
            
            # ... etc., finally:
            default
            raise "Segment #{seg_name}: Not accounted for!"
          end
        end
      end
    end

    n=0
    assert_nothing_raised {n = ic.validate}
    assert_equal( 0, n )

    second_msg = ic[1]
    last_msg = ic.last
    d = last_msg['DTM']  # Array of all DTM segments, any segment group
    assert( d. is_a?( Array ) )
    d = last_msg.find_all {|seg| seg.name == 'DTM' && seg.sg_name == 'SG4'}
    assert_equal( 11, d.size )

    doc1 = last_msg['DOC'].first
    assert_equal( 12, doc1.children.size )
    assert_equal( 13, doc1.children_and_self.size )
    assert_equal( 15, doc1.descendants.size )
    assert_equal( 16, doc1.descendants_and_self.size )
  end
end
