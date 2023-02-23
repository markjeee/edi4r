# -*- encoding: iso-8859-1 -*-

require 'enumerator'
require 'logger'

BEGIN {
  require 'pathname'
# 'realpath' fails on Windows platforms!
# ENV['EDI_NDB_PATH'] = Pathname.new(__FILE__).dirname.parent.realpath + 'data'
  pdir = Pathname.new(__FILE__).dirname.parent
  ENV['EDI_NDB_PATH'] =  File.expand_path(pdir) + File::Separator + 'data'
}

require "edi4r/standards"
require "edi4r/diagrams"

=begin rdoc
:main:README
:title:edi4r

= UN/EDIFACT module

An API to parse and create UN/EDIFACT and other EDI data
* Abstract classes are maintained in this file.
* See other files in edi4r/ for specific EDI syntax standards.

$Id: edi4r.rb,v 1.6 2006/08/01 11:12:39 werntges Exp werntges $

:include: ../AuthorCopyright

== Background

We anticipate to support several EDI syntax standards with this module:

 C  Name		Description
 ===========================================================================
 A  ANSI ASC X.12	the U.S. EDI standard; a precursor of UN/EDIFACT
 E  UN/EDIFACT 		the global EDI standard under the auspices of the UNO
 G  GENCOD		an early French EDI standard, consumer goods branch
 I  SAP IDoc		not an EDI standard, but a very popular in-house format
 S  SEDAS		an early Austrian/German EDI standard, see GENCOD
 T  Tradacoms		the British EDI standard; a precursor of UN/EDIFACT
 X  XML			(DTDs / Schemas still to be supplied)

Our focus will be on UN/EDIFACT, the only global EDI standard we have
that is independent of industry branches.

Terms used will be borrowed from EDIFACT and applied to the other 
syntax standards whenever possible.

A, E, and T are technically related in that they employ a compact
data representation based on a hierarchy of separator characters.
G and S as well as I are fixed-record formats, X is a markup syntax.

== Data model

We use the EDIFACT model as the name-giving, most general model.
Other EDI standards might not support all features.

The basic unit exchanged between trading partners is the "Interchange".
An interchange consists of an envelope and content. Content is
either a sequence of messages or a sequence of message groups.
Message groups - if used - comprise a (group level) envelope and
a sequence of messages.

A message is a sequence of segments (sometimes also called records).
A segment consists of a sequence of data elements (aka. fields), 
either simple ones (DE) or composites (CDE). 
Composites are sequences of simple data elements.

Hence:

 Interchange > [ MsgGroup > ] Message > Segment > [ CDE > ] DE

Syntax related information is maintained at the top (i.e. interchange) level.
Lower-level objects like segments and DEs are aware of their syntax context
through attibute "root", even though this context originates at the 
interchange level.

Lower levels may add information. E.g. a message may add its message type,
or a segment its hierarchy level, and its segment group - depending
on the syntax standard in use.

This basic structure is always maintained, even in cases like SAP IDocs
where the Interchange level is just an abstraction.

Note that this data model describes the data as they are parsed or built,
essentially lists of lists or strings. In contrast, EDI documents
frequently publish specifications in a hierarchical way, using terms like
"segment group", "instance", "level" and alike.
Here we regard such information as metadata, or additional properties
which may or may not apply or be required.

=== Example

You can build a valid EDIFACT interchange simply by adding
messages and segments - just follow your specifications.

However, if you want this Ruby module to *validate* your result, 
the metadata are required. Similarly, in order to map from EDIFACT to
other formats, accessing inbound segments though their hierarchical
representation is much more convenient than processing them linearly.

== EDI Class hierarchy (overview)

EDI_Object::    Collection, DE
Collection::    Collection_HT, Collection_S
Collection_HT:: Interchange, MsgGroup, Message
Collection_S::  Segment, CDE
=end

# To-do list:
#   validate	- add still more functionality, e.g. codelists
#   charset	- check for valid chars in more charsets
#   NDB		- support codelists
#   (much more, including general cleanup & tuning ...)

