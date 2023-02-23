#!/usr/bin/env ruby
# -*- encoding: ISO-8859-1 -*-
#
# Author:  Heinz W. Werntges (edi@cs.hs-rm.de)
#
# License: This code is put under the Ruby license
#
# Copyright (c) 2006, 2011 Heinz W. Werntges, RheinMain University of Applied Sciences, Wiesbaden
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
# This script turns XML files into EDI (EDIFACT or ANSI X12 or SAP IDOC) documents.
# 

require "rubygems"
require "edi4r"
require "edi4r-tdid"
# require_gem "edi4r-idoc"
require "edi4r/edifact"
require "edi4r/ansi_x12"
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
