#!/usr/bin/env ruby
# *-* encoding: iso-8859-1 -*-
# :include: ../AuthorCopyright

#######################################################################
# Test conversion to and from XML representation
#
# Mapping to XML and back should yield the original UN/EDIFACT data.
# Mapping to UN/EDIFACT and back should yield the original XML data.

# Include statement during test setup:

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '..', '..', 'tdid', 'lib')

require 'edi4r'
require 'edi4r/edifact'
require 'edi4r/rexml'
require 'edi4r-tdid'
require 'edi4r/edifact-rexml'

# Regular include statements:

#require "rubygems"
#require_gem "edi4r"
#require "edi4r/edifact"
#require 'edi4r/rexml'

require 'stringio'
require 'test/unit'


class EDIFACT_REXML_Tests < Test::Unit::TestCase

  def setup
    @ice = EDI::Interchange.parse(File.open("in2.edi"))
    @se  = @ice.to_s
    @icg = EDI::Interchange.parse(File.open("groups.edi"))
  end

  def test_rexml
    @icx = nil
    assert_nothing_raised do
      @icx = EDI::Interchange.parse(File.open("in2.xml"))
      assert_equal( 0, @icx.validate )
    end

    assert_equal( @se, @icx.to_s )  # EDIFACT representations equal?
    
    sx = File.open('in2.edi') { |hnd| hnd.read }.chop
    se = @se.sub(/PRI\+AAA:30::LIU\'PRI\+AAE:99::/,
                 'PRI+AAA:30.0::LIU\'PRI+AAE:99,0::')
    assert_equal( se, sx )  # EDIFACT representations equal file content?

    se = StringIO.new
    xdoc_e = REXML::Document.new
    @ice.to_xml(xdoc_e)
    xdoc_e.write( se, 0 )
#    xdoc_e.write( File.open('in2a.xml','w'), 0 )

    sx = StringIO.new
    xdoc_x = REXML::Document.new
    @ice.to_xml(xdoc_x)
    xdoc_x.write( sx, 0 )

    assert_equal( se.string, sx.string ) # XML representations equal?
  end


  def test_joko
    icx = nil
    assert_nothing_raised do
      icx = EDI::Interchange.parse(File.open("joko2.xml"))
      assert_equal( 0, icx.validate )
    end

    ice = EDI::Interchange.parse(File.open("joko_in.edi"))
    assert_equal( ice.to_s, icx.to_s )  # EDIFACT representations equal?
    
    se = StringIO.new
    xdoc_e = REXML::Document.new
    ice.to_xml(xdoc_e)
    xdoc_e.write( se, 0 )
    xdoc_e.write( File.open('joko2a.xml','w'), 0 )

    sx = StringIO.new
    xdoc_x = REXML::Document.new
    icx.to_xml(xdoc_x)
    xdoc_x.write( sx, 0 )

    ie = EDI::E::Interchange.parse_xml( xdoc_e )
    ix = EDI::E::Interchange.parse_xml( xdoc_x )
    assert_equal( ie.to_s, ix.to_s )
  end


  def test_groups

    xdoc = REXML::Document.new
    assert_nothing_raised{ @icg.to_xml( xdoc ) }

    sg = StringIO.new
    xdoc.write( sg )
#    xdoc.write( File.open("groups2.xml",'w') )

    ic = nil
    assert_nothing_raised do
      ic = EDI::E::Interchange.parse_xml( REXML::Document.new( sg.string )) 
    end
    assert_equal( @icg.to_s, ic.to_s ) 
  end


  def test_din16557_4
    xdoc = nil
    assert_nothing_raised{ xdoc = @ice.to_din16557_4 }

    sg = StringIO.new
#    sg = $stdout
    xdoc.write( sg, 0 )

    xdoc = nil
    assert_nothing_raised{ xdoc = @icg.to_din16557_4 }

#    sg = $stdout
    sg = StringIO.new
    xdoc.write( sg, 0 )
#    xdoc.write( File.open("groups2.xml",'w'), 0 )
  end
end