module EDI

  @logger = Logger.new(STDERR) # Default logger
  attr_accessor :logger
  module_function :logger, :logger=

  #########################################################################
  #
  # Basic (abstract) class: Makes sure that all derived
  # EDI objects have at least following attributes:
  #
  # +parent+:: Reference to parent EDI object (a +Collection+)
  # +root+::   Reference to root   EDI object (typically an +Interchange+)
  # +name+::   The name of this instance (a +String+ object)
  #
  # Caveat:: Setters are used only internally during message construction.
  #          Avoid using them!


  class Object
    attr_accessor :parent, :root, :name

    def initialize (parent, root, name)
      @parent, @root, @name = parent, root, name
    end
  end


  #########################################################################
  #
  # Here we extend class Time by some methods that help us maximize
  # its use in some contexts like UN/EDIFACT.
  #
  # Basic idea (UN/EDIFACT example): 
  # * Use the EDIFACT qualifiers of DE 2379 in DTM directly
  #   to parse dates and to create them upon output.
  # * Use augmented Time objects as values of DE 2380 instead of strings
  #

  class EDI::Time < ::Time
    attr_accessor :format
    @@to_s_callbacks = []

    alias to_s_orig to_s

    def to_s
      return to_s_orig unless @format
      str = nil
      @@to_s_callbacks.each do |sym|
	return str if (str=self.send(sym)) # Found if not nil
      end
      raise "EDI::Time: Format '#{format}' not supported" 
    end
  end


  #########################################################################
  #
  # A simple utility class that fills a need not covered by "zlib".
  #
  # It is stripped to the essentials needed here internally.
  # Not recommended for general use! The overhead of starting 
  # "bzcat" processes all the time is considerable, binding to a library
  # similar to 'zib' for the BZIP2 format would give much better results.

  class Bzip2Reader
    attr_accessor :path

    def initialize( hnd )
      @path = hnd.path
      @pipe = IO.popen("bzcat #@path",'r' )
    end

    def read( len=0 )
      len==0 ? @pipe.read : @pipe.read( len )
    end

    def getc
      @pipe.getc # @pipe.read( 1 )
    end

    def rewind
      @pipe.close
      @pipe = IO.popen("bzcat #@path",'r' )
    end

    def close
      @pipe.close
    end
  end

  #########################################################################
  #
  # An EDI collection instance behaves like a simplified array.
  # In addition, it permits access to its elements through their names.
  # This implies that only objects with a +name+ may be stored,
  # i.e. derivatives of EDI::Object.

  class Collection < EDI::Object

    def initialize( parent, root, name )
      super
      @a = []
    end


    def root= (rt)
      super( rt )
      each {|obj| obj.root = rt }
    end

    # TO-DO: Experimental add-on
    # Inefficient, brute-force implementation - use sparingly
    def deep_clone
       Marshal.restore(Marshal.dump(self)) # TO DO: Make more efficient
