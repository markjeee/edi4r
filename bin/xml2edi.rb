#!/usr/bin/env ruby

# $Id: xml2edi.rb,v 1.1 2006/08/01 11:20:56 werntges Exp $

# $Log: xml2edi.rb,v $
# Revision 1.1  2006/08/01 11:20:56  werntges
# Initial revision
#
#
# Author:  Heinz W. Werntges (edi@informatik.fh-wiesbaden.de)
#
# License: This code is put under the Ruby license
#
# Copyright (c) 2006 Heinz W. Werntges, FH Wiesbaden
#

# SYNOPSIS:
#
# $ xml2edi.rb file1 [file2 ...]
# ...
# $ zcat somefile.xml.gz | xml2edi.rb
# ...
#
# DESCRIPTION:
#
# This script turns XML files into EDI (EDIFACT or SAP IDOC) documents.
# 

require "rubygems"
require_gem "edi4r"
require_gem "edi4r-tdid"
# require_gem "edi4r-idoc"
require "edi4r/edifact"
require "edi4r/rexml"

def to_edi( xdoc )
  ic = EDI::Interchange.parse_xml xdoc
  $stdout.print ic
end


if ARGV.size == 0
  xdoc = REXML::Document.new $stdin
  to_edi( xdoc )
else
  ARGV.each do |fname|
    xdoc = REXML::Document.new( File.open(fname,'r') )
    to_edi( xdoc )
  end
end
