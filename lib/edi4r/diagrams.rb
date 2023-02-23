# -*- encoding: iso-8859-1 -*-
# Classes related to message diagrams and validation
# for the EDI module "edi4r", a class library
# to parse and create UN/EDIFACT and other EDI data
#
# :include: ../../AuthorCopyright
#
# $Id: diagrams.rb,v 1.8 2006/05/26 16:57:37 werntges Exp werntges $
#--
# $Log: diagrams.rb,v $
# Revision 1.8  2006/05/26 16:57:37  werntges
# V 0.9.3 snapshot. RDoc added, some refactoring / renaming / cleanups
#
# Revision 1.7  2006/04/28 14:25:42  werntges
# 0.9.1 snapshot
#
# Revision 1.6  2006/03/28 22:24:58  werntges
# changed from strings to symbols as parameter keys, e.g. :d0051
#
# Revision 1.5  2006/03/22 16:57:17  werntges
# id --> object_id
#
# Revision 1.4  2004/02/19 17:34:58  heinz
# HWW: Snapshot after REMADV mapping
#
# Revision 1.3  2004/02/11 23:39:14  heinz
# HWW: IDoc support added, lots of dead code/data removed,
#      caching bug fixed, seek! augmented to accept also Regexp, ...
#
# Revision 1.2  2004/02/10 18:17:52  heinz
# HWW: Temp. check-in, before adding support for multiple standards
#
# Revision 1.1  2003/10/22 16:56:30  heinz
# Initial revision
#
#
# To-do list:
#	all	-	Just starting this...
#++
#
# Module "EDI::Diagram" bundles the classes needed to maintain
# branching diagrams, i.e. data structures that formally
# define message types.

module EDI::Diagram

  #
  # Diagram: A structure class to represent a message diagram (branching diagram)
  #
  # A Diagram is essentially
  # - a Branch object (at top-level)
  # - a description text
  # - a node dictionary (a hash that allows index-like access)
  #
  # In contrast to a simple Branch, all nodes of a Diagram object
  # are indexed (counting from 1) according to their natural sequence
  # in the EDIFACT branching diagram. Thus, access by index is available
  # for Diagram objects, but not for Branch objects.
  #

  class Diagram
    @@cache = {}
    @@caching = true
    private_class_method :new

    # A Diagram can become quite complex and memory-consuming.
    # Therefore diagrams are cached after creation, so that they
    # need to be created and maintained only once when there are several
    # messages of the same type in an interchange.
    #
    # Turns off this caching mechanism, saving memory but costing time.
    #
    def Diagram.caching_off
      @@caching = false
    end

    # Turns on caching (default setting), saving time but costing memory.
    #
    def Diagram.caching_on
      @@caching = true
    end

    # Tells if caching is currently activated (returns a boolean)
    #
    def Diagram.caching?
      @@caching
    end

    # Releases memory by flushing the cache. Needed primarily for unit tests,
    # where many if not all available diagrams are created.

    def Diagram.flush_cache
      @@cache = {}
    end

    # Creates (and caches) a new diagram. Returns reference to existing diagram
    # when already in cache.
    # std:: The syntax standard key. Currently supported:
    #       - 'E' (EDIFACT),
    #       - 'I' (SAP IDOC)
    #       - 'S' (SEDAS, experimental)
    #       - 'A' (ANSI X.12, limited)
    # params:: A hash of parameters that uniquely identify the selected diagram.
    #          Internal use only - see source code for details.
    #
    def Diagram.create( std, params )
      case std
      when 'E' # UN/EDIFACT
        par = {
          :d0051 => 'UN', 
          :d0057 => nil,
          :is_iedi => false }.update( params )
      when 'I' # SAP IDocs
        par = params
        #      raise "Not implemented yet!"
      when 'S' # SEDAS
        par = params
      when 'A' # ANSI X12
        par = params
      else
        raise "Unsupported syntax standard: #{std}"
      end

      if Diagram.caching?
        #
        # Use param set as key for caching
        #
        key = par.sort {|a,b| a.to_s <=> b.to_s}.hash
        obj = @@cache[key]
        return obj unless obj.nil?

        obj = new( std, par )
        @@cache[key] = obj # cache & return it

      else
        new( std, par )
      end
    end


    def initialize( std, par ) # :nodoc:
      case std
      when 'A' # ANSI X12
        @base_key = [par[:ST01], # msg type, e.g. 837
          par[:GS08][0,3], # version
          par[:GS08][3,2], # release, 
          par[:GS08][5,1], # sub-version
          '',
          # par[:GS08][6..-1], # assoc. assigned code (subset)
          ''].join(':')
        @msg_type = par[:ST01]

        @dir = EDI::Dir::Directory.create(std, par )