#      c = Marshal.restore(Marshal.dump(self)) # TO DO: Make more efficient
#      c.each {|obj| obj.parent = c }
#      c.root = c if c.is_a? EDI::Interchange
#      c
    end


    # Similar to Array#push(), but automatically setting obj's
    # parent and root to self and self's root. Returns obj.
    def add( obj )
      push obj
      obj.parent = self
      obj.root = self.root
      obj
    end

    alias append add


    def ==(obj)
      self.object_id == obj.object_id
    end

    # Delegate to array:
    #   index, each, find_all, length, size, first, last
    def index(obj);   @a.index(obj);   end
    def each(&b);     @a.each(&b);     end
    def find(&b);     @a.find(&b);     end
    def find_all(&b); @a.find_all(&b); end
    def size;         @a.size;         end
    def length;       @a.length;       end
    def first;        @a.first;        end
    def last;         @a.last;         end

    # The element reference operator [] supports two access modes:
    # Array-like:: Return indexed element when passing an integer
    # By regexp::  Return array of element(s) whose name(s) match given regexp
    # By name::    Return array of element(s) whose name(s) match given string
    def [](i)
      lookup(i)
    end


    # This implementation of +inspect()+ is very verbose in that it
    # inspects all contained objects in a recursive manner.
    #
    # indent::  String offset to use for indentation / pretty-printing
    # symlist:: Array of getter names (passed as symbols) whose values are
    #           to be listed. Note that :name is included automatically.

    def inspect( indent='', symlist=[] )
      headline = indent + self.name+': ' + symlist.map do |sym|
        "#{sym} = #{(s=send(sym)).nil? ? 'nil' : s.to_s}"
      end.join(', ') + "\n"
      if self.is_a? Collection_HT
        headline << @header.inspect(indent+'  ') if @header
        str = @a.inject( headline ){|s,obj| s << obj.inspect(indent+'  ')}
        @trailer ? str << @trailer.inspect(indent+'  ') : str
      else
        @a.inject( headline ){|s,obj| s << obj.inspect(indent+'  ')}
      end
    end


    # Returns an array of names of all included objects in proper sequence;
    # primarily for internal use.

    def names
      @a.collect {|e| e.name}
    end


    # Helper method: Turns e.g. "EDI::E::Interchange" into "Interchange".
    # For internal use only!

    def normalized_class_name # :nodoc:
      if self.class.to_s !~ /^(\w*::)?(\w::)(\w+)?$/
        raise "Cannot normalize class name: #{self.class.to_s}"
      end
      $3
    end


    private

    # push: Similar to Array#push, except that it requires objects
    #       with getter :name
    #       Low-level method, avoid. Use "add" instead.

    def push( obj )
      raise TypeError unless obj.is_a? EDI::Object # obj.respond_to? :name
      @a << obj
    end


    alias << push


    def lookup(i)
      if i.is_a?(Integer)
        @a[i]
      elsif i.is_a?(Regexp)
        @a.find_all {|x| x.name =~ i}
      else
        @a.find_all {|x| x.name == i}
      end
    end

    # Here we perform the "magic" that provides us with dynamically
    # "generated" getters and setters for just those DE and CDE
    # available in the given Collection_S instance.
    #
    # UN/EDIFACT examples:
    #  d3055, d1004=(value), cC105, a7174[1].value
    #
    # ANSI X.12 examples:
    #  d305 = "C" # in segment BPR
    #  r01  = "C" # equivalent expression, 01 indicating the first DE

    def method_missing(sym, *par)
      if sym.id2name =~ /^([acdrs])(\w+)(=)?/
        rc = $1=='r' ? lookup($2.to_i - 1) : lookup($2)
        if rc.is_a? Array
          if rc.size==1
            rc = rc.first
          elsif rc.size==0
            return super
          end
        end
        if $3
          # Setter
          raise TypeError, "Can't assign to array #$2" if rc.is_a? Array
          raise TypeError, "Can only assign to a DE value" unless rc.respond_to?(:value) # if $1 != 'd'
          rc.value = par[0]
        else
          # Getter
          return rc.value if rc.is_a? DE and ($1 == 'd' || $1 == 'r')
          return rc if rc.is_a? CDE      and ($1 == 'c' || $1 == 'r')
          return rc if rc.is_a? Segment  and $1 == 's'
          err_msg =  "Method prefix '#$1' not matching result '#{rc.class}'!"
          raise TypeError, err_msg unless rc.is_a? Array
          # Don't let whole DEs be overwritten - enforce usage of "value":
          rc.freeze
          return rc if $1 == 'a'
          raise TypeError,"Array found - use 'a#$2[i]' to access component i"
        end
      else
        super
      end
    end

  end


  #########################################################################
  #
  # A collection with header and trailer, common to Interchange, MsgGroup, 
  # and Message. Typically, header and trailer are Segment instances.
  #
  class Collection_HT < Collection
    attr_accessor :header, :trailer # make private or protected?

    def root= (rt)
      super( rt )
      @header.root = rt if @header
      @trailer.root = rt if @trailer
    end


    # Experimental: Ignore content of header / trailer,
    # regard object as empty when nothing "add"ed to it.

    def empty?
      @a.empty?
    end


    def validate( err_count=0 )
      err_count += @header.validate if @header
      err_count += @trailer.validate if @trailer
      each {|obj| err_count += obj.validate}
      err_count
    end


    def to_s( postfix='' )
      s = @header ? @header.to_s + postfix : ''
      each {|obj| s << (obj.is_a?(Segment) ? obj.to_s+postfix : obj.to_s)}
      s << @trailer.to_s+postfix if @trailer
      s
    end

  end


  #########################################################################
  #
  # A "segment-like" collection, base class of Segment and CDE
  #
  class Collection_S < Collection
    attr_accessor :status, :rep, :maxrep


    def initialize(parent, name, status=nil)
      @status = status
      super( parent, parent.root, name)
    end


    def validate( err_count=0 )
      location = "#{parent.name} - #{@name}"
      if empty?
        if required?
          EDI::logger.warn "#{location}: Empty though mandatory!"
          err_count += 1
        end
      else
        if rep && maxrep && rep > maxrep
          EDI::logger.warn "#{location}: Too often repeated: #{rep} > #{maxrep}!"
          err_count += 1
        end
        each {|obj| err_count += obj.validate}
      end
      err_count
    end


    def fmt_of_DE(id) # :nodoc:
      @parent.fmt_of_DE(id)
    end


    def each_BCDS(id, &b) # :nodoc:
      @parent.each_BCDS(id, &b)
    end


    # Returns +true+ if all contained elements are empty.

    def empty?
      empty = true
      each {|obj| empty &= obj.empty? } # DE or CDE
      empty
    end


    # Returns +true+ if this segment or CDE is mandatory / required
    # according to its defining "Diagram".

    def required?
      @status == 'M' or @status == 'R'
    end


    def inspect( indent='', symlist=[] )
      symlist += [:status, :rep, :maxrep]
      super
    end

  end


  #########################################################################
  #
  # Base class of all interchanges
  #
  class Interchange < Collection_HT

    attr_accessor :output_mode
    attr_reader :syntax, :version
    attr_reader :illegal_charset_pattern

    # Abstract class - don't instantiate directly
    #
    def initialize( user_par=nil )
      super( nil, self, 'Interchange' )
      @illegal_charset_pattern = /^$/ # Default: Never match a non-empty string
      @content = nil # nil if empty, else :messages, or :groups
      EDI::logger = user_par[:logger] if user_par[:logger].is_a? Logger
    end

    # Auto-detect file content, optionally decompress, return an 
    # Interchange object of the sub-class that matches the (unzipped) content.
    #
    # This is a convenience method.
    # When you know the file contents, consider a direct call to
    # Interchange::E::parse etc.
    #
    # NOTES:
    # * Make sure to <tt>require 'zlib'</tt> when applying this method
    #   to gzipped files.
    # * BZIP2 is indirectly supported by calling "bzcat". Make sure that
    #   "bzcat" is available when applying this method to *.bz2 files.
    # * Do not pass $stdin to this method - we could not "rewind" it!

    def Interchange.parse( hnd, auto_validate=true )
      case rc=Interchange.detect( hnd )
      when 'BZ' then Interchange.parse( EDI::Bzip2Reader.new( hnd ) ) # see "peek"
      when 'GZ' then Interchange.parse( Zlib::GzipReader.new( hnd ) )
      when 'A'  then EDI::A::Interchange.parse( hnd, auto_validate )
      when 'E'  then EDI::E::Interchange.parse( hnd, auto_validate )
      when 'I'  then EDI::I::Interchange.parse( hnd, auto_validate )
      when 'S'  then EDI::S::Interchange.parse( hnd, auto_validate )
      when 'XA' then EDI::A::Interchange.parse_xml( REXML::Document.new(hnd) )
      when 'XE' then EDI::E::Interchange.parse_xml( REXML::Document.new(hnd) )
      when 'XI' then EDI::I::Interchange.parse_xml( REXML::Document.new(hnd) )
      when 'XS' then EDI::S::Interchange.parse_xml( REXML::Document.new(hnd) )
      else raise "#{rc}: Unsupported format key - don\'t know how to proceed!"
      end
    end

    # Auto-detect file content, optionally decompress, return an 
    # empty Interchange object of that sub-class with only the header filled.
    #
    # This is a convenience method.
    # When you know the file contents, consider a direct call to
    # Interchange::E::peek etc.
    #
    # NOTES: See Interchange.parse

    def Interchange.peek( hnd=$stdin, params={})
      case rc=Interchange.detect( hnd )
        # Does not exist yet!
