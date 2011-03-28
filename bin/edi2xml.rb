#!/usr/bin/env ruby

# $Id: edi2xml.rb,v 1.1 2006/08/01 11:20:24 werntges Exp $

# $Log: edi2xml.rb,v $
# Revision 1.1  2006/08/01 11:20:24  werntges
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
# $ edi2xml.rb [-D] file1 [file2 ...]
# ...
# $ edi2xml.rb [-D] -Z edifact_file.gz 
# ...
# $ zcat edifact_file.gz | edi2xml.rb [-s E]
# ...
#
# DESCRIPTION:
#
# This script turns EDIFACT files into XML documents,
# either according to DIN 16557-4 or to a generic DTD supplied by this project.
# 

require "rubygems"
require_gem "edi4r"
require_gem "edi4r-tdid"
#require_gem "edi4r-idoc"
require "edi4r/edifact"
require "edi4r/rexml"

require "getoptlong"


def output( ic )
  if $din_mode
    fail "DIN 16557 applies only to UN/EDIFACT data" unless ic.syntax=='E'
    ic.to_din16557_4.write($stdout,0)
  else
    ic.to_xml.write($stdout,0)
  end
end


def usage_and_exit
  puts <<EOT
Usage:
  #$0 [-D] [files ...]
  #$0 [-D] -z edifile.gz [files ...]     (Zlib required)
  #$0 -s E|I [-D]   (reads from stdin, E)difact or SAP I)doc)
Options:
 -d    Activates debug mode by setting $DEBUG=true
 -D    Generate DIN 16557-4 output.
 -s k  Set standard key, k=E for UN/EDIFACT (default) or k=I for SAP IDOC
       (currently only E supported).
 -z    Require Zlib. You may then pass gzipped files directly.
       Note that Zlib is not always available.
EOT

  exit 0
end

opts = GetoptLong.new(
                      ["--standard-key", "-s", GetoptLong::REQUIRED_ARGUMENT ],
                      ["--debug",        "-d", GetoptLong::NO_ARGUMENT ],
                      ["--DIN",          "-D", GetoptLong::NO_ARGUMENT ],
                      ["--help",         "-h", GetoptLong::NO_ARGUMENT ],
                      ["--zlib",         "-z", GetoptLong::NO_ARGUMENT ]
                      )

opts.each do |opt, arg|
  case opt
  when "--debug"
    $DEBUG = true
  when "--DIN"
    $din_mode = true
  when "--help"
    usage_and_exit()
  when "--standard-key"
    $STD_key = arg
  when "--zlib"
    require 'zlib'
  end
end


if ARGV.size == 0
  $STD_key = 'E' unless $STD_key # default is EDIFACT
  ic = EDI.const_get($STD_key).const_get('Interchange').parse or exit
  output( ic )
else
  usage_and_exit() if $STD_key
  ARGV.each do |fname|
    output( EDI::Interchange.parse( File.open(fname,'r') ) )
  end
end
