#!/usr/bin/env ruby
# -*- encoding: ISO-8859-1 -*-
#
# Tool to validate, list and analyze EDI data, based on EDI4R
#
# Author:  Heinz W. Werntges (edi@cs.hs-rm.de)
#
# License: This code is put under the Ruby license
#
# Copyright (c) 2006, 2011 Heinz W. Werntges, RheinMain University of Applied Sciences, Wiesbaden
#

if $DEBUG  # Include statement during test setup:
  $:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
  require 'edi4r'
  require 'edi4r/edifact'
  require "edi4r/rexml"
  require "edi4r-tdid"
else       # Regular include statements:
  require "rubygems"
  require "edi4r"
  begin
    require "edi4r-idoc"
  rescue LoadError # Ignore error
  end
  require "edi4r/edifact"
  require "edi4r/ansi_x12"
  require "edi4r/rexml"
  require "edi4r-tdid"
end
require 'zlib'
require 'getoptlong'


def usage
  $stderr.puts "Usage:\t#{$0} [-n|-v] [-i|-l] [-o] [file(s)...]"
  $stderr.puts "Usage:\t#{$0} -p file(s)..."
  $stderr.puts "Options:"
  $stderr.puts "\t--validate, --valid, -v\tValidate EDI files"
  $stderr.puts "\t--no-valid, -n\t\tDo not validate EDI files (default)"
  $stderr.puts "\t--list, -l\t\tList EDI files one segment per line, indented"
  $stderr.puts "\t--indent-off, -o\tSwitch indent off when in list mode"
  $stderr.puts "\t--peek, -p\tPeek into header & report some crucial data"
  $stderr.puts "\t--inspect, -i\t\tInspect mode, list content with more details"
  $stderr.puts"NOTE:\t-n, -v and -l, -i are mutually exclusive."
  exit 0
end


def headline_peek_result
  puts "Filename\tSender\t\tRecip\t\tRef\t\tTest", "=" * 78
end

def report_peek_result( ic_stub, fname )
  h = ic_stub.header
  case s=ic_stub.syntax

  when 'E'
    params = if ic_stub.is_iedi?
               [fname, h.cS002.d0004, h.cS003.d0010, h.cS302.d0300, h.d0035==1]
             else
               [fname, h.cS002.d0004, h.cS003.d0010, h.d0020, h.d0035==1]
             end
    puts "%15.15s\t%13s\t%13s\t%14s\t%s" % params

  when 'A'
    params = [fname, h.dI06, h.dI07, h.dI12, h.dI14=='T']
    puts "%15.15s\t%13s\t%13s\t%14s\t%s" % params

  when 'I'
    puts "%15.15s\tSAP IDocs not supported yet" % [fname]
    
  else
    puts "%15.15s\tSyntax %s not supported" % [fname, s]
  end
end


class MyOptions
  attr_accessor :validate, :list, :inspect, :peek, :no_indent

  def initialize
    @validate = false
    @list = false
    @inspect = false
    @peek = false
    @no_indent = false
  end
end


opts = GetoptLong.new(
  ['--validate', '--valid', '-v', GetoptLong::NO_ARGUMENT],
  ['--no-valid',            '-n', GetoptLong::NO_ARGUMENT],
  ['--list',                '-l', GetoptLong::NO_ARGUMENT],
  ['--peek',                '-p', GetoptLong::NO_ARGUMENT],
  ['--indent-off',          '-o', GetoptLong::NO_ARGUMENT],
  ['--inspect',             '-i', GetoptLong::NO_ARGUMENT],
  ['--help',                '-h', GetoptLong::NO_ARGUMENT]
)
my_opts = MyOptions.new

opts.each do |opt, arg|
  case opt
  when '--validate';	my_opts.validate = true
  when '--no-valid';	my_opts.validate = false
  when '--list';	my_opts.list = true; my_opts.inspect = false
  when '--peek';        my_opts.peek = true
  when '--indent-off';  my_opts.no_indent = true
  when '--inspect';	my_opts.list = false; my_opts.inspect = true
  else; usage
  end
end

rc = 0 # return code

if ARGV.empty?

  usage if my_opts.peek # Does not work with $stdin!

  ic = EDI::E::Interchange.parse($stdin, false) or exit
  rc = ic.validate if my_opts.validate
  if my_opts.list
    ic.output_mode = my_opts.no_indent ? :linebreak : :indented
    print ic
  end
  print ic.inspect if my_opts.inspect

else

  if my_opts.peek

    headline_peek_result
    ARGV.each do |fname|
      report_peek_result( EDI::Interchange.peek(File.open(fname)), fname )
    end

  else

    ARGV.each do |fname|
      File.open(fname) do |hnd|
        puts "------------ #{fname} ------------" if ARGV.size > 1
        ic = EDI::Interchange.parse(hnd, false)
        rc += ic.validate if my_opts.validate
        if my_opts.list
          ic.output_mode = my_opts.no_indent ? :linebreak : :indented
          print ic.to_s
        end
        print ic.inspect if my_opts.inspect
      end
    end
  end
end
exit( rc )

