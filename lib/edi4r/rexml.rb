# -*- encoding: iso-8859-1 -*-
# Add-on to EDI module "EDI4R"
# Classes for XML support, here: Basic classes
#
# :include: ../../AuthorCopyright
#
# $Id$
#--
# $Log: rexml.rb,v $
# Revision 1.2  2007/03/14 23:59:25  werntges
# Bug fix (Joko's report) in DE#to_xml: Attribute "instance" generated now
#
# Revision 1.1  2006/08/01 11:14:29  werntges
# Initial revision
#
#++
# To-do list:
#	all	-	Just starting this...
#
# This is the REXML module of edi4r
#
# It adds methods to most of the basic classes which enable EDI objects
# to represent themselves in a generic XML document type, and to read back
# instances of this document type.
#
# This version of XML support for EDI4R relies on REXML.

require 'rexml/document'
# require 'diagrams-xml'
require 'edi4r/ansi_x12-rexml' if EDI.constants.include? 'A'
require 'edi4r/edifact-rexml' if EDI.constants.include? 'E'
require 'edi4r/idoc-rexml'    if EDI.constants.include? 'I'

module EDI

  #########################################################################
  #
  # Utility: Separator method for UN/EDIFACT segments/CDEs
  # 

  class Collection_S

    def to_xml( xel_parent, instance=1 )
      xel  = REXML::Element.new( normalized_class_name ) 
      xel.attributes["name"]  = @name
      xel.attributes["instance"]  = instance.to_s if instance > 1
      xel_parent.elements << xel
      instance_counter = Hash.new(0)
      each do |obj| 
        i = (instance_counter[obj.name] += 1)
        obj.to_xml( xel, i ) unless obj.empty?
      end
      xel
    end
  end


  class Collection_HT

    def to_xml( xel_parent )
      xel  = REXML::Element.new( normalized_class_name ) 
      xel.attributes["name"]  = @name
      xel_parent.elements << xel

      xhd = to_xml_header( xel )
      each { |obj| obj.to_xml( xel ) }
      xtr = to_xml_trailer( xel )
      [xel, xhd, xtr] # You might want to add something ...
    end


    def to_xml_header( xparent )
      if @header
        xparent << (xel = REXML::Element.new( 'Header' ))
        @header.to_xml( xel )
        return xel
      end
      nil
    end

    def to_xml_trailer( xparent )
      if @trailer
        xparent << (xel = REXML::Element.new( 'Trailer' ))
        @trailer.to_xml( xel )
        return xel
      end
      nil
    end

  end


  class Interchange

    # This is a dispatcher method for your convenience, similar to
    # EDI::Interchange.parse. It may be used for all supported EDI standards.
    #
    # hnd:: A REXML document or something that can be turned into one,
    #       i.e. an IO object or a String object with corresponding contents
    #
    # Returns an Interchange object of the subclass specified by the
    # "standard_key" atribute of the root element, e.g. a EDI::E::Interchange.
    #
    def Interchange.parse_xml( hnd ) # Handle to REXML document
      unless hnd.is_a? REXML::Document or hnd.is_a? IO or hnd.is_a? String
        raise "Unsupported object type: #{hnd.class}"
      end
      hnd = REXML::Document.new( hnd ) if hnd.is_a? IO or hnd.is_a? String

      key = hnd.root.attributes['standard_key'].strip
      raise "Unsupported standard key: #{key}" if key == 'generic'
      EDI::const_get(key)::const_get('Interchange').parse_xml( hnd )
