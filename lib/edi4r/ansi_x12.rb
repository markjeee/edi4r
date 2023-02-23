# -*- encoding: iso-8859-1 -*-
# ANSI X.12 add-ons to EDI module,
# API to parse and create ANSI X.12 data
#
# :include: ../../AuthorCopyright
#
# $Id$
#--
#
# Derived from "edifact.rb" v 1.10 on 2006/08/01 11:14:07 by HWW
#
# To-do list:
#	all		- just starting
#++
#
# This is the ANSI X12 module of edi4r (hence '::A')
#
# It implements ANSI X12 versions of classes Interchange, MsgGroup, Message, 
# Segment, CDE, and DE in sub-module 'A' of module 'EDI'.

module EDI::A

  #
  # Use pattern for allowed chars of extended charset if none given explicitly
  #
  Illegal_Charset_Patterns = Hash.new(/[^-A-Za-z0-9!"&'()*+,.\/:;?= %~@\[\]_{}\\|<>#\$\x01-\x07\x09\x0A-\x0D\x11-\x17\x1C-\x1F]+/) # Default is Extended set!
  Illegal_Charset_Patterns['Basic'] =     /[^-A-Z0-9!"&'()*+,.\/:;?= \x07\x09\x0A-\x0D\x1C-\x1F]+/
  Illegal_Charset_Patterns['Extended'] =  /[^-A-Za-z0-9!"&'()*+,.\/:;?= %~@\[\]_{}\\|<>#\$\x01-\x07\x09\x0A-\x0D\x11-\x17\x1C-\x1F]+/
  # more to come...


  class EDISyntaxError < ArgumentError
  end


  #######################################################################
  #
  # Interchange: Class of the top-level objects of ANSI X12 data
  #
  class Interchange < EDI::Interchange

    # attr_accessor :show_una
    attr_reader :e_linebreak, :e_indent # :nodoc:
    attr_reader :charset # :nodoc:
    attr_reader :groups_created
    attr_reader :ce_sep, :de_sep, :seg_term, :rep_sep
    attr_reader :re_ce_sep, :re_de_sep

    @@interchange_defaults = {
      :charset => 'UNOB',
      :version => "00401",
      :ce_sep => ?\\,
      :de_sep => ?*,
      :rep_sep => ?^,
      :seg_term => ?~,

      :sender => nil, :recipient => nil,
      :interchange_control_reference => 1,
      :interchange_control_standards_id => 'U',
      :acknowledgment_request => 0, :test_indicator => 'P',
      :output_mode => :verbatim
    }
    @@interchange_default_keys = @@interchange_defaults.keys

    # Create an empty ANSI X.12 interchange
    #
    # == Supported parameters (passed hash-style):
    #
    # === Essentials, should not be changed later
    # :charset ::  Not applicable, do not use. Default = 'UNOB'
    # :version ::  Sets I11 (ISA12), default = '00401'
    #
    # === Optional parameters affecting to_s, with corresponding setters
    # :output_mode :: See setter output_mode=(), default = :verbatim
    # :ce_sep ::   Component element separator, default = ?\\
    # :de_sep ::   Data element separator, default = ?*
    # :rep_sep ::  Repetition element separator, default = ?^ (version 5)
    # :seg_term :: Segment terminator, default = ?~
    #
    # === Optional ISA presets for your convenience, may be changed later
    # :sender ::    Presets DE I07, default = nil
    # :recipient :: Presets DE I09, default = nil
    # :interchange_control_reference ::    Presets DE I12, default = '1'
    # :interchange_control_standards_id :: Presets DE I10, default = 'U'
    # :acknowledgment_request ::  Presets DE I13, default = 0
    # :test_indicator ::          Presets DE I14, default = 'P'
    #
    # === Notes
    # * Date (I08) and time (I09) are set to the current values automatically.
    # * Add or change any data element later.
    #
    # === Examples:
    # - ic = EDI::A::Interchange.new  # Empty interchange, default settings
    # - ic = EDI::A::Interchange.new(:output_mode=> :linebreak)

    def initialize( user_par={} )
      super( user_par ) # just in case...
      if (illegal_keys = user_par.keys - @@interchange_default_keys) != []
        msg = "Illegal parameter(s) found: #{illegal_keys.join(', ')}\n"
        msg += "Valid param keys (symbols): #{@@interchange_default_keys.join(', ')}"
        raise ArgumentError, msg
      end
      par = @@interchange_defaults.merge( user_par )

      @groups_created = 0

      @syntax = 'A' # par[:syntax]	# A = ANSI X12
      @charset = par[:charset] # FIXME: Outdated?

      @version = par[:version]

      @ce_sep  = par[:ce_sep]
      @re_ce_sep = Regexp.new( Regexp.escape( @ce_sep.chr ) )
      @de_sep  = par[:de_sep]
      @re_de_sep = Regexp.new( Regexp.escape( @de_sep.chr ) )
      @rep_sep = par[:rep_sep]
      @seg_term = par[:seg_term]

      self.output_mode = par[:output_mode]

      check_consistencies
      init_ndb( @version )

      @header = new_segment('ISA')
      @trailer = new_segment('IEA')
      #@header.cS001.d0001 = par[:charset]

      @header.dI06 = par[:sender] unless par[:sender].nil?
      @header.dI07 = par[:recipient] unless par[:recip].nil?

      @header.dI10 = par[:interchange_control_standards_id]
      @header.dI11 = par[:version]
      @header.dI12 = par[:interchange_control_reference]
      @header.dI13 = par[:acknowledgment_request]
      @header.dI14 = par[:test_indicator]
      @header.dI15 = @ce_sep

      t = Time.now
      @header.dI08 = t.strftime('%y%m%d')
      @header.dI09 = t.strftime('%H%M')

      @trailer.dI16 = 0
    end

    #
    # Reads EDI data from given stream (default: $stdin),
    # parses it and returns an Interchange object
    #
    def Interchange.parse( hnd=$stdin, auto_validate=true )
      builder = StreamingBuilder.new( auto_validate )
      builder.go( hnd )
      builder.interchange
    end

    #
    # Read +maxlen+ bytes from $stdin (default) or from given stream
    # (ANSI data expected), and peek into first segment (ISA).
    #
    # Returns an empty Interchange object with a properly header filled.
    #
    # Intended use: 
    #   Efficient routing by reading just ISA data: sender/recipient/ref/test
    #
    def Interchange.peek(hnd=$stdin, params={}) # Handle to input stream
      builder = StreamingBuilder.new( false )
      if params[:deep_peek]
        def builder.on_segment( s, tag )
        end
      else
        def builder.on_gs( s )
          throw :done
        end
        def builder.on_st( s, tag )
          throw :done  # FIXME: Redundant, since GS must occur?
        end
      end
      builder.go( hnd )
      builder.interchange
    end


    # This method modifies the behaviour of method to_s():
    # ANSI X12 interchanges and their components are turned into strings
    # either "verbatim" (default) or in some more readable way.
    # This method corresponds to a parameter with the same name 
    # that may be set at creation time.
    #
    # Valid values:
    #
    # :linebreak :: One-segment-per-line representation
    # :indented ::  Like :linebreak but with additional indentation 
    #               (2 blanks per hierarchy level).
    # :verbatim ::  No linebreak (default), ISO compliant
    # 
    def output_mode=( value )
      super( value )
      @e_linebreak = @e_indent = ''
      case value
      when :verbatim
        # NOP (default)
      when :linebreak
        @e_linebreak = "\n"
      when :indented
        @e_linebreak = "\n"
        @e_indent = '  '
      else
        raise "Unknown output mode '#{value}'. Supported modes: :linebreak, :indented, :verbatim (default)"
      end
    end


    # Add a MsgGroup (Functional Group) object to the interchange.
    #
    # GE counter is automatically incremented.

    def add( obj, auto_validate=true )
      super
      @trailer.dI16 += 1 #if @trailer
      # FIXME: Warn/fail if ST id is not unique (at validation?)
    end


    # Derive an empty message group from this interchange context.
    # Parameters may be passed hash-like. See MsgGroup.new for details
    #
    def new_msggroup(params={}) # to be completed ...
      @groups_created += 1
      MsgGroup.new(self, params)
    end


    # Derive an empty segment from this interchange context
    # For internal use only (header / trailer segment generation)
    #
    def new_segment(tag) # :nodoc:
      Segment.new(self, tag)
    end


    # Parse a message group (when group mode detected)
    # Internal use only.

    def parse_msggroup(list) # :nodoc:
      MsgGroup.parse(self, list)
    end


    # Parse a segment (header or trailer expected)
    # Internal use only.

    def parse_segment(buf, tag) # :nodoc:
      Segment.parse(self, buf, tag)
    end


    # Returns the string representation of the interchange.
    #
    # Type conversion and escaping are provided.
    # See +output_mode+ for modifiers. 

    def to_s
      s = ''
      postfix = '' << seg_term << @e_linebreak
      s << super( postfix )
    end


    # Yields a readable, properly indented list of all contained objects,
    # including the empty ones. This may be a very long string!

    def inspect( indent='', symlist=[] )
      # symlist << :una
      super
    end


    # Returns the number of warnings found and logs them

    def validate( err_count=0 )
      if (h=self.size) != (t=@trailer.dI16)
        EDI::logger.warn "Counter IEA, DE I16 does not match content: #{t} vs. #{h}"
        EDI::logger.warn "classes: #{t.class} vs. #{h.class}"
        err_count += 1
      end
      #if (h=@header.cS001.d0001) != @charset
      #  warn "Charset UNZ/UIZ, S001/0001 mismatch: #{h} vs. #@charset"
      #  err_count += 1
      #end
      if (h=@header.dI11) != @version
        EDI::logger.warn "Syntax version number ISA, ISA12 mismatch: #{h} vs. #@version"
        err_count += 1
      end
      check_consistencies

      if (t=@trailer.dI12) != (h=@header.dI12)
        EDI::logger.warn "ISA/IEA mismatch in refno (I12): #{h} vs. #{t}"
        err_count += 1
      end

      # FIXME: Check if messages/groups are uniquely numbered

      super
    end

    private

    #
    # Private method: Loads EDI norm database
    #
    def init_ndb(d0002, d0076 = nil)
      @basedata = EDI::Dir::Directory.create(root.syntax,
                                             :ISA12   => @version )
    end

    #
    # Private method: Check if basic UNB elements are set properly
    #
    def check_consistencies
      # FIXME - @syntax should be completely avoided, use sub-module name
      if not ['A'].include?(@syntax) # More anticipated here
        raise "#{@syntax} - syntax not supported!"
      end
=begin
      case @version
      when 1
        if @charset != 'UNOA'
          raise "Syntax version 1 permits only charset UNOA!"
        end
      when 2
        if not @charset =~ /UNO[AB]/
          raise "Syntax version 2 permits only charsets UNOA, UNOB!"
        end
      when 3
        if not @charset =~ /UNO[A-F]/
          raise "Syntax version 3 permits only charsets UNOA...UNOF!"
        end
      when 4
        # A,B: ISO 646 subsets, C-K: ISO-8859-x, X: ISO 2022, Y: ISO 10646-1
        if not @charset =~ /UNO[A-KXY]/
          raise "Syntax version 4 permits only charsets UNOA...UNOZ!"
        end
      else
        raise "#{@version} - no such syntax version!"
      end
=end
      @illegal_charset_pattern = Illegal_Charset_Patterns['@version']
      # Add more rules ...
    end

  end


  #########################################################################
  #
  # Class EDI::A::MsgGroup
  #
  # This class implements a group of business documents of the same type
  # Its header unites features from UNB as well as from UNH.
  #
  class MsgGroup < EDI::MsgGroup

    attr_reader :messages_created

    @@msggroup_defaults = {
      :msg_type => '837', :func_ident => 'HC',
      :version => '004', :release => '01',
      :sub_version => '0', :assigned_code => nil # e.g. 'X098A1'
    }
    @@msggroup_default_keys = @@msggroup_defaults.keys
    
    # Creates an empty ANSI X12 message group (functional group)
    # Don't use directly - use +new_msggroup+ of class Interchange instead!
    #
    # == First parameter
    #
    # This is always the parent object (an interchange object).
    # Use method +new_msggroup+ in the corresponding object instead
    # of creating message groups unattended - the parent reference
    # will be accounted for automatically.
    #
    # == Second parameter
    # 
    # List of supported hash keys:
    #
    # === GS presets for your convenience, may be changed later
    #
    # :msg_type ::    (for ST), default = '837'
    # :func_ident ::  Sets DE 479, default = 'HC'
    # :version ::     Merges into DE 480, default = '004'
    # :release ::     Merges into DE 480, default = '01'
    # :sub_version :: Merges into DE 480, default = '0'
    #
    # === Optional parameters, required depending upon use case
    #
    # :assigned_code ::   Merges into DE 480 (subset), default = nil
    # :sender ::          Presets DE 142, default = nil
    # :recipient ::       Presets DE 124, default = nil
    # :group_reference :: Presets DE 28, auto-incremented
    #
    # == Notes
    #
    # * The functional group control number in GS and GE (28) is set 
    #   automatically to a number that is unique for this message group and
    #   the running process (auto-increment).
    # * The counter in GE (97) is set automatically to the number
    #   of included messages.
    # * The trailer segment (GE) is generated automatically.
    # * Whenever possible, <b>avoid writing to the counters of
    #   the message header or trailer segments</b>!

    def initialize( p, user_par={} )
      super( p, user_par )
      @messages_created = 0
 
      if user_par.is_a? Hash
        preset_group( user_par )
        @header = new_segment('GS')
        @trailer = new_segment('GE')
        @trailer.d97 = 0
        @header.d479 = @func_ident # @name
        @header.d455 = @resp_agency
        @header.d480 = @version+@release+@sub_version
        #cde.d0054 = @release
        #cde.d0057 = @subset

        @header.d142 = user_par[:sender] || root.header.dI06
        @header.d124 = user_par[:recipient] || root.header.dI07
        @header.d28  = user_par[:group_reference] || p.groups_created
        #      @trailer.d28 = @header.d28
	@header.d455 = 'X'

        t = Time.now
        @header.d373 = t.strftime('%Y%m%d')
        @header.d337 = t.strftime("%H%M")

      elsif user_par.is_a? Segment

        @header = user_par
        raise "GS expected, #{@header.name} found!" if @header.name != 'GS'
        @header.parent = self
        @header.root = self.root

        # Assign a temporary GS segment
        de_sep = root.de_sep
        @trailer = Segment.parse(root, 'GE' << de_sep << '0' << de_sep << '0')

        @name = @header.d479 # FIXME: HC??
        s480 = @header.d480
        @version = s480[0,3]
        @release = s480[3,2]
        @sub_version = s480[5,1]
        # @subset = s008.d0057
        @resp_agency = @header.d455
      else
        raise "First parameter: Illegal type!"
      end

    end


    # Internal use only!

    def preset_group(user_par) # :nodoc:
      if (illegal_keys = user_par.keys - @@msggroup_default_keys) != []
        msg = "Illegal parameter(s) found: #{illegal_keys.join(', ')}\n"
        msg += "Valid param keys (symbols): #{@@msggroup_default_keys.join(', ')}"
        raise ArgumentError, msg
      end
      par = @@msggroup_defaults.merge( user_par )

      @name = par[:msg_type]
      @func_ident = par[:func_ident]
      @version = par[:version]
      @release = par[:release]
      @sub_version = par[:sub_version]
      @resp_agency = par[:resp_agency]
      # @subset = par[:assigned_code]
      # FIXME: Eliminate use of @version, @release, @resp_agency, @subset
      #        They get outdated whenever their UNG counterparts are changed
      #        Try to keep @name updated, or pass it a generic name
    end


    def MsgGroup.parse (p, segment_list) # List of segments
      grp = p.new_msggroup(:msg_type => 'DUMMY')

      # We now expect a sequence of segments that comprises one group, 
      # starting with ST and ending with SE, and with messages in between.
      # We process the ST/SE envelope separately, then work on the content.

      header  = grp.parse_segment(segment_list.shift, 'GS')
      trailer = grp.parse_segment(segment_list.pop,   'GE')

      init_seg = Regexp.new('^ST')
      exit_seg = Regexp.new('^SE')
      
      while segbuf = segment_list.shift
        case segbuf

        when init_seg
          sub_list = Array.new
          sub_list.push segbuf

        when exit_seg
          sub_list.push segbuf	
          grp.add grp.parse_message(sub_list)

        else
          sub_list.push segbuf	
        end
      end

      grp.header  = header
      grp.trailer = trailer
      grp
    end
    

    def new_message(params={})
      @messages_created += 1
      Message.new(self, params)
    end

    def new_segment(tag) # :nodoc:
      Segment.new(self, tag)
    end


    def parse_message(list) # :nodoc:
      Message.parse(self, list)
    end

    def parse_segment(buf, tag) # :nodoc:
      Segment.parse(self, buf, tag)
    end


    def add( msg, auto_validate=true )
      super( msg )
      @trailer.d97 = @trailer.d97.to_i if @trailer.d97.is_a? String
      @trailer.d97 += 1
    end


    def to_s
      postfix = '' << root.seg_term << root.e_linebreak
      super( postfix )
    end


    def validate( err_count=0 )
      # Consistency checks
      if (a=@trailer.d97) != (b=self.size)
        EDI::logger.warn "GE: DE 97 (#{a}) does not match number of messages (#{b})"
        err_count += 1
      end
      a, b = @trailer.d28, @header.d28
      if a != b
        EDI::logger.warn "GE: DE 28 (#{a}) does not match reference in GS (#{b})"
        err_count += 1
      end

      # FIXME: Check if messages are uniquely numbered

      super
    end

  end


  #########################################################################
  #
  # Class EDI::A::Message
  #
  # This class implements a single business document according to ANSI X12

  class Message < EDI::Message
    #    private_class_method :new

    @@message_defaults = {
      :msg_type => 837, :version=> '004010', :ref_no => nil
    }
    @@message_default_keys = @@message_defaults.keys

    # Creates an empty ANSI X12 message.
    #
    # Don't use directly - call method +new_message+ of class Interchange 
    # or MsgGroup instead!
    #
    # == First parameter
    #
    # This is always the parent object, either a message group
    # or an interchange object.
    # Use method +new_message+ in the corresponding object instead
    # of creating messages unattended, and the parent reference
    # will be accounted for automatically.
    #
    # == Second parameter, case "Hash"
    # 
    # List of supported hash keys:
    #
    # === Essentials, should not be changed later
    #
    # :msg_type ::    Sets DE 143, default = '837'
    # :ref_no ::      Sets DE 329, default is a built-in counter
    # :version ::     Sets S009.0052, default = 'D'
    # :release ::     Sets S009.0054, default = '96A'
    # :resp_agency :: Sets S009.0051, default = 'UN'
    #
    # === Optional parameters, required depending upon use case
    #
    # :assigned_code :: Sets S009.0057 (subset), default = nil
    #
    # == Second parameter, case "Segment"
    #
    # This mode is only used internally when parsing data.
    #
    # == Notes
    #
    # * The counter in ST (329) is set automatically to a
    #   number that is unique for the running process.
    # * The trailer segment (SE) is generated automatically.
    # * Whenever possible, <b>avoid write access to the 
    #   message header or trailer segments</b>!

    def initialize( p, user_par={} )
      super( p, user_par )

      # First param is either a hash or segment ST
      # - If Hash:    Build ST from given parameters
      # - If Segment: Extract some crucial parameters
      if user_par.is_a? Hash
        preset_msg( user_par )
        par = {
	  :GS08 => @version
          # :d0065 => @msg_type, :d0052=> @version, :d0054=> @release, 
          # :d0051 => @resp_agency, :d0057 => @subset, :is_iedi => root.is_iedi?
        }
        @maindata = EDI::Dir::Directory.create(root.syntax, par )
 
        @header = new_segment('ST')
        @trailer = new_segment('SE')
        @header.d143 = @name
        @header.d329 = user_par[:ref_no].nil? ? p.messages_created : user_par[:ref_no]
	@trailer.d329 = @header.d329

=begin
        cde = @header.cS009
        cde.d0065 = @name
        cde.d0052 = @version
        cde.d0054 = @release
        cde.d0051 = @resp_agency
        cde.d0057 = @subset
=end

      elsif user_par.is_a? Segment
        @header = user_par
        raise "ST expected, #{@header.name} found!" if @header.name != 'ST'
        @header.parent = self
        @header.root = self.root
        @trailer = Segment.new(root, 'SE') # temporary
        #s009 = @header.cS009
        #@name = s009.d0065
        @version = p.header.d480 # GS08
        #@release = s009.d0054
        #@resp_agency = s009.d0051
        #@subset = s009.d0057
        par = {
	  :GS08 => @version,
	  :ST01 => @header.d143
         # :d0065 => @name, :d0052=> @version, :d0054=> @release, 
         # :d0051 => @resp_agency, :d0057 => @subset, :is_iedi => root.is_iedi?
        }
        @maindata = EDI::Dir::Directory.create(root.syntax, par )
      else
        raise "First parameter: Illegal type!"
      end

      @trailer.d96 = 2 if @trailer  # Just ST and SE so far
    end

    #
    # Derive a new segment with the given name from this message context.
    # The call will fail if the message name is unknown to this message's
    # Directory (not in EDMD).
    #
    # == Example:
    #    seg = msg.new_segment( 'BHT' )
    #    seg.d353 = '00'
    #    # etc.
    #    msg.add seg
    #
    def new_segment( tag )
      Segment.new(self, tag)
    end

    # Internal use only!

    def parse_segment(buf, tag=nil) # :nodoc:
      Segment.parse(self, buf, tag)
    end

    # Internal use only!

    def preset_msg(user_par) # :nodoc:
      if (illegal_keys = user_par.keys - @@message_default_keys) != []
        msg = "Illegal parameter(s) found: #{illegal_keys.join(', ')}\n"
        msg += "Valid param keys (symbols): #{@@message_default_keys.join(', ')}"
        raise ArgumentError, msg
      end

      par = @@message_defaults.merge( user_par )

      @name = par[:msg_type]
      @version = par[:version]
      @release = par[:release]
      @resp_agency = par[:resp_agency]
      @subset = par[:assigned_code]
      # FIXME: Eliminate use of @version, @release, @resp_agency, @subset
      #        They get outdated whenever their UNH counterparts are changed
      #        Try to keep @name updated, or pass it a generic name
    end


    # Returns a new Message object that contains the data of the
    # strings passed in the +segment_list+ array. Uses the context
    # of the given +parent+ object and configures message as a child.

    def Message.parse (parent, segment_list)

      h, t, re_t = 'ST', 'SE', /^SE/

      # Segments comprise a single message
      # Temporarily assign a parent, or else service segment lookup fails
      header  = parent.parse_segment(segment_list.shift, h)
      msg     = parent.new_message(header)
      trailer = msg.parse_segment( segment_list.pop, t )

      segment_list.each do |segbuf|
        seg = Segment.parse( msg, segbuf )
        if segbuf =~ re_t # FIXME: Should that case ever occur?
          msg.trailer = seg
        else
          msg.add(seg)
        end
      end
      msg.trailer = trailer
      msg
    end


    #
    # Add a previously derived segment to the end of this message (append)
    # Make sure that all mandatory elements have been supplied.
    #
    # == Notes
    #
    # * Strictly add segments in the sequence described by this message's
    #   branching diagram!
    #
    # * Adding a segment will automatically increase the corresponding
    #   counter in the message trailer.
    #
    # == Example:
    #    seg = msg.new_segment( 'BHT' )
    #    seg.d353 = 837
    #    # etc.
    #    msg.add seg
    #
    def add( seg )
      super
      @trailer.d96 = @trailer.d96.to_i if @trailer.d96.is_a? String
      @trailer.d96 += 1	# What if new segment is/remains empty??
    end


    def validate( err_count=0 )
      # Check sequence of segments against library,
      # thereby adding location information to each segment

      par = {
        :ST01 => @header.d143, # :d0052=> @version, :d0054=> @release, 
        # :d0051 => @resp_agency, :d0057 => @subset, 
        # :ISA12 => root.version, # :is_iedi => root.is_iedi?,
	:GS08 => parent.header.d480
      }
      diag = EDI::Diagram::Diagram.create( root.syntax, par )
      ni = EDI::Diagram::NodeInstance.new(diag)

      ni.seek!( @header )
      @header.update_with( ni )
      each do |seg|
        if ni.seek!(seg)
          seg.update_with( ni )
        else
          # FIXME: Do we really have to fail here, or would a "warn" suffice?
          raise "seek! failed for #{seg.name} when starting at #{ni.name}"
        end 
      end
      ni.seek!( @trailer )
      @trailer.update_with( ni )


      # Consistency checks

      if (a=@trailer.d96) != (b=self.size+2)
        EDI::logger.warn "DE 96 (#{a}) does not match number of segments (#{b})"
        err_count += 1
      end

      a, b = @trailer.d329, @header.d329
      if a != b
        EDI::logger.warn "Trailer reference (#{a}) does not match header reference (#{b})"
        err_count += 1
      end

=begin
      if parent.is_a? MsgGroup
        ung = parent.header; s008 = ung.cS008; s009 = header.cS009
        a, b = s009.d0065, ung.d0038
        if a != b
          warn "Message type (#{a}) does not match that of group (#{b})"
          err_count += 1
        end
        a, b = s009.d0052, s008.d0052
        if a != b
          warn "Message version (#{a}) does not match that of group (#{b})"
          err_count += 1
        end
        a, b = s009.d0054, s008.d0054
        if a != b
          warn "Message release (#{a}) does not match that of group (#{b})"
          err_count += 1
        end
        a, b = s009.d0051, ung.d0051
        if a != b
          warn "Message responsible agency (#{a}) does not match that of group (#{b})"
          err_count += 1
        end
        a, b = s009.d0057, s008.d0057
        if a != b
          warn "Message association assigned code (#{a}) does not match that of group (#{b})"
          err_count += 1
        end
      end
=end

      # Now check each segment
      super( err_count )
    end


    def to_s
      postfix = '' << root.seg_term << root.e_linebreak
      super( postfix )
    end

  end


  #########################################################################
  #
  # Class EDI::A::Segment
  #
  # This class implements UN/EDIFACT segments like BGM, NAD etc.,
  # including the service segments UNB, UNH ...
  #

  class Segment < EDI::Segment

    # A new segment must have a parent (usually, a message). This is the
    # first parameter. The second is a string with the desired segment tag.
    #
    # Don't create segments without their context - use Message#new_segment()
    # instead.

    def initialize(p, tag)
      super( p, tag )

      each_BCDS('s'+tag) do |entry| # FIXME: Workaround for X12 segment names
        id = entry.name
        status = entry.status

        # FIXME: Code redundancy in type detection - remove later!
        case id
        when /C\d{3}/		# Composite
          add new_CDE(id, status)
        when /I\d{2}|\d{1,4}/	# Simple DE
          add new_DE(id, status, fmt_of_DE(id))
        else			# Should never occur
          raise "Not a legal DE or CDE id: #{id}"
        end
      end
    end


    def new_CDE(id, status)
      CDE.new(self, id, status)
    end


    def new_DE(id, status, fmt)
      DE.new(self, id, status, fmt)
    end


    # Reserved for internal use

    def Segment.parse (p, buf, tag_expected=nil)
      # Buffer contains a single segment
      # obj_list = buf.split( Regexp.new('\\'+p.root.de_sep.chr) ) # FIXME: Pre-calc the regex!
      obj_list = buf.split( p.root.re_de_sep )
      tag = obj_list.shift 		  # First entry must be the segment tag

      raise "Illegal tag: #{tag}" unless tag =~ /[A-Z][A-Z0-9]{1,2}/
        if tag_expected and tag_expected != tag
          raise "Wrong segment name! Expected: #{tag_expected}, found: #{tag}"
        end

      seg = p.new_segment(tag)
      seg.each {|obj| obj.parse( obj_list.shift ) }
      seg
      # Error handling needed here if obj_list is not exhausted now!
    end


    def to_s
      s = ''
      return s if empty?

      rt = self.root

      indent = rt.e_indent * (self.level || 0)
      s << indent << name << rt.de_sep
      skip_count = 0
      each {|obj| 
        if obj.empty?
          skip_count += 1
        else
          if skip_count > 0
            s << rt.de_sep.chr * skip_count
            skip_count = 0
          end
          s << obj.to_s
          skip_count += 1
        end
      }
      s # name=='ISA' ? s.chop : s
    end


    # Some exceptional setters, required for data consistency

    # Don't change DE 0002! d0002=() raises an exception when called.
    def d0002=( value ); fail "ANSI version not modifiable!"; end

    # Setter for DE I12 in ISA & IEA (interchange control reference)
    def dI12=( value )
      return super unless self.name=~/I[SE]A/
      parent.header['I12'].first.value = value
      parent.trailer['I12'].first.value = value
    end

    # Setter for DE 28 in GS & GE (group reference)
    def d28=( value )
      return super unless self.name=~/G[SE]/
      parent.header['28'].first.value = value
      parent.trailer['28'].first.value = value
    end

    # Setter for DE 329 in ST & SE (TS control number)
    def d329=( value )
      return super unless self.name=~/S[TE]/
      parent.header['329'].first.value = value
      parent.trailer['329'].first.value = value
    end

  end


  #########################################################################
  #
  # Class EDI::A::CDE
  #
  # This class implements ANSI X12 composite data elements C001 etc.
  #
  # For internal use only.

  class CDE < EDI::CDE

    def initialize(p, name, status)
      super(p, name, status)

      each_BCDS(name) do |entry|
        id = entry.name
        status = entry.status
        # FIXME: Code redundancy in type detection - remove later!
        if id =~ /\d{1,4}/
          add new_DE(id, status, fmt_of_DE(id))
        else				# Should never occur
          raise "Not a legal DE: #{id}"
        end
      end
    end

    def new_DE(id, status, fmt)
      DE.new(self, id, status, fmt)
    end


    def parse (buf)	# Buffer contains content of a single CDE
      return nil unless buf
      obj_list = buf.split( root.re_ce_sep )
      each {|obj| obj.parse( obj_list.shift ) }
      # FIXME: Error handling needed here if obj_list is not exhausted now!
    end


    def to_s
      rt = self.root
      s = ''; skip_count = 0
      ce_sep = rt.ce_sep.chr
      each {|de| 
        if de.empty?
          skip_count += 1
        else
          if skip_count > 0
            s << ce_sep * skip_count
            skip_count = 0
          end
          s << de.to_s
          skip_count += 1
        end
      }
      s
    end

  end


  #########################################################################
  #
  # Class EDI::A::DE
  #
  # This class implements ANSI X12 data elements 1004, 2005 etc.,
  # including the service DEs I01, ..., I16
  #
  # For internal use only.

  class DE < EDI::DE

    def initialize( p, name, status, fmt )
      super( p, name, status, fmt )
      raise "Illegal DE name: #{name}" unless name =~ /\d{1,4}/
        # check if supported format syntax
        # check if supported status value
    end


    # Generate the DE content from the given string representation.
    # +buf+ contains a single DE string

    def parse( buf, already_escaped=false ) # 2nd par is a dummy for X12
      return nil unless buf
      return @value = nil if buf.empty?
      self.value = buf
#      if format[0] == ?n
#        # Select appropriate Numeric, FIXME: Also match exponents!
#        self.value = @value=~/\d+\.\d+/ ? @value.to_f : @value.to_i
#      end
      @value
    end


    def to_s( no_escape=false ) # Parameter is a dummy for X12
      location = "DE #{parent.name}/#{@name}"
      if @format =~ /^(AN|B|DT|ID|N\d+?|R|TM|XX) (\d+)\/(\d+)$/
        _type, min_size, max_size = $1, $2.to_i, $3.to_i
      else
	raise "#{location}: Illegal format #{format}"
      end
      case _type
      when 'AN', 'ID', 'DT', 'TM'
	if empty? then return( required?  ? ' '* min_size : '' ) end
	str = @value.to_s; fixlen = str.length
	return @value.to_s[0,max_size] if fixlen > max_size # Truncate if too long
        fixlen < min_size ? str + ' ' * (min_size - fixlen) : str # Right-pad with blanks if too short
      when /N(\d+)/
	x = @value.to_f
	$1.to_i.times { x *= 10 }
	str = (x+0.0001).to_i.to_s; fixlen = str.length
        raise "#{location}: '#{value}' too long (#{fixlen}) for fmt #{format}" if fixlen > max_size
        return '0' * (min_size - fixlen) + str if fixlen < min_size # Left-pad with zeroes
	str
      when 'R'
	@value.to_s
	# FIXME: Add length control!
      when 'XX'
	# @value.to_s
	@value
      else
        raise "#{location}: Format #{format} not supported"
      end
    end

    # The proper method to assign values to a DE.
    # The passed value must respond to +to_i+ .

    def value=( val )
      if @format =~ /^(AN|B|DT|ID|N\d+?|R|TM|XX) (\d+)\/(\d+)$/
        _type, min_size, max_size = $1, $2.to_i, $3.to_i
      else
	location = "DE #{parent.name}/#{@name}"
	raise "#{location}: Illegal format #{format}"
      end

      case _type
      when 'AN', 'ID', 'DT', 'TM'
	# super
      when 'R'
	val = val.to_f
      when /N(\d+)/
	if $1==0
	  val = val.to_i
	else
	  val = val.to_f
	  $1.to_i.times { val /= 10.0 }
	end
      when 'XX'
        # p "case XX: name, val = ", name, val
	val = val[0] if val.is_a?(String)
	# raise "#{location}: Illegal value #{val} for format XX" unless val.is_a? Fixnum
	# return super
      else
	location = "DE #{parent.name}/#{@name}"
        raise "#{location}: Format #{format} not supported"
      end
      # Suppress trailing decimal part if Integer value
      if val.is_a? Float
	ival = val.to_i
	val = ival if val == ival
      end
      EDI::logger.info "***** I15='#{val}'" if name == 'I15' && val.is_a?(String) && val.size > 1
      super
    end


    # Performs various validation checks and returns the number of
    # issues found (plus the value of +err_count+):
    #
    # - empty while mandatory?
    # - character set limitations violated?
    # - various format restrictions violated?
    #
    # Note: X12 comes with its own format definitions, so we overwrite
    #	    validate() of the base class here entirely.

    def validate( err_count=0, fmt=@format )
      location = "DE #{parent.name}/#{@name}"
      if empty?
        if required?
          EDI::logger.warn "#{location}: Empty though mandatory!"
          err_count += 1
        end
      else
        #
        # Charset check
        #
        if (pos = (value =~ root.illegal_charset_pattern)) # != nil
          EDI::logger.warn "#{location}: Illegal character: #{value[pos].chr} (#{value[pos]})"
          err_count += 1
        end
        #
        # Format check, raise error if not consistent!
        #
        if fmt =~ /^(AN|B|DT|ID|N\d|R|TM|XX) (\d+)\/(\d+)$/
          _type, min_size, max_size = $1, $2.to_i, $3.to_i
          case _type

          when 'R'
            strval = value.to_s
            re = Regexp.new('^(-)?(\d+)(\.\d+)?$')
            md = re.match strval
            if md.nil?
              raise "#{location}: '#{strval}' - not matching format #{fmt}"
              #              warn "#{strval} - not matching format #{fmt}"
#              err_count += 1
            end

            len = strval.length
            # Sign char does not go into length count:
            len -= 1 if md[1]=='-'
            # Decimal char does not go into length count:
            len -= 1 if not md[3].nil?

            # break if not required? and len == 0
           if required? or len != 0
            if len > max_size.to_i
#            if _upto.nil? and len != _size.to_i or len > _size.to_i
              EDI::logger.warn "Context in #{location}: #{_type}, #{min_size}, #{max_size}; #{md[1]}, #{md[2]}, #{md[3]}"
              EDI::logger.warn "Max length exceeded in #{location}: #{len} vs. #{max_size}"
              err_count += 1
              #            warn "  (strval was: '#{strval}')"
            end
            if md[1] =~/^0+/
              EDI::logger.warn "#{strval} contains leading zeroes"
              err_count += 1
            end
            if md[3] and md[3]=~ /.0+$/
              EDI::logger.warn "#{strval} contains trailing decimal sign/zeroes"
              err_count += 1
            end
           end

          when /N\d+/
            len = (str=value.to_s).length
	    len -= 1 if str[0]==?- # Don't count sign in length
            if len > max_size  # len < min_size is ok, would be left-padded
	      EDI::logger.warn "#{@name}: Value is '#{value}'"
              EDI::logger.warn "Length mismatch in #{location}: #{len} vs. #{min_size}/#{max_size}"
              err_count += 1
            end

          when 'AN'
            len = value.to_s.length
            if len > max_size
	      EDI::logger.warn "#{@name}: Value is '#{value}'"
              EDI::logger.warn "Length mismatch in #{location}: #{len} vs. #{min_size}/#{max_size} - content will be truncated!"
              err_count += 1
	    elsif len < min_size
	      EDI::logger.warn "#{@name}: Value is '#{value}'"
              EDI::logger.warn "Length mismatch in #{location}: #{len} vs. #{min_size}/#{max_size}  (content will be right-padded)"
              # err_count += 1
            end

          when 'ID', 'DT', 'TM'
            len = value.to_s.length
            unless len.between?( min_size, max_size )
	      EDI::logger.warn "#{@name}: Value is '#{value}'"
              EDI::logger.warn "Length mismatch in #{location}: #{len} vs. #{min_size}/#{max_size}"
              err_count += 1
            end
	  when 'XX'
	    # Currently, this case only affects I15, which is a Fixnum,
	    # but represents a character
	    if RUBY_VERSION < '1.9'
	      x_from, x_to = 1, 255
	    else
	      x_from, x_to = "\001", "\377"
	    end
            unless value.between?(x_from, x_to)
	      EDI::logger.warn "#{@name}: Value is '#{value}'"
              EDI::logger.warn "Cannot be encoded as a character!"
              err_count += 1
            end
          else
            raise "#{location}: Illegal format prefix #{_type}"
            # err_count += 1
          end

        else
          EDI::logger.warn "#{location}: Illegal format: #{fmt}!"
          err_count += 1
        end
      end
      err_count
    end
  end


  #########################################################################
  #
  # = Class StreamingParser
  #
  # == Introduction
  #
  # Turning a whole EDI interchange into an EDI::A::Interchange object
  # with method +parse+ is both convenient and memory consuming.
  # Sometimes, interchanges become just too large to keep them completely
  # in memory. 
  # The same reasoning holds for large XML documents, where there is a
  # common solution: The SAX/SAX2 API, a streaming approach. This class
  # implements the same idea for EDI data.
  #
  # Use StreamingParser instances to parse ANSI X12 data *sequentially*.
  # Sequential parsing saves main memory and is applicable to
  # arbitrarily large interchanges.
  #
  # At its core lies method +go+. It scans the input stream and
  # employs callbacks <tt>on_*</tt> which implement most of the parser tasks.
  #
  # == Syntax check
  #
  # Without your customizing the callbacks, this parser just scans
  # through the data. Only callback <tt>on_error()</tt> contains code:
  # It raises an exception telling you about the location and kind
  # of syntax error encountered.
  #
  # === Example: Syntax check
  #
  #   parser = EDI::A::StreamingParser.new
  #   parser.go( File.open 'damaged_file.x12' )
  #   --> EDI::EDISyntaxError at offset 1234, last chars = UNt+1+0
  #
  #
  # == Callbacks
  #
  # Most callbacks provided here are just empty shells. They usually receive
  # a string of interest (a segment content, i.e. everything from the segment
  # tag to and excluding the segment terminator) and also the
  # segment tag as a separate string when tags could differ.
  #
  # Overwrite them to adapt the parser to your needs!
  #
  # === Example: Counting segments
  #
  #   class MyParser < EDI::A::StreamingParser
  #     attr_reader :counters
  #
  #     def initialize
  #       @counters = Hash.new(0)
  #       super
  #     end
  #
  #     def on_segment( s, tag )
  #       @counters[tag] += 1
  #     end
  #   end
  #
  #   parser = MyParser.new
  #   parser.go( File.open 'myfile.x12' )
  #   puts "Segment tag statistics:"
  #   parser.counters.keys.sort.each do |tag|
  #     print "%03s: %4d\n" % [ tag, parser.counters[tag] ]
  #   end
  #
  # == Want to save time? Throw <tt>:done</tt> when already done!
  #
  # Most callbacks may <b>terminate further parsing</b> by throwing
  # symbol <tt>:done</tt>. This saves a lot of time e.g. if you already
  # found what you were looking for. Otherwise, parsing continues
  # until +getc+ hits +EOF+ or an error occurs.
  #
  # === Example: A simple search
  #
  #   parser = EDI::A::StreamingParser.new
  #   def parser.on_segment( s, tag ) # singleton
  #     if tag == 'CLM'
  #       puts "Interchange contains at least one segment CLM !"
  #       puts "Here is its contents: #{s}"
  #       throw :done   # Skip further parsing
  #     end
  #   end
  #   parser.go( File.open 'myfile.x12' )
    
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

    # Called when ISA encountered
    #
    def on_isa( s, tag )
    end

    # Called when IEA encountered
    #
    def on_iea( s, tag )
    end

    # Called when GS encountered
    #
    def on_gs( s )
    end

    # Called when GE encountered
    #
    def on_ge( s )
    end

    # Called when ST encountered
    #
    def on_st( s, tag )
    end

    # Called when SE encountered
    #
    def on_se( s, tag )
    end

    # Called when any other segment encountered
    #
    def on_segment( s, tag )
    end

    # This callback is usually kept empty. It is called when the parser
    # finds strings between segments or in front of or trailing an interchange.
    #
    # Strictly speaking, such strings are not permitted by the ANSI X12
    # syntax rules. However, it is quite common to put a line break
    # between segments for better readability. The default settings thus 
    # ignore such occurrences.
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
    # It reads sequentially through the given stream of octets and 
    # generates calls to the callbacks <tt>on_...</tt>
    # Parameter +hnd+ may be any object supporting method +getc+.
    #
    def go( hnd )
      state, offset, item, tag = :outside, 0, '', ''
      seg_term, de_sep, ce_sep, rep_sep = nil, nil, nil, nil
      isa_count = nil

      @path = hnd.path if hnd.respond_to? :path

      self.on_interchange_start

      catch(:done) do
        loop do
          c = hnd.getc

          case state # State machine

            # Characters outside of a segment context
          when :outside
            case c

            when nil
              break # Regular exit at EOF

            when (?A..?Z)
              unless item.empty? # Flush
                self.on_other( item )
                item = ''
              end
              item << c; tag << c
              state = :tag1

            else
              item << c
            end

            # Found first tag char, now expecting second
          when :tag1
            case c

            when (?A..?Z),(?0..?9)
              item << c; tag << c
              state = :tag2

            else # including 'nil'
              self.on_error(EDISyntaxError, offset, item, c)
            end

            # Found second tag char, now expecting optional last
          when :tag2
            case c
            when (?A..?Z),(?0..?9)
              item << c; tag << c
              if tag=='ISA'
                state = :in_isa
                isa_count = 0
              else
                state = :in_segment
              end
	    when de_sep
		item << c
                state = :in_segment
            else # including 'nil'
              self.on_error(EDISyntaxError, offset, item, c)
            end

          when :in_isa
            self.on_error(EDISyntaxError, offset, item) if c.nil?
            item << c; isa_count += 1
	    case isa_count
	    when 1;	de_sep = c
	    when 80;	rep_sep = c # FIXME: Version 5.x only
	    when 102;	ce_sep = c
	    when 103
		seg_term = c
        	dispatch_item( item , tag,
				[ce_sep, de_sep, rep_sep||' ', seg_term] )
        	item, tag = '', ''
        	state = :outside
	    end
            if isa_count > 103 # Should never occur
		EDI::logger.warn "isa_count = #{isa_count}"
		self.on_error(EDISyntaxError, offset, item, c)
            end

          when :in_segment
            case c
            when nil
              self.on_error(EDISyntaxError, offset, item)
            when seg_term
              dispatch_item( item , tag )
              item, tag = '', ''
              state = :outside
            else
              item << c
            end

          else # Should never occur...
            raise ArgumentError, "unexpected state: #{state}"
          end  
          offset += 1
        end # loop
#        self.on_error(EDISyntaxError, offset, item) unless state==:outside
      end # catch(:done)
      self.on_interchange_end
      offset
    end

    private

    # Private dispatch method to simplify the parser

    def dispatch_item( item, tag, other=nil ) # :nodoc:
      case tag
      when 'ISA'
        on_isa( item, tag, other )
      when 'IEA'
        on_iea( item, tag )
      when 'GS'
        on_gs( item )
      when 'GE'
        on_ge( item )
      when 'ST'
        on_st( item, tag )
      when 'SE'
        on_se( item, tag )
      when /[A-Z][A-Z0-9]{1,2}/
        on_segment( item, tag )
      else
        self.on_error(EDISyntaxError, offset, "Illegal tag: #{tag}")
      end
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
      @auto_validate = auto_validate
    end


    def interchange
      @ic
    end


    def on_isa( s, tag, seps ) # Expecting: "ISA*...~"
      params = { :version => s[84,5] } # '00401', '00500',
      [:ce_sep, :de_sep, :rep_sep, :seg_term].each_with_index do |sep, i|
	params[sep] = seps[i]
      end
      @ic = Interchange.new( params )
      @ic.header = Segment.parse( @ic, s )
    end

    def on_iea( s, tag )
      @ic.trailer = Segment.parse( @ic, s )
    end

    def on_gs( s )
      @curr_group = @ic.new_msggroup( @ic.parse_segment(s,'GS') )
      @curr_group.header = Segment.parse( @curr_group, s )
    end

    def on_ge( s )
      @curr_group.trailer = Segment.parse( @curr_group, s )
      @ic.add( @curr_group, @auto_validate )
    end

    def on_st( s, tag )
      seg = @ic.parse_segment(s,tag)
      @curr_msg = @curr_group.new_message( seg )
#      @curr_msg = (@curr_group || @ic).new_message( @ic.parse_segment(s,tag) )
      @curr_msg.header = Segment.parse( @curr_msg, s )
    end

    def on_se( s, tag )
      @curr_msg.trailer = Segment.parse( @curr_msg, s )
      #      puts "on_unt_uit: #@curr_msg"
      @curr_group.add( @curr_msg )
    end

    # Overwrite this method to react on segments of interest
    #
    # Note: For a skeleton Builder (just ISA/GS/ST etc), overwrite with
    # an empty method.
    #
    def on_segment( s, tag )
      @curr_msg.add @curr_msg.parse_segment( s )
      super
    end


    def on_interchange_end
      if @auto_validate
        @ic.header.validate
        @ic.trailer.validate
        # Content is already validated through @ic.add() and @curr_group.add()
      end
    end

  end # StreamingBuilder


  # Just an idea - not sure it's worth an implementation...
  #########################################################################
  #
  # = Class StreamingSkimmer
  #
  # The StreamingSkimmer works as a simplified StreamingBuilder.
  # It only skims through the service segements of an interchange and 
  # builds an interchange skeleton from them containing just the interchange,
  # group, and message level, but *not* the regular messages.
  # Thus, all messages are *empty* and not fit for validation
  # (use class StreamingBuilder to build a complete interchange).
  #
  # StreamingSkimmer lacks an implementation of callback
  # method <tt>on_segment()</tt>. The interchange skeletons it produces are 
  # thus quicky built and hace a small memory footprint.
  # Customize the class by overwriting <tt>on_segment()</tt>. 
  #

  class StreamingSkimmer < StreamingBuilder
    def on_segment( s, tag )
      # Deliberately left empty
    end
  end

end # module EDI::A
