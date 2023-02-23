#!/usr/bin/env ruby
# :include: ../AuthorCopyright

# Load path magic...
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'

require 'edi4r'
require 'edi4r/edifact'

#######################################################################
# Test the streaming parser with a large interchange
#
# Instead of mapping, we derive some statistics:
#   Count number of line items, report no. of messages

module MyParserAddons

  attr_accessor :lin, :all

  def on_other( s )
    $stderr.puts "other: #{s}"
  end

  def on_segment( s, tag )
    case tag
    when 'LIN'
      self.lin += 1
      self.all += 1
    else
      self.all += 1
    end
    super
  end

  def to_s
    "Found %d LIN segments, %d total segments" % [self.lin, self.all]
  end
end


class MyParser < EDI::E::StreamingParser
  include MyParserAddons

  def initialize
    @lin = @all = 0
    super
  end
end


class MyLWBuilder < EDI::E::StreamingBuilder
  include MyParserAddons

  def initialize( validate )
    @lin = @all = 0
    super
  end

  def on_segment( s, tag )
    case tag
    when 'LIN'
      self.lin += 1
      self.all += 1
    else
      self.all += 1
    end
    # super
  end

  def on_interchange_end
#    @ic.validate
#    super
  end
end


class MyBuilder < EDI::E::StreamingBuilder
  include MyParserAddons

  def initialize( validate )
    @lin = @all = 0
    super
  end
end


class MyDemoParser < EDI::E::StreamingParser
  attr_reader :counters
  
  def initialize
    @counters = Hash.new(0)
    super
  end
  
  def on_segment( s, tag )
    @counters[tag] += 1
  end
end
  

class StreamParser_Tests < Test::Unit::TestCase

  def test_streaming_parser
    parser = MyParser.new
    assert_nothing_raised{ parser.go File.open('in1.edi') }
    assert_equal( 2, parser.lin )
    assert_equal( 35, parser.all )

    # Syntax check
    #
    parser = EDI::E::StreamingParser.new
    assert_raise(EDI::E::EDISyntaxError){ parser.go( File.open('damaged_file.edi') ) }
  end

  def test_sample_code
    assert_nothing_raised {
      parser = MyDemoParser.new
      parser.go( File.open( 'remadv101.edi' ) )
      # parser.go( File.open( 'I0002352726' ) ) # Huge interchange, 5MB
      puts "Segment tag statistics:"
      parser.counters.keys.sort.each do |tag|
        print "%03s: %4d\n" % [ tag, parser.counters[tag] ]
      end
    }
    parser = EDI::E::StreamingParser.new
    def parser.on_segment( s, tag ) # singleton
      if tag == 'AJT'
        puts "Interchange in '#{self.path}' contains at least one segment AJT."
        puts "Here is its contents: #{s}"
        throw :done   # Skip further parsing
      end
    end
    def parser.on_unz_uiz( s, tag )
      puts "Interchange in '#{self.path}' does NOT contain a segment AJT!"
    end
    assert_nothing_raised do
      parser.go( File.open( 'in1.edi' ) )
      parser.go( File.open( 'remadv101.edi' ) )
    end

  end

  def test_streaming_lightweight_builder
    builder = MyLWBuilder.new( false )
    assert_nothing_raised{ builder.go File.open('I0002352726') }
    ic = builder.interchange
    assert_equal( 35679, builder.lin )
    assert_equal( 290947, builder.all )
    assert_equal( 28, ic.size )
  end

  def test_streaming_builder
    builder = MyBuilder.new( false )
    assert_nothing_raised{ builder.go File.open('in1.edi') }
    ic = builder.interchange
    assert_equal( 2, builder.lin )
    assert_equal( 35, builder.all )
    assert_equal( 1, ic.size )
    assert_nothing_raised{ assert(ic.validate) }

    builder = MyBuilder.new( true )
    assert_nothing_raised{ builder.go File.open('groups.edi') }
  end

end