#      class_sym = (key+'Interchange').intern
#      EDI::const_get(class_sym).parse_xml( hnd )
    end


    def to_xml( xel_parent )
      externalID = "PUBLIC\n" + " "*9
      externalID += "'-//Hochschule RheinMain FB DCSM//DTD XML Representation of EDI data V1.2//EN'\n"
      externalID += " "*9
      externalID += "'http://edi01.cs.hs-rm.de/edi4r/edi4r-1.2.dtd'"
      xel_parent << REXML::XMLDecl.new
      xel_parent << REXML::DocType.new( normalized_class_name, externalID )

      rc = super

      xel = rc.first
      pos = self.class.to_s =~ /EDI::((.*?)::)?Interchange/
      raise "This is not an Interchange object: #{rc}!" unless pos==0
      xel.attributes["standard_key"] = ($2 and not $2.empty?) ? $2 : "generic"
      xel.attributes["version"] = @version.to_s
      xel.attributes.delete "name"
      rc
    end

  end


  class MsgGroup

    # Note: Code is very similar to Message.parse_xml. Remove redundancy?

    def MsgGroup.parse_xml(p, xgrp)
      _header    = xgrp.elements["Header/Segment"]
      _trailer   = xgrp.elements["Trailer/Segment"]
      grp        = p.new_msggroup( Segment.parse_xml( p, _header ) )

      grp.header = Segment.parse_xml( grp, _header  ) if _header
      xgrp.elements.each('Message') {|xel| grp.add Message.parse_xml(grp, xel)}
      grp.trailer = Segment.parse_xml( grp, _trailer ) if _trailer

      grp
    end  

  end


  class Message

    def Message.parse_xml(p, xmsg)
      _header    = xmsg.elements["Header/Segment"]
      _trailer   = xmsg.elements["Trailer/Segment"]

      msg = p.new_message( Segment.parse_xml( p, _header ) )
      msg.header  = Segment.parse_xml( msg, _header  ) if _header

      xmsg.elements.each('descendant::Segment') do |xel|
        next if xel.parent.name =~ /Header|Trailer/
        msg.add Segment.parse_xml(msg, xel)
      end
      msg.trailer = Segment.parse_xml( msg, _trailer ) if _trailer

      msg
    end  


    # Build an XML document tree from 
    #   a) the linear sequence of segments
    #   b) metadata from the standards DB (attached to each segment)
    #
    # Track xml parent element for segments by level
    #
    # Add 'header' and 'trailer' wrapper element around
    #   header and trailer, if any
    #
    # Trigger segments and their depending segments get wrapped
    # in a 'SegmentGroup' element that bears the group name as its name.
    
    def to_xml( xel_parent )
      xel_msg = REXML::Element.new( 'Message' ) 
      xel_parent.elements << xel_msg

      # Default parent is XML message element itself
      #
      xel_parent_stack = Hash.new(xel_msg)

      xhd = to_xml_header( xel_msg )

      each do |seg|
        next if seg.empty?
        if seg.is_tnode?
          xgrp = REXML::Element.new( 'SegmentGroup' )
          xgrp.attributes["name"] = seg.sg_name
          xel_parent_stack[seg.level - 1] << xgrp
          seg.to_xml( xgrp )
          xel_parent_stack[seg.level] = xgrp
        else
          seg.to_xml( xel_parent_stack[seg.level - 1] )
        end
      end

      xtr = to_xml_trailer( xel_msg )
      [xel_msg, xhd, xtr]
    end

  end


  class Segment

    def Segment.parse_xml( p, xseg )
      tag = xseg.attributes['name']
      seg = p.new_segment(tag)
      xseg.elements.each('CDE') do |xcde|
        cde_name = xcde.attributes['name']
        i = (xcde.attributes['instance'] || 1).to_i - 1
        cde = seg[cde_name][i]
        Segment.parse_xml_de( cde, xcde )
      end
      Segment.parse_xml_de( seg, xseg )
      seg
    end

    private
    
    def Segment.parse_xml_de( seg_or_cde, xseg_or_cde )
      de_instance_counter = Hash.new(0)
      xseg_or_cde.elements.each('DE') do |xde|
        de_name = xde.attributes['name']
        i = (xde.attributes['instance'] || 1).to_i - 1
        seg_or_cde[de_name][i].parse( xde.text, true )
      end
    end

  end



  class DE

    def to_xml( xel_parent, instance=1 )
      xel = REXML::Element.new( 'DE' ) 
      xel.attributes["name"] = @name
      xel.attributes["instance"] = instance.to_s if instance > 1
      xel_parent.elements << xel
      xel.text = self.to_s( true ) # don't escape!
      xel
    end
  end

end # module EDI