#                                          :d0065 => @msg_type,
#                                          :d0052 => par[:d0052], 
#                                          :d0054 => par[:d0054], 
#                                          :d0051 => par[:d0051], 
#                                          :d0057 => par[:d0057], 
#                                          :is_iedi => par[:is_iedi])
      when 'E' # UN/EDIFACT
        @base_key = [par[:d0065], # msg type
          par[:d0052], # version
          par[:d0054], # release, 
          par[:d0051], # resp. agency
          # '',
          par[:d0057], # assoc. assigned code (subset)
          ''].join(':')
        @msg_type = par[:d0065]

        @dir = EDI::Dir::Directory.create(std,
                                          :d0065 => @msg_type,
                                          :d0052 => par[:d0052], 
                                          :d0054 => par[:d0054], 
                                          :d0051 => par[:d0051], 
                                          :d0057 => par[:d0057], 
                                          :is_iedi => par[:is_iedi])
      when 'I' # SAP IDocs
        @base_key = [par[:IDOCTYPE],
          par[:EXTENSION],
          par[:SAPTYPE],
          '',
          '',
          #                   par[:d0057],  # assoc. assigned code (subset)
          ''].join(':')
        @msg_type = par[:IDOCTYPE]

        @dir = EDI::Dir::Directory.create(std,
                                          :IDOCTYPE => @msg_type,
                                          :EXTENSION => par[:EXTENSION], 
                                          :SAPTYPE => par[:SAPTYPE])
        #      raise "Not implemented yet!"

      when 'S' # SEDAS
        @base_key = [par[:SEDASTYPE],
          '',
          '',
          '',
          '',
          #                   par[:d0057],  # assoc. assigned code (subset)
          ''].join(':')
        @msg_type = par[:SEDASTYPE]

        @dir = EDI::Dir::Directory.create(std)

      else
        raise "Unsupported syntax standard: #{std}"
      end

      top_branch = Branch.new( @base_key, nil, self )
      raise "No branch found for key '#{@base_key}'" unless top_branch

      @diag = top_branch.expand
      @desc = @diag.desc

      i = 0; @node_dict = {}
      @diag.each { |node| i+=1; node.index=i; @node_dict[i]=node }
    end


    # Iterates recursively through all nodes of the diagram.
    #
    def each(&b)
      @diag.each(&b)
    end


    # Index access through ordinal number of node, starting with 1 (!).
    #
    def [](i)
      @node_dict[i] # efficient access via hash
    end

    # Getter for the directory object associated with this diagram.
    #
    def dir
      @dir
    end

    # Returns the top branch of the diagram.
    #
    def branch
      @diag
    end

  end


  #
  # A Branch is a sequence of Nodes. It corresponds to a segment group without
  # its included groups (no sub-branches). A Branch has a name (+sg_name+)
  # and comes with descriptory text (+desc+).
  #
  # Note that included TNodes may have side chains/branches ("tails").
  #
  class Branch
    attr_accessor :desc
    attr_reader :sg_name

    # A new Branch object is uniquely identified by the +key+ argument
    # that selects the directory entry and its +sg_name+ (if not top branch).
    # +root+ is a reference to the Diagram it belongs to.

    def initialize(key, sg_name, root)
      # warn "Creating branch for key `#{key||''+sg_name||''}'..."
      @key = key
      @sg_name = sg_name
      @root = root

      @nodelist=[]
      b = @root.dir.message( key+sg_name.to_s )
=begin
      # UN/EDIFACT subsets only:
      if b.nil? && key =~ /(\w{6}:\w+:\w+:\w+:)(.+?)(:.*)/
	puts "2: #{key}"
	@key = key = $1+$3 # Discard the subset DE
	puts "3: #{key}"
	EDI::logger.warn "Subset #{$2} data not found - trying standard instead..."
        b = @root.dir.message( key+sg_name.to_s )
      end