#      when 'BZ': Interchange.peek( Zlib::Bzip2Reader.new( hnd ) )
        # Temporary substitute, Unix/Linux only, low performance:
      when 'BZ' then Interchange.peek( EDI::Bzip2Reader.new( hnd ), params )

      when 'GZ' then Interchange.peek( Zlib::GzipReader.new( hnd ), params )
      when 'A'  then EDI::A::Interchange.peek( hnd, params )
      when 'E'  then EDI::E::Interchange.peek( hnd, params )
      when 'I'  then EDI::I::Interchange.peek( hnd )
      when 'S'  then EDI::S::Interchange.peek( hnd )
      when 'XA' then EDI::A::Interchange.peek_xml( REXML::Document.new(hnd) )
      when 'XE' then EDI::E::Interchange.peek_xml( REXML::Document.new(hnd) )
      when 'XI' then EDI::I::Interchange.peek_xml( REXML::Document.new(hnd) )
      when 'XS' then EDI::S::Interchange.peek_xml( REXML::Document.new(hnd) )
      else raise "#{rc}: Unsupported format key - don\'t know how to proceed!"
      end
    end

    # Auto-detect the given file format & content, return format key
    #
    # Convenience method, intended for internal use only
    # 
    def Interchange.detect( hnd ) # :nodoc:
      buf = hnd.read( 256 )
      #
      # NOTE: "rewind" fails when applied to $stdin!
      # If you really need to read from $stdin, call Interchange::E::parse()
      # and Interchange::E::peek() etc. directly to bypass auto-detection
      hnd.rewind
      
      re  = /(<\?xml.*?)?DOCTYPE\s+Interchange.*?\<Interchange\s+.*?standard\_key\s*=\s*(['"])(.)\2/m
      case buf
      when /^(UNA......)?\r?\n?U[IN]B.UNO[A-Z].[1-4]/ then 'E'  # UN/EDIFACT
      when /^ISA.{67}\d{6}.\d{4}/ then 'A'  # ANSI X.12
      when /^EDI_DC/ then 'I'  # SAP IDoc
      when /^00/ then 'S'      # SEDAS
      when re then 'X'+$3      # XML, Doctype = Interchange, syntax standard key (E, I, ...) postfix
      when /^\037\213/ then 'GZ' # gzip
      when /^\037\235/ then 'Z'  # compress
      when /^\037\036/ then 'z'  # pack
      when /^BZh[0-\377]/ then  'BZ' # bzip2
      else raise "?? (stream starts with: #{buf[0..15]})"
      end
    end


    def fmt_of_DE(id) # :nodoc:
      de = @basedata.de(id)
      de.nil? ? nil : de.format
    end


    def each_BCDS(id, &b) # :nodoc:
      begin
        @basedata.each_BCDS(id, &b )
      rescue EDILookupError # NoMethodError
        raise "Lookup failure for BCDS entry id '#{id}'"
      end
    end


    # Add either Message objects or MsgGroup objects to an interchange;
    # mixing both types raises a TypeError.

    def add( obj, auto_validate=true )
      err_msg = "Added object must also be a "
      if obj.is_a? Message
        @content = :messages unless @content
        raise TypeError, err_msg+"'Message'" if @content != :messages
      elsif obj.is_a? MsgGroup
        @content = :groups unless @content
        raise TypeError, err_msg+"'MsgGroup'" if @content != :groups
      else
	raise TypeError, "Only Message or MsgGroup allowed here"
      end
      obj.validate if auto_validate
      super( obj )
    end

  end


  #########################################################################
  #
  # A "MsgGroup" is a special "Collection with header and trailer"
  # It collects "Message" objects and is only rarely used.


  class MsgGroup < Collection_HT

    def initialize(p, user_par = nil)
      super(p, p.root, 'MsgGroup')
      # ...
    end


    def fmt_of_DE(id) # :nodoc:
      @parent.fmt_of_DE(id)
    end


    def each_BCDS(id, &b) # :nodoc:
      @parent.each_BCDS(id, &b)
    end

    # Add only Message objects to a message group!

    def add (msg)
      raise "Only Messages allowed here" unless msg.is_a? Message
      super
    end

  end


  #########################################################################
  #
  # A "Message" is a special "Collection with header and trailer"
  # It collects "Segment" objects.

  class Message < Collection_HT

#    @@msgCounter = 1

    def initialize( p, user_par=nil )
      super(p, p.root, 'Message')
    end


    def fmt_of_DE(id) # :nodoc:
      de = @maindata.de(id)
      return @parent.fmt_of_DE(id) if de.nil?
      de.format
    end


    def each_BCDS(id, &b) # :nodoc:
      begin
        @maindata.each_BCDS(id, &b )
      rescue EDILookupError
        @parent.each_BCDS(id, &b)
      end
    end


    # Add only Segment objects to a message!

    def add (seg)
      raise "Only Segments allowed here" unless seg.is_a? Segment
      super
    end

  end


  #########################################################################
  #
  # A "Segment" is a special Collection of type "S" (segment-like),
  # similar to "CDE". Special Segment attributes are:
  # +sg_name+:: The name of its segment group (optional)
  # +level+::   The segment's hierarchy level, an integer


  class Segment < Collection_S

    attr_reader :sg_name, :level

    # Returns true if segment is a TNode (i.e. a trigger segment).
    # Note that only TNodes may have descendants.

    def is_tnode?
      @tnode
    end

    # Returns array of all segments that have the current segment
    # as ancestor.

    def descendants
      self['descendant::*']
    end

    # Returns array of all segments with the current segment
    # as ancestor, including the current segment.
    # For trigger segments, this method returns all segments
    # of one instance of the corresponding segment group.

    def descendants_and_self
      self['descendant-or-self::*']
    end

    # Returns all child elements of the current segment.

    def children
      self['child::*']
    end

    # Returns the current segment and all of its child elements.
    # Useful e.g. to deal with one instance of a segment group
    # without traversing included segment groups.

    def children_and_self
      self['child-or-self::*']
    end


    # Access by XPath expression (support is very limited currently)
    # or by name of the dependent component. Pass them as strings.
    #
    # Used internally - try to avoid at user level!
    # Currently supported XPath expressions:
    #
    # - descendant::*
    # - descendant-or-self::*
    # - child::*
    # - child-or-self::*

    def []( xpath_expr )
      return super( xpath_expr ) if xpath_expr.is_a? Integer

      msg_unsupported = "Unsupported XPath expression: #{xpath_expr}" 

      case xpath_expr

      when /\A(descendant|child)(-or-self)?::(.*)/
        return xpath_matches($1, $2, $3, msg_unsupported)

        # Currently no real path, no predicate available supported
      when /\//, /\[/, /\]/
        raise IndexError, msg_unsupported

      when /child::(\w+)/ # ignore & accept default axis "child"
        return super( $1 )

      when /::/ # No other axes supported for now
        raise IndexError, msg_unsupported

      else # assume simple element name
        return super( xpath_expr )
      end
    end


    def inspect( indent='', symlist=[] )
      symlist += [:sg_name, :level]
      super
    end


    # Update attributes with information from a corresponding node instance

    def update_with( ni ) # :nodoc:
      return nil if ni.name != @name # Names must match; consider a raise!
      @status, @maxrep, @sg_name, @rep, @index, @level, @tnode = ni.status,\
      ni.maxrep, ni.sg_name, ni.inst_cnt, ni.index, ni.level, ni.is_tnode?
      self
    end

    private 

    def add (obj)
      raise "Only DE or CDE allowed here" unless obj.is_a? DE or obj.is_a? CDE
      super( obj )
    end

    def xpath_matches( axis, or_self, element, msg_unsupported )
      raise IndexError, msg_unsupported if element != '*'
      results = []
      results << self if or_self
      child_mode = (axis=='child')
      return results unless self.is_tnode?
      
      # Now add all segments in self's "tail"
      msg = parent
      index = msg.index(self)
      raise IndexError, "#{name} not found in own message?!" unless index
      loop do
        index += 1
        seg = msg[index]
	break if seg.nil?
        next  if child_mode and seg.level > level+1 # other descendants
        break if seg.level <= level
        results << seg
      end
      results
    end
  end


  #########################################################################
  #
  # Composite data element, primarily used in the EDIFACT context.
  # A "CDE" is a special Collection of type "S" (segment-like),
  # similar to "Segment".
  #
  class CDE < Collection_S

    private

    # Add a DE 

    def add( obj )
      raise "Only DE allowed here" unless obj.is_a? DE
      super
    end

  end

  #########################################################################
  #
  # A basic data element. Its content is accessible through methods +value+
  # and <tt>value=</tt>. Allowed contents is described by attribute +format+.
  #
  # Note that values are usually Strings, or Numerics when the format indicates
  # a numeric value. Other objects are conceivable, as long as they
  # maintain a reasonable +to_s+ for their representation.
  #
  # The external representation of the (abstract) value may further depend on 
  # rules of the unterlying EDI standard. E.g., UN/EDIFACT comes with a set
  # of reserved characters and an escaping mechanism.

  class DE < EDI::Object
    attr_accessor :value
    attr_reader :format, :status

    def initialize( p, name, status, fmt )
      @parent, @root, @name, @format, @status = p, p.root, name, fmt, status
      if fmt.nil? || status.nil?
        location = "DE #{parent.name}/#{@name}"
        raise "#{location}: 'nil' is not an allowed format." if fmt.nil?
        raise "#{location}: 'nil' is not an allowed status." if status.nil?
      end
      @value = nil
    end


    def to_s
      str = self.value
      return str if str.is_a? String
      str = str.to_s; len = str.length
      return str unless format =~ /n(\d+)/ && len != (fixlen=$1.to_i)
      location = "DE #{parent.name}/#{@name}"
      raise "#{location}: Too long (#{l}) for fmt #{format}" if len > fixlen
      '0' * (fixlen - len) + str
    end


    def inspect( indent='' )
      indent + self.name+': ' + [:value, :format, :status].map do |sym|
        "#{sym} = #{(s=send(sym)).nil? ? 'nil' : s.to_s}"
      end.join(', ') + "\n"
    end

  
    # Performs various validation checks and returns the number of
    # issues found (plus the value of +err_count+):
    #
    # - empty while mandatory?
    # - character set limitations violated?
    # - various format restrictions violated?

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
        if (pos = (value =~ root.illegal_charset_pattern))# != nil
          EDI::logger.warn "#{location}: Illegal character: #{value[pos].chr} (#{value[pos]})"
          err_count += 1
        end
        #
        # Format check, raise error if not consistent!
        #
        if fmt =~ /^(a|n|an)(..)?(\d+)$/
          _a_n_an, _upto, _size = $1, $2, $3
          case _a_n_an

          when 'n'
            strval = value.to_s
            re = Regexp.new('^(-)?(\d+)([.,]\d+)?$')
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
            # len -= 1 if (md[1]=='-' and md[3]) || (md[1] != '' and not md[3])

            # break if not required? and len == 0
           if required? or len != 0
            if len > _size.to_i
#            if _upto.nil? and len != _size.to_i or len > _size.to_i
              EDI::logger.warn "Context in #{location}: #{_a_n_an}, #{_upto}, #{_size}; #{md[1]}, #{md[2]}, #{md[3]}"
              EDI::logger.warn "Length # mismatch in #{location}: #{len} vs. #{_size}"
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

          when 'a', 'an'
#            len = value.is_a?(Numeric) ? value.to_s.length : value.length
            len = value.to_s.length
            if _upto.nil? and len != $3.to_i or len > $3.to_i
              EDI::logger.warn "Length mismatch in #{location}: #{len} vs. #{_size}"
              err_count += 1
            end
          else
            raise "#{location}: Illegal format prefix #{_a_n_an}"
            # err_count += 1
          end

        else
          EDI::logger.warn "#{location}: Illegal format: #{fmt}!"
          err_count += 1
        end
      end
      err_count
    end


    # Returns +true+ if value is not +nil+. 
    # Note that assigning an empty string to a DE makes it "not empty".
    def empty?
      @value == nil
    end


    # Returns +true+ if this is a required / mandatory segment.
    def required?
      @status == 'M' or @status == 'R'
    end

  end

end # module EDI
