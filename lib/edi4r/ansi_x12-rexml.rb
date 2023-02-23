# -*- encoding: iso-8859-1 -*-
# UN/EDIFACT add-ons to EDI module,
#   Methods for XML support for the ANSI X12 module
#
# :include: ../../AuthorCopyright
#
# $Id$
#--
# $Log$
#
# Derived from "edifact-rexml.rb"  by HWW
#
# To-do list:
#	all		- Just starting...
#++
#
# This is the XML add-on for the ANSI X12 module of edi4r (hence '::A')
#
# It leaves all real work to the base classes.

module EDI::A

  class Interchange
    #
    # Returns a REXML document that represents the interchange
    #
    # xdoc:: REXML document that contains the XML representation of
    #        a ANSI X12 interchange
    #
    def Interchange.parse_xml( xdoc )
      _root = xdoc.root
      _header  = _root.elements["Header"]
      _trailer = _root.elements["Trailer"]
      _version = _root.attributes["version"]
      _ce_sep = REXML::XPath.first(xdoc, "/Interchange/Header/Segment/DE[@name='I15']").text.to_i
      params = { :ce_sep => _ce_sep, :version => _version }
      ic = Interchange.new( params )
      if _root.elements["Message"].nil? # correct ??
        _root.elements.each('MsgGroup') do |xel|
          ic.add( MsgGroup.parse_xml( ic, xel ), false )
        end
      else
        _root.elements.each('Message') do |xel|
          ic.add( Message.parse_xml( ic, xel ), false )
        end
      end

      ic.header  = Segment.parse_xml( ic, _header.elements["Segment"] )
      ic.header.dI15 = _ce_sep
      ic.trailer = Segment.parse_xml( ic, _trailer.elements["Segment"] )
      ic.validate
      ic
    end

    #
    # Read +maxlen+ bytes from $stdin (default) or from given stream
    # (ANSI X12 data expected), and peek into first segment (ISA).
    #
    # Returns an empty Interchange object with a properly header filled.
    #
    # Intended use: 
    #   Efficient routing by reading just ISA data: sender/recipient/ref/test
    #
    def Interchange.peek_xml(xdoc) # Handle to REXML document
      _root = xdoc.root
      _header  = _root.elements["Header"]
      _trailer = _root.elements["Trailer"]
      _version = _root.attributes["version"]
      _ce_sep = REXML::XPath.first(xdoc, "/Interchange/Header/Segment/DE[@name='I15']").text.to_i
      params = { :ce_sep => _ce_sep, :version => _version }
      ic = Interchange.new( params )

      ic.header  = Segment.parse_xml( ic, _header.elements["Segment"] )
      ic.header.dI15 = _ce_sep
      ic.trailer = Segment.parse_xml( ic, _trailer.elements["Segment"] )

      ic
    end

    #
    # Returns a REXML document that represents the interchange
    #
    def to_xml( xdoc = REXML::Document.new )
      rc = super
      # Add parameter(s) to header in rc[1]
#      rc
      xdoc
    end

  end # class Interchange
end # module EDI::A