=end
      raise EDI::EDILookupError, "Lookup failed for key `#{key+sg_name.to_s}' - known names: #{@root.dir.message_names.join(', ')}" unless b
      @desc = b.desc
      b.each {|obj| @nodelist << Node.create( obj.name, obj.status, obj.maxrep )}
      raise "Empty branch! key, sg = #{key}, #{sg_name}" if @nodelist.empty?
    end

    #
    # Recursively add "tails" (branches, segment groups) to TNodes
    #
    def expand
      each do |node|
        if node.is_a? TNode and node.tail == nil
          #        puts "Expanding #{node}"
          tail = Branch.new(@key, node.name, @root)

          # Merge TNode with first tail node (trigger segment)
          trigger_segment = tail.shift
          node.name = trigger_segment.name
          if trigger_segment.status != 'M' or trigger_segment.maxrep != 1
            raise "#{trigger_segment.name}: Not a trigger seg!" 
          end
          node.tail = tail.expand # Recursion!
        end
      end
      self
    end

    # Removes and returns the first node from the node list, cf. Array#shift
    #
    def shift
      @nodelist.shift
    end

    # Makes +node+ the first node of the node list, cf. Array#unshift
    #
    def unshift(node)
      @nodelist.unshift(node)
    end

    # Iterate through each node of the node list
    #
    def each
      @nodelist.each {|node|
        yield(node)
        if node.is_a? TNode and node.tail
          node.tail.each {|tn| yield(tn)} # Recursion
        end
      }
    end

    #  def each_pruned
    #    @nodelist.each {|node|
    #      yield(node)	# Simple array interator, no sidechains
    #    }
    #  end

    # Access node list by index, cf. Array
    #
    def [](index)
      @nodelist[index]
    end

    # Returns size of the node list (number of nodes of this branch)
    #
    def size
      @nodelist.size
    end

    # Returns TRUE if branch is empty. Example: 
    #  The tail of a segment group that consists of just the trigger segment
    #
    def empty?
      @nodelist.size==0
    end

  end


  #
  # A Node is essentially the representation of a segment in a diagram.
  # It comes in two flavors: Simple nodes (SNode) and T-nodes (TNode) 
  # which may have "tails".
  # "Node" is an abstract class - either create a SNode or a TNode.
  #
  class Node
    private_class_method :new	# Make it an abstract class
    attr_accessor :name, :index
    attr_reader :status, :maxrep

    # +name+ ::   The node's name, e.g. the segment tag
    # +status+ :: A one-char string like 'M' (mandatory), 'C' (conditional)
    # +rep+ ::    The max. number of repetitions of this node as allowed
    #             by the diagram specs.
    #
    def Node.create(name, status, rep)
      case name
      when /^SG\d+$/ # T-Node
        return TNode.new(name, status, rep)
      else	   # Simple node
        return SNode.new(name, status, rep)
      end
    end

    def initialize(name, status, rep) # :nodoc:
      @name, @status, @maxrep = name, status, rep
      # @template = EDI::Segment.new(name, nil, nil)
      # warn "Creating node: #{self.to_s}"
    end

    def to_s
      "%3d - %s, %s, %d" % [@index, @name, @status, @maxrep]
    end

    def required?
      (@status =~ /[MR]/) ? true : false
    end

    # Returns +nil+ for an SNode or a reference to the side branch ("tail")
    # of a TNode.
    def tail
      return nil # Only TNode implements this non-trivially
    end
  end

  #
  # Simple node:
  # Just store name (segment tag), status (M/C etc), max repetitions
  #
  class SNode < Node
    public_class_method :new
  end

  #
  # T-Node:
  # Additionally maintain the tail branch and the segment group name
  #
  class TNode < Node
    public_class_method :new
    attr_accessor :tail
    attr_reader :sg_name

    def initialize(name, status, rep)
      super
      @tail, @sg_name = nil, @name
    end

  end

  ####################################################################
  #
  # Nodes and more

  NodeCoords = Struct.new( :branch, :offset, :inst_cnt )

  # Node co-ordinates: A Struct consisting of the +branch+, its +offset+ 
  # within the branch, and its instance counter +inst_cnt+ .

  class NodeCoords
    def to_s
      "<NodeCoords>"+self.branch.object_id.to_s+', '+self.offset.to_s+', '+self.inst_cnt.to_s
    end
  end

  # NodeInstance
  #
  # A given segment of a real message instance needs an instance counter
  # in addition to its location in the diagram. This applies recursively 
  # to all segment groups in which it is embedded. This class is equipped 
  # with the additional attributes ("co-ordinates") of node instances.
  #
  # We also use this class to determine the node instance of a segment
  # when parsing a message. This is done in a sequential manner, starting
  # from the current instance, by following the diagram branches up to
  # the next matching segment tag/name.
  #
  class NodeInstance

    # A new NodeInstance is inititialized to a "virtual" 0th node
    # before the first real node of the diagramm referenced by +diag+ .
    #
    def initialize( diag )
      @diag = diag # Really needed later?
      
      # Init. to first segment of top branch, e.g. "UNH" or "EDI_DC40"
      @coord = NodeCoords.new(diag.branch, 0, 0)
      @coord_stack = []
      @down_flag = false
    end

    # Returns the node's instance counter
    #
    def inst_cnt
      @coord.inst_cnt
    end

    alias rep inst_cnt


    # Returns diagram node corresponding to this instance's co-ordinates
    #
    def node
      @coord.branch[@coord.offset]
    end

    # Delegate some getters to the underlying diagram node:
    #  index, maxrep, name, status
    #
    def name;   node.name;   end
    def status; node.status; end
    def maxrep; node.maxrep; end
    def index;  node.index;  end

    # Returns this node instance's level in the diagram.
    # Note that special UN/EDIFACT rules about level 0 are acknowledged:
    # level == 0 for mandatory SNode instances of the main branch with maxrep==1.
    def level
      depth = @coord_stack.length+1
      return 0 if depth == 1 and node.maxrep == 1 and node.required? and not is_tnode? # Special Level 0 case
      depth # Else: Level is depth of segment group stack + 1 (1 if no SG)
    end

    # Returns the branch name (segment group name)
    #
    def sg_name
      #    (node.is_a? TNode) ? node.sg_name : nil
      if node.is_a? TNode
        return node.sg_name
      end
      @coord.branch.sg_name
    end

    # +true+ if this is a TNode (trigger node/segment)
    def is_tnode?
      node.is_a? TNode
    end


    # Main "workhorse": Seek for next matching segment tag/name
    #
    # Starts at current location, follows the diagram downstream
    # while searching for next matching segment.
    #
    # Returns updated location (self) when found, nil otherwise.
    #
    # Notes:
    # 1. Search fails when trying to skip a required node
    # 2. Search fails if we hit the end of the diagram before a match
    # 3. We might need to loop through segment groups repeatedly!
    #
    def seek!(seg) # Segment, Regexp or String expected
      name = (seg.is_a? EDI::Segment) ? seg.name : seg
      #    name = (seg.is_a? String) ? seg : seg.name
      begin
        node = self.node
        # warn "Looking for #{name} in #{self.name} @ level #{self.level} while node.maxrep=#{node.maxrep}..."
        #
        # Case "match"
        #
        if node.nil?
          warn "#{name}: #{@coord.offset} #{@coord.branch.sg_name} #{@coord.branch.desc} #{@coord.branch.size}"
          raise "#{self}: no node!"
        end
        if name === node.name # == name
          #        puts "match!"
          @coord.inst_cnt += 1
          msg = "Segment #{name} at #{@coord.to_s}: More than #{node.maxrep}!"
          if @coord.inst_cnt > node.maxrep
            raise EDI::EDILookupError, msg
          else
            @down_flag = true if node.is_a? TNode
            return self# .node
          end
        end
        #
        # Missed a required node?
        #
        if node.required? and @coord.inst_cnt == 0 # @unmatched
          msg = "Missing required segment #{node.name} at #{@coord.to_s}\n" + \
          " while looking for segment #{name}!"
          raise EDI::EDILookupError, msg
        end
        #      puts
      end while self.next!
      # Already at top level - Error condition!
      raise "End of diagram exceeded!"
    end

    # Navigation methods, for internal use only

    protected

    #
    # Move "up" to the TNode of this branch.
    # Returns +self+, or +nil+ if already at the top.
    def up!
      return nil if @coord_stack.empty?
      @coord = @coord_stack.pop
      self
    end

    #
    # Move to the right of the current node in this branch.
    # Returns +self+, or +nil+ if already at the branch end.
    def right!
      return nil if @coord.offset+1 == @coord.branch.size
      @coord.offset += 1
      @coord.inst_cnt = 0
      self
    end

    #
    # Move to the first node of the tail branch of this TNode.
    # Returns +self+, or +nil+ if there is no tail node.
    def down!
      this_node = self.node
      return nil if (tail=this_node.tail).nil? or tail.empty?
      # Save current co-ordinates on stack
      @coord_stack.push( @coord )
      # Init. co-ordinates for the new level:
      @coord = NodeCoords.new(tail, 0, 0)
      self
    end

    #
    # Next: Move down if TNode and same as last match (another SG instance), 
    # else right. Move up if neither possible.
    # Returns +self+, or +nil+ if end of diag encountered.
    def next!
      loop do
        node = self.node; r = nil
        if node.is_a? TNode and @down_flag
          @down_flag = false
          r = self.down!
        end
        break if r
        # Down not applicable or available; now try "right!"
        break if r = self.right!
        # At end of this branch - try to move up:
        break if r = self.up!
        # Already at top level!
        return nil
      end
      self
    end

  end

end # module EDI::Diagram
