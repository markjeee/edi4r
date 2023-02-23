#!/usr/bin/env ruby
# -*- encoding: iso-8859-1 -*-
#
# :main:README
# :title:sedas
#
# SEDAS module: API to parse (and create) SEDAS data
#
# == Synopsis
#
#  It module adds basic SEDAS capabilities, as were needed for a limited
#  SEDAS-to-EANCOM migration project.
#  Note that SEDAS is a "dying" standard, so it is not fully supported here.
#
# == Usage
#
#   require 'sedas'
#
# == Description
#
#  The edi4r base gem comes with a limited set of SEDAS data structures
#  focused on invoice data, as well as abstract classes for the
#  handling of general EDI data structures.
#  This add-on builds upon the same abstract classes and provides support
#  for SEDAS data.
#
#  Only one release (1993) is considered. Record types 00,01,98,99,
#  12-17/22-27, 29, 50, and 51 are supported, as well as follow-up types
#  01 (for 12/22, 15/25, 29), 02 (for 13/23, 16/26, 29), and 08
#  (for 12-17/22-27). 
#
# :include:../../AuthorCopyright
#--
# $Id: sedas.rb,v 1.2 2007/04/10 22:21:05 werntges Exp $
#
# $Log: sedas.rb,v $
# Revision 1.2  2007/04/10 22:21:05  werntges
# Final refinements, preparing pre-release
#
# Revision 1.1  2007/03/30 14:43:09  werntges
# Initial revision
#
#
#
# To-do list:
# * Support for generation of SEDAS data (low prio)
# * Removal of some remaining code from IDOC precursor source
# * Formal support of character sets
#


# SEDAS add-ons to EDI module
#	API to parse and create SEDAS
#

module EDI

