# -*- encoding: iso-8859-1 -*-
# UN/EDIFACT add-ons to EDI module,
#   Methods for XML support for the UN/EDIFACT module
#
# :include: ../../AuthorCopyright
#
# $Id: edifact-rexml.rb,v 1.1 2006/08/01 11:14:18 werntges Exp $
#--
# $Log: edifact-rexml.rb,v $
# Revision 1.1  2006/08/01 11:14:18  werntges
# Initial revision
#
#
# Derived from "edifact.rb" (precursor) by HWW
#
# To-do list:
#	SV4		- Support & testing
#++
#
# This is the XML add-on for UN/EDIFACT module of edi4r (hence '::E')
#
# It leaves all real work to the base classes. Only the UNA information
# is treated in a special way (as a "Parameter" element of the header)
# and dealt with here.

module EDI::E

  class Interchange
    #
    # Returns a REXML document that represents the interchange
    #
    # xdoc:: REXML document that contains the XML representation of
    #        a UN/EDIFACT interchange
    #
    def Interchange.parse_xml( xdoc )
      _root = xdoc.root
      _header  = _root.elements["Header"]
      _trailer = _root.elements["Trailer"]
      _una  = _header.elements["Parameter[@name='UNA']"]
      _una = _una.text.strip if _una
      raise "Empty UNA" if _una and _una.empty? # remove later!
      # S001: Works for both batch and interactive EDI:
      _s001 =  _header.elements["Segment/CDE[@name='S001']"]
      _version = _s001.elements["DE[@name='0002']"].text.to_i
      _charset = _s001.elements["DE[@name='0001']"].text.strip
      params = { :charset => _charset, :version => _version }
      if _una
        params[:una_string] = _una
        params[:show_una] = true
      end
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
      ic.trailer = Segment.parse_xml( ic, _trailer.elements["Segment"] )
      ic.validate
      ic
    end  

    #
    # Read +maxlen+ bytes from $stdin (default) or from given stream
    # (UN/EDIFACT data expected), and peek into first segment (UNB/UIB).
    #
    # Returns an empty Interchange object with a properly header filled.
    #
    # Intended use: 
    #   Efficient routing by reading just UNB data: sender/recipient/ref/test
    #
    def Interchange.peek_xml(xdoc) # Handle to REXML document
      _root = xdoc.root
      _header  = _root.elements["Header"]
      _trailer = _root.elements["Trailer"]
      _una  = _header.elements["Parameter[@name='UNA']"]
      _una = _una.text if _una
      raise "Empty UNA" if _una and _una.empty? # remove later!
      # S001: Works for both batch and interactive EDI:
      _s001 =  _header.elements["Segment/CDE[@name='S001']"]
      _version = _s001.elements["DE[@name='0002']"].text.to_i
      _charset = _s001.elements["DE[@name='0001']"].text.strip
      params = { :charset => _charset, :version => _version }
      if _una
        params[:una_string] = _una
        params[:show_una] = true
      end
      ic = Interchange.new( params )

      ic.header  = Segment.parse_xml( ic, _header.elements["Segment"] )
      ic.trailer = Segment.parse_xml( ic, _trailer.elements["Segment"] )

      ic
    end


    #
    # Returns a REXML document that represents the interchange
    #
    def to_xml( xdoc = REXML::Document.new )
      rc = super
      # Add parameter(s) to header in rc[1]
      unless @una.nil? #@una.empty?
        xel = REXML::Element.new('Parameter')
        rc[1] << xel
        xel.attributes["name"] = 'UNA'
        xel.text = @una.to_s
      end
#      rc
      xdoc
    end


    #
    # Returns a REXML document that represents the interchange
    # according to DIN 16557-4
    #
    def to_din16557_4( xdoc = REXML::Document.new )
      externalID = "SYSTEM \"edifact.dtd\""
      doc_element_name = 'EDIFACTINTERCHANGE'
      xdoc << REXML::XMLDecl.new
      xdoc << REXML::DocType.new( doc_element_name, externalID )

      doc_el = REXML::Element.new( doc_element_name )
      xel  = REXML::Element.new( 'UNA' ) 
      xel.attributes["UNA1"]  = una.ce_sep.chr
      xel.attributes["UNA2"]  = una.de_sep.chr
      xel.attributes["UNA3"]  = una.decimal_sign.chr
      xel.attributes["UNA4"]  = una.esc_char.chr
      xel.attributes["UNA5"]  = una.rep_sep.chr
      xel.attributes["UNA6"]  = una.seg_term.chr
      xdoc.elements << doc_el
      doc_el.elements << xel

      super( xdoc.root )
      xdoc
    end

  end

  class Segment
    def to_din16557_4( xdoc )
      xel  = REXML::Element.new( self.name )
      names.uniq.each do |nm|
        # Array of all items with this name
        a = self[nm]; max = a.size
        raise "DIN16557-4 does not support more than 9 repetitions" if max > 9
        raise "Lookup error (should never occur)" if max == 0
        if max == 1
          obj = a.first
          obj.to_din16557_4( xel ) unless obj.empty?
        else
          a.each_with_index do |obj, i| 
            obj.to_din16557_4( xel, i+1 ) unless obj.empty?
          end
        end
      end
      xdoc.elements << xel
    end
  end


  class CDE
    def to_din16557_4( xel, rep=nil )
      prefix = name
      prefix += rep.to_s if rep
      names.uniq.each do |nm|
        # Array of all items with this name
        a = self[nm]; max = a.size
        raise "DIN16557-4 does not support more than 9 repetitions" if max > 9
        raise "Lookup error (should never occur)" if max == 0
        if max == 1
          obj = a.first
          obj.to_din16557_4( xel, nil, prefix ) unless obj.empty?
        else
          a.each_with_index do |obj, i| 
            obj.to_din16557_4( xel, i+1, prefix ) unless obj.empty?
          end
        end
      end
    end
  end


  class DE
    def to_din16557_4( xel, rep=nil, prefix='' )
      nm = prefix + 'D' + name
      nm += rep.to_s if rep
      xel.attributes[nm] = to_s( true )
    end
  end

=begin
      de_instance_counter = Hash.new(0)
      xseg_or_cde.elements.each('DE') do |xde|
        de_name = xde.attributes['name']
        i = (xde.attributes['instance'] || 1).to_i - 1
        seg_or_cde[de_name][i].parse( xde.text, true )
      end
=end
end # module EDI::E



module EDI
  class Collection_HT
    #
    # NOTE: Makes sense only in the UN/EDIFACT context,
    # so we list this method here.
    #
    def to_din16557_4( xparent )
      header.to_din16557_4( xparent )
      each {|obj| obj.to_din16557_4( xparent )}
      trailer.to_din16557_4( xparent )
    end
  end
end
