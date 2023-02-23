#!/usr/bin/env ruby
# :include: ../AuthorCopyright

=begin
  E = ??	# ESC char
  C = ?:	# CDE separator char
  D = ?+	# DE separator char
  S = ?'	# Segment terminator
=end

# Load path magic...
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'

require 'edi4r'
require 'edi4r/edifact'
include EDI::E

class TestClass < Test::Unit::TestCase

=begin
  def test_cde_sep
    assert_equal(['a','b'], edi_split('a:b', ?:, ??) ) 
    assert_equal(['a:b'],   edi_split('a?:b', ?:, ??) ) 
    assert_equal(['a?','b'],edi_split('a??:b', ?:, ??) ) 
    assert_equal(['a?:b'],  edi_split('a???:b', ?:, ??) ) 
    assert_raise( EDISyntaxError) { edi_split('a:b?', ?:, ??)}

    assert_equal(['a','', 'b'],     edi_split('a::b', ?:, ??) ) 
    assert_equal(['a','', '', 'b'], edi_split('a:::b', ?:, ??) ) 
    assert_equal(['a','b'],         edi_split('a:b:', ?:, ??) ) 
    assert_equal(['a','', 'b'],     edi_split('a::b::', ?:, ??) ) 

    assert_equal(['','a','b'],            edi_split(':a:b', ?:, ??) ) 
    assert_equal(['','','', 'a','', 'b'], edi_split(':::a::b::', ?:, ??) ) 

    assert_equal( ['123456780', 'A + B LTD' ], edi_split('123456780:A + B LTD', ?:, ??) )
    assert_equal( ['', '', '', '10010099', '25', '131' ], edi_split(':::10010099:25:131', ?:, ??) )
  end

  def test_de_sep
    assert_equal( ['IMD', 'A','', ':::JEANS'], edi_split('IMD+A++:::JEANS', ?+, ??))
    assert_equal( ['FII', 'OR','123456780:A + B LTD', ':::10010099:25:131' ], edi_split('FII+OR+123456780:A ?+ B LTD+:::10010099:25:131', ?+, ??) )
    assert_raise(EDISyntaxError){edi_split('TAG+SOME TEXT??+MORE TEXT+PENDING ESC! ?', ?+, ??)}
    assert_equal( ['TAG','SOME TEXT?', 'MORE TEXT', 'PENDING ESC ?'], edi_split('TAG+SOME TEXT??+MORE TEXT+PENDING ESC ??', ?+, ??) )
    assert_raise(EDISyntaxError){edi_split('TAG+SOME TEXT??+MORE TEXT+PENDING ESC! ???', ?+, ??)}
  end
=end
  # New concept: Leave the unescaping to the last step (at DE level)
  #              to avoid accidental multiple unescaping
  def test_cde_sep
    assert_equal(['a','b'], edi_split('a:b', ?:, ??) ) 
    assert_equal(['a?:b'],   edi_split('a?:b', ?:, ??) ) 
    assert_equal(['a??','b'],edi_split('a??:b', ?:, ??) ) 
    assert_equal(['a???:b'],  edi_split('a???:b', ?:, ??) ) 
    assert_raise( EDISyntaxError) { edi_split('a:b?', ?:, ??)}

    assert_equal(['a','', 'b'],     edi_split('a::b', ?:, ??) ) 
    assert_equal(['a','', '', 'b'], edi_split('a:::b', ?:, ??) ) 
    assert_equal(['a','b'],         edi_split('a:b:', ?:, ??) ) 
    assert_equal(['a','', 'b'],     edi_split('a::b::', ?:, ??) ) 

    assert_equal(['','a','b'],            edi_split(':a:b', ?:, ??) ) 
    assert_equal(['','','', 'a','', 'b'], edi_split(':::a::b::', ?:, ??) ) 

    assert_equal( ['123456780', 'A + B LTD' ], edi_split('123456780:A + B LTD', ?:, ??) )
    assert_equal( ['', '', '', '10010099', '25', '131' ], edi_split(':::10010099:25:131', ?:, ??) )
  end

  def test_de_sep
    assert_equal( ['IMD', 'A','', ':::JEANS'], edi_split('IMD+A++:::JEANS', ?+, ??))
    assert_equal( ['FII', 'OR','123456780:A ?+ B LTD', ':::10010099:25:131' ], edi_split('FII+OR+123456780:A ?+ B LTD+:::10010099:25:131', ?+, ??) )
    assert_raise(EDISyntaxError){edi_split('TAG+SOME TEXT??+MORE TEXT+PENDING ESC! ?', ?+, ??)}
    assert_equal( ['TAG','SOME TEXT??', 'MORE TEXT', 'PENDING ESC ??'], edi_split('TAG+SOME TEXT??+MORE TEXT+PENDING ESC ??', ?+, ??) )
    assert_raise(EDISyntaxError){edi_split('TAG+SOME TEXT??+MORE TEXT+PENDING ESC! ???', ?+, ??)}
  end

  def test_seg_term
    assert_equal( ['RFF+ACK:12345/678', 'FII+BF+000000000:::EUR+:::10010099:25:131', 'SEQ++1', 'FII+OR+123456780:A ?+ B LTD+:::10010099:25:131', 'RFF+RA:YOUR ACCOUNT 1234-5678 9'], edi_split('RFF+ACK:12345/678\'FII+BF+000000000:::EUR+:::10010099:25:131\'SEQ++1\'FII+OR+123456780:A ?+ B LTD+:::10010099:25:131\'RFF+RA:YOUR ACCOUNT 1234-5678 9\'', ?', ??))
  end

end