# Notes:
#
# SEDAS data are organized as record sets. A physical file or
# transmission unit is always framed by record types 00 and 99.
# Within such a physical unit, one or more logical units may occur,
# framed by records 01 and 98.
#
# SEDAS data are self-contained already at the message level.
# An "Interchange" of the SEDAS type is just a concatenation
# of messages; a single message per Interchange is quite acceptable.
# However, one such message will usually map to several messages
# of the UN/EDIFACT type. As an example, a sequence of record types 29
# may map to one or several INVOIC messages (BGM+393), depending on
# the number of group changes (document number changes).
#
# Also note that SEDAS record types 50, 51 are considered master data.
# They are referred to by earlier records to avoid redundant data.
# Here we treat this master data block as a single "message" - but not
# with mapping in mind.
#
# Here we use the Interchange level only to maintain the information
# about the physical/logical unit data.
#

 module S

  class Interchange < EDI::Interchange

    attr_accessor :charset, :output_mode
    attr_reader :basedata

     def init_ndb
       @basedata = EDI::Dir::Directory.create( root.syntax )
     end

     # Currently, this is almost a dummy method
     # It might grow into something useful.
     # Keep it to stay consistent with other module add-ons.
     #
     def check_consistencies
       if 'S' != @syntax
         raise "#{@syntax} - syntax must be 'S' (SEDAS)!"
       end

       case @charset
       when 'ISO-8859-15'
         # ok
         #   when '...'
       else
         raise "#{@charset} - character set not supported!"
       end
       # Add more rules ...
     end


     def initialize( user_par={} )
       super( user_par ) # just in case...
       par = {:syntax  => 'S',
              :output_mode => nil,
              :charset => 'ISO-8859-15', # not used yet...
       }.update( user_par )

       @syntax = par[:syntax]	# UN/EDIFACT
       @output_mode = par[:output_mode]
       @charset = par[:charset]

       # Temporary - adjust to current SEDAS needs:
       @illegal_charset_pattern = /[^-A-Za-z0-9 .,()\/=!%"&*;<>'+:?\xa0-\xff]+/

       check_consistencies
       init_ndb
     end


    #
    # Reads SEDAS data from given stream (default: $stdin),
    # parses it and returns an Interchange object
    #
    def Interchange.parse( hnd=$stdin, auto_validate=true )
      builder = StreamingBuilder.new( auto_validate )
      builder.go( hnd )
      builder.interchange
    end

    #
    # Read +maxlen+ bytes from $stdin (default) or from given stream
    # (SEDAS data expected), and peek into first segment (00).
    #
    # Returns an empty Interchange object with a properly header filled.
    #
    # Intended use: 
    #   Efficient routing by reading just 00 data: sender/recipient/ref/test
    #
    def Interchange.peek(hnd=$stdin, params={}) # Handle to input stream
      builder = StreamingBuilder.new( false )
      if params[:deep_peek]
        def builder.on_segment( s, tag )
        end
      else
        def builder.on_01( s )
          throw :done
        end
        def builder.on_msg_start( s, tag )
          throw :done  # FIXME: UNZ??
        end
      end
      builder.go( hnd )
      builder.interchange
    end


     def Interchange.parse_xml(xdoc)
       ic = Interchange.new # ({:sap_type => xdoc.root.attributes['version']})
       xdoc.root.elements.each('Message') do |xel|
         ic.add( Message.parse_xml( ic, xel ) )
       end
       ic
     end  


     def new_msggroup(params)
       MsgGroup.new(self, params)
     end

     def new_message(params)
       Message.new(self, params)
     end

     def new_segment(tag)
       Segment.new(self, tag)
     end


     def parse_message(list)
       Message.parse(self, list)
     end

     def parse_segment(buf)
       Segment.parse(self, buf)
     end

   end


   
   class MsgGroup < EDI::MsgGroup

     def new_message(params)
       Message.new(self, params)
     end

     def new_segment(tag)
       Segment.new(self, tag)
     end

     def parse_segment(buf)
       Segment.parse(self, buf)
     end

   end


   class Message < EDI::Message
     attr_accessor :maindata
     #    private_class_method :new

#     @@msgCounter = 1

     def preset_msg(user_par={})
       # lower-case names for internal keys, 
       # upper-case names for EDI_DC field names
       par = {:sedas_type => '12',
       }.update( user_par )
       @pars = par
     end


     def initialize( p, user_par )
       super( p, user_par )
       #      @parent, @root = p, p.root

       # First param is either a hash or segment EDI_DC
       #  If Hash:    Build EDI_DC from given parameters
       #  If Segment: Extract some crucial parameters

       @maindata = Dir::Directory.create( root.syntax )
       if user_par.is_a? Hash
         preset_msg( user_par)
         @name = @pars[:sedas_type]

         @header = nil # new_segment(p.dc_sig.strip) # typically, "EDI_DC40"
         # @header.dIDOCTYP = @pars[:IDOCTYP]
         # etc.
=begin
       elsif user_par.is_a? EDI::S::Segment
         @header = user_par
         if @header.name !~ /^[12]2/
           raise "12/22 expected, '#{@header.name}' found!" 
         end
         @header.parent = self
         @header.root = self.root
         @pars = Hash.new
         @pars[:sedas_type]= header.name[0,2] # e.g. '12', '15'
         # @pars[:IDOCTYP] = @header.dIDOCTYP
#         @maindata = Dir::Directory.create( root.syntax,
#                                           :SEDASTYPE=> @pars[:sedas_type]
#                                           )
=end
       else
         raise "Parameter 'user_par': Illegal type!"
       end

       @trailer = nil
#       @@msgCounter += 1
     end


     def new_segment(tag)
       Segment.new(self, tag)
     end

     def parse_segment(buf)
       Segment.parse(self, buf)
     end


     def Message.parse (p, segment_list)
       # Segments comprise a single message

       # Temporarily assign p as segment parent, 
       # or else service segment lookup fails:
       raise "NOT SUPPORTED anymore!"
       header = p.parse_segment(segment_list.shift, p.dc_sig.strip)

       msg = p.new_message(header) # Now use header rec as template

       segment_list.each {|segbuf|  msg.add Segment.parse( msg, segbuf ) }

       msg.trailer = nil
       msg
     end


     def validate
       # Check sequence of segments against library,
       # thereby adding location information to each segment
       diag = EDI::Diagram::Diagram.create(root.syntax,
                                           :SEDASTYPE=> @pars[:sedas_type]
                                           )
       ni = EDI::Diagram::NodeInstance.new(diag)
#       puts "Initial node instance is: #{ni.name}"
       if @header
         ni.seek!( @header )
         @header.update_with( ni )
       end
       each {|seg|
#         if (key = seg.name) !~ /.*\d\d\d/
#           key = Regexp.new(key+'(\d\d\d)?')
#         end

         begin
           if ni.seek!(seg.name) # key) # (seg)
             seg.update_with( ni )
           else
             raise "seek! failed for #{seg.name} when starting at #{ni.name}"
           end 
=begin
         rescue EDI::EDILookupError
           warn key
           if key =~ /(.*)\d\d\d/
             key = $1 
             retry
           else
             raise
           end
=end
         end
       }
#       ni.seek!( @trailer )
       #    @trailer.update_with( ni )

       # Now check each segment
       super
     end
     
   end



   class Segment < EDI::Segment

     def initialize(p, tag)
       super( p, tag )

       segment_list = root.basedata.segment(tag)
       raise "Segment \'#{tag}\' not found" if segment_list.nil?
       
       #  each_BCDS_Entry('s'+tag) do |entry| # This does not work here...
       segment_list.each do |entry|
         id = entry.name
         status = entry.status
         # puts "Seeking DE >>#{tag+':'+id}<<"
         # Regular lookup
         fmt = fmt_of_DE(tag+':'+id)
         add new_DE(id, status, fmt)
       end
     end


     def new_DE(id, status, fmt)
       DE.new(self, id, status, fmt)
     end


     # Buffer contains a single segment (line)
     def Segment.parse (p, buf, tag_expected=nil)
       case tag = buf[0,2]
       when '00', '01', '03', '51', '96', '98','99'
         # take just the rec_id as tag
       else
         # append "Folgesatz" id
         tag +=buf[146,2]
       end
       seg = p.new_segment(tag)

       if tag_expected and tag_expected != tag
         raise "Wrong segment name! Expected: #{tag_expected}, found: #{tag}"
       end

       seg.each {|obj| obj.parse(buf) }
       seg
     end


     def to_s
       line = ''
       crlf = "\x0d\x0a"
       return line if empty?
       if root.output_mode == :linebreak
         each do |obj|
           next if obj.empty?
           line << name.ljust(12)+obj.name.ljust(12)+'['+obj.to_s+']' unless obj.empty?
         end
       else
         last_nonempty_de = nil
         each {|obj| last_nonempty_de = obj unless obj.empty? }
         each {|obj| line += obj.to_s; break if obj.object_id == last_nonempty_de.object_id }
       end
       line << crlf
       line
     end

     private

     # SEDAS field names direcly qualify as Ruby method names,
     # and there are neither composites nor arrays, so we can
     # simplify access to fields here. 
     #

     def method_missing(sym, *par)
      if sym.id2name =~ /^(\w+)(=)?/
        rc = lookup($1)
        if rc.is_a? Array
          if rc.size==1
            rc = rc.first
          elsif rc.size==0
            return super
          end
        end
        if $2
          # Setter
          raise TypeError, "Can't assign to a #{rc.class} object '#$1'" unless rc.is_a? DE
          rc.value = par[0]
        else
          # Getter
          return rc.value if rc.is_a? DE
          err_msg =  "No DE with name '#$1' found, instead there is a '#{rc.class}'!"
          raise TypeError, err_msg
        end
      else
        super
      end
    end

  end


   # There are no CDEs in IDocs:
   # class CDE_E < CDE
   # end


   class DE < EDI::DE

     # ae, oe, ue, sz, Ae, Oe, Ue, Paragraph, `, ´
     @@umlaute_iso636_de = '{-}~[-]@`´'
     @@umlaute_cp850     = "\x84\x94\x81\xE1\x8E\x99\x9A\xF5''"
     @@umlaute_iso8859_1 = "\xE4\xF6\xFC\xDF\xC4\xD6\xDC\xA7''"

     def initialize( p, name, status, fmt )
       super( p, name, status, fmt )
       fmt =~ /(a|an|n|d|t)(\.\.)?(\d+):(\d+)/
       raise "Illegal format string in field #{name}: #{fmt}" if $3.nil? or $4.nil?
       @length, @offset = $3.to_i, $4.to_i-1
#       puts "#{name}: len=#{@length.to_s}, off=#{@offset.to_s}"
       # check if supported format syntax
       # check if supported status value
     end
     

     def parse( buf ) 	# Buffer contains segment line; extract sub-string!
#       msg = "DE #{@name}: Buffer missing or too short"
       if buf.nil? or buf.length < @offset# +@length
         @value = nil
         return
       end

       # Sure that "strip" is always ok, and that we can ignore whitespace??
#       case @name
#       when 'SEGNUM'
       @value = buf[@offset...@offset+@length]
       if self.format[0]==?n # Numerical?
         if @value =~ /^ *$/ # Optional numerical field
           @value = nil
           return
         end
         code = @value[-1]
         @value[-1] = ?0
         @value = @value.to_i

	 if RUBY_VERSION >= '1.9'
         case code
         when ?A..?I
           @value += (code.ord-?@.ord)
         when ?J..?R
           @value += (code.ord-?I.ord)
           @value = -@value
         when ?}, "\x81", "\xfc"       # ü (0xFC) to be confirmed
           @value = -@value
         when ?{, ?0, ' '  # Blank, ä to be confirmed
           # noop
         when ?1..?9
           @value += (code.ord-?0.ord)
         else
           raise "#{self.name}: #{code} is not a valid last char of a numerical field"
         end
	 else # older Ruby version
         case code
         when ?A..?I
           @value += (code-?@)
         when ?J..?R
           @value += (code-?I)
           @value = -@value
         when ?}, 0x81, 0xfc       # ü (0xFC) to be confirmed
           @value = -@value
         when ?{, ?0, 0x20  # Blank, ä to be confirmed
           # noop
         when ?1..?9
           @value += (code-?0)
         else
           raise "#{self.name}: #{code.chr} (#{code}) is not a valid last char of a numerical field"
         end
	 end # Ruby version 
       elsif @value.is_a? String
         @value.tr!(@@umlaute_cp850,     @@umlaute_iso8859_1)
         @value.tr!(@@umlaute_iso636_de, @@umlaute_iso8859_1)
       end
#       else
#         @value = buf[@offset...@offset+@length].strip
#       end
#       @value = nil if @value =~ /^\s*$/
     end


     def validate( err_count=0 )
       location = "#{parent.name} - #{@name}"
       @format =~ /((a|an|n|d|t)(\.\.)?(\d+)):\d+/
       fmt = [$2, $3, $4].join
       case $1
       when 'd8'
         if !empty? && value !~ /^\d{8}$/
           warn "#{location}: Format \'#@format\' violated: #@value"
           err_count+=1
         end
       when 't6'
         if !empty? && value !~ /^\d{6}$/
           warn "#{location}: Format \'#@format\' violated: #@value"
           err_count+=1
         end
       when /^[dt].*/
         warn "validate in DE #@name: Format \'#@format\' not validated yet!"
       else
         return super( err_count, fmt )
       end
       err_count
     end

     # TODO: reversal of charset mapping, debugging (round-circle ok?)
     #
     def to_s
#       return '' if empty?
       if self.format[0]==?n # Numerical?
	 if @value && @value < 0
	   @value = -@value
	   value_str = @value.to_s
	   value_str[-1] = case value_str[-1]
	     when '0' then '}'
	     when '1' then 'J'
	     when '2' then 'K'
	     when '3' then 'L'
	     when '4' then 'M'
	     when '5' then 'N'
	     when '6' then 'O'
	     when '7' then 'P'
	     when '8' then 'Q'
	     when '9' then 'R'
	     else raise "Illegal last digit in numeric value '#{value_str}'"
	   end
           value_str.rjust(@length,'0')[0,@length] # left-padded with '0'
	 else
           @value.to_s.rjust(@length,'0')[0,@length] # left-padded with '0'
	 end
       else
         @value.to_s.ljust(@length)[0,@length] # right-padded with ' '
       end
     end

   end


   #########################################################################
   #
   # = Class StreamingParser
   #
   # For a documentation, see class EDI::E::StreamingParser;
   # this class is its SEDAS equivalent.
    
  class StreamingParser

    def initialize
      @path = 'input stream'
    end

    # Convenience method. Returns the path of the File object
    # passed to method +go+ or just string 'input stream'
    def path
      @path
    end

    # Called at start of reading - overwrite for your init purposes.
    # Note: Must *not* throw <tt>:done</tt> !
    #
    def on_interchange_start
    end

    # Called at EOF - overwrite for your cleanup purposes.
    # Note: Must *not* throw <tt>:done</tt> !
    #
    def on_interchange_end
    end

    # Called when UNB or UIB encountered
    #
    def on_00( s )
    end

    # Called when UNZ or UIZ encountered
    #
    def on_99( s )
    end

    # Called when UNG encountered
    #
    def on_01( s )
    end

    # Called when UNE encountered
    #
    def on_98( s )
    end

    # Called when UNH or UIH encountered
    #
    def on_msg_start( s )
    end

    # Called when UNT or UIT encountered
    #
    def on_msg_end
    end

    # Called when any other segment encountered
    #
    def on_segment( s, tag )
    end

    # This callback is usually kept empty. It is called when the parser
    # finds strings between segments or in front of or trailing an interchange.
    #
    # Strictly speaking, such strings are not permitted by the SEDAS
    # syntax rules. However, some people e.g. seem to add empty lines
    # at the end of a file. The default settings thus ignore such occurrences.
    #
    # If you need strict conformance checking, feel free to put some code
    # into this callback method, otherwise just ignore it.
    # 
    #
    def on_other( s )
    end

    # Called upon syntax errors. Parsing should be aborted now.
    #
    def on_error(err, offset, fragment, c=nil)
      raise err, "offset = %d, last chars = %s%s" % 
        [offset, fragment, c.nil? ? '<EOF>' : c.chr]
    end

    #
    # The one-pass reader & dispatcher of segments, SAX-style.
    #
    # It reads sequentially through the given records and
    # generates calls to the callbacks <tt>on_...</tt>
    # Parameter +hnd+ may be any object supporting method +gets+.
    #
    def go( hnd )
      rec, rec_id, line_no, rec_no, pos_no, folgesatz = nil, nil, 0, 0, 0, nil
      @path = hnd.path if hnd.respond_to? :path
      @msg_begun = @msg_50_begun = false
      @msg_29_nr = nil

      self.on_interchange_start

      catch(:done) do
        loop do
          begin
            rec = hnd.gets
            line_no += 1
            break if rec.nil?
            rec.chomp!
            unless rec =~ /^\s*$/
              pos_no = rec[125,6].to_i
              rec_id = rec[0,2]
              raise "Wrong record order at line #{line_no}! Expected: #{pos_no}, found: #{rec_no}" if rec_no != pos_no && rec_id !~ /00|01|99/
              folgesatz = rec[146,2] # not valid for 00,01,03,51,96,98,99
            end
            case rec
            when /^\s*$/
              self.on_other( rec )
            when /^00/
              self.on_00( rec )
            when /^99/
              self.on_99( rec )
            when /^01/
              rec_no = pos_no
              # raise "SA01: pos_nr=#{pos_no}, expected 1" if pos_no != 1
              self.on_01( rec )
            when /^98/
              @msg_50_begun = false
              self.on_98( rec )

            when /^[12][25]/
              self.on_msg_end if @msg_begun
              self.on_msg_start( rec ) if folgesatz=='00'
              self.on_segment( rec, rec_id+folgesatz )

            when /^[12][3467]/
              self.on_segment( rec, rec_id+folgesatz )

            when /^29/  # Group change triggers new message!
              if rec[30,1]=='2' # Reli-Nr.
                nr_of_sa29 = rec[31..37] 
              else
                raise "Unexpected SA29 condition"
              end
              if @msg_29_nr != nr_of_sa29 # Group change!
                self.on_msg_end if @msg_begun
                self.on_msg_start( rec )
                @msg_29_nr = nr_of_sa29
              end
              self.on_segment( rec, rec_id+folgesatz )

            when /^50/  # Only first occurrence of SA50 starts a message!
              if not( @msg_50_begun )
                self.on_msg_end if @msg_begun
                raise "First SA50 - syntax error!" if folgesatz!='00'
                self.on_msg_start( rec )
                @msg_50_begun = true
              end
              self.on_segment( rec, rec_id+folgesatz )

            when /^51/
              self.on_segment( rec, '5100' )

            else
              $stderr.puts "Unsupported record type: '#{rec_id}#{folgesatz}' - ignored"
            end

          rescue
            warn "Error at record #{rec_no}, record id=#{rec_id}"
            raise
          end
          rec_no += 1
        end # loop

      end # catch(:done)

      self.on_interchange_end
#      offset
    end
  end # StreamingParser

  #########################################################################
  #
  # = Class StreamingBuilder
  #
  # The StreamingBuilder parses the input stream just like StreamingParser
  # and in addition builds the complete interchange.
  #
  # This method is the new basis of Interchange.parse. You might want to
  # study its callbacks to get some ideas on how to create a special-purpose
  # parser/builder of your own.
  #

  class StreamingBuilder < StreamingParser
    def initialize(auto_validate=true)
      @ic = nil
      @curr_group = @curr_msg = nil
      @una = nil
      @is_iedi = false
      @auto_validate = auto_validate
    end


    def interchange
      @ic
    end


    def on_00( s )
      @ic = Interchange.new
      @ic.header = @ic.parse_segment( s )
    end

    def on_99( s )
      @ic.trailer = @ic.parse_segment( s )
    end

    def on_01( s )
      @curr_group = @ic.new_msggroup( @ic.parse_segment( s ) )
      @curr_group.header = @curr_group.parse_segment( s )
    end

    def on_98( s )
      self.on_msg_end if @msg_begun
      @curr_group.trailer = @curr_group.parse_segment( s )
      @ic.add( @curr_group, @auto_validate )
    end

    def on_msg_start( s )
      @curr_msg = @curr_group.new_message( :sedas_type => s[0,2] )
      @msg_begun = true
#      @curr_msg.header = Segment.parse( @curr_msg, s )
    end

    def on_msg_end
      @curr_group.add( @curr_msg )
      @msg_begun = false
      @msg_29_nr = nil
    end

    # Overwrite this method to react on segments of interest
    #
    # Note: For a skeleton Builder (just UNB/UNG/UNT etc), overwrite with
    # an empty method.
    #
    def on_segment( s, tag )
      @curr_msg.add @curr_msg.parse_segment( s )
      super
    end


    def on_other( s )
      warn "Empty record/line found - ignored!"
    end

    def on_interchange_end
      if @auto_validate
        @ic.header.validate
        @ic.trailer.validate
        # Content is already validated through @ic.add() and @curr_group.add()
      end
    end

  end # StreamingBuilder

 end # module S
end # module EDI
