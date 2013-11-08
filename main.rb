class Node < OpenStruct
  DEFAULTS = {
    :root => { :open => true },
    :room => { :open => true },
    :item => { :open => false },
    :player => { :open => true }
  }

  def initialize(parent=nil, tag=nil, defaults={}, &block)
    super()
    defaults.each {|k,v| send("#{k}=", v) }

    self.parent = parent
    self.parent.children << self unless parent.nil?
    self.tag = tag
    self.children = []

    instance_eval(&block) unless block.nil?
  end

  def init_with(c)
    c.map.keys.each do|k|
      instance_variable_set("@#{k}", c.map[k])
    end

    @table.keys.each do|k|
      new_ostruct_member(k)
    end
  end

  def self.save(node, file='save.yaml')
    File.open(file, 'w+') do|f|
      f.puts node.to_yaml
    end
  end

  def self.load(file='save.yaml')
    YAML::load_file(file)
  end

  def puts(*s)
    STDOUT.puts( s.join(' ').word_wrap )
  end

  def to_s(verbose=false, indent='')
    bullet = if parent && parent.tag == :root
               '#'
             elsif tag == :player
               '@'
             elsif tag == :root
               '>'
             elsif open == true
               'O'
             else
               '*'
             end

    str = "#{indent}#{bullet} #{tag}\n"
    if verbose
      self.table.each do|k,v|
        if k == :children
          str << "#{indent+'  '}#{k}=#{v.map(&:tag)}\n"
        elsif v.is_a?(Node)
          str << "#{indent+'  '}#{k}=#{v.tag}\n"
        else
          str << "#{indent+'  '}#{k}=#{v}\n"
        end
      end
    end

    children.each do|c|
      str << c.to_s(verbose, indent + '  ')
    end

    return str
  end

  def described?
    if respond_to?(:described)
      self.described
    else
      false
    end
  end

  def describe
    if !described? && respond_to?(:desc)
      self.described = true
      puts desc
    elsif respond_to?(:short_desc)
      puts short_desc
    else
      # Just make something up
      puts "You are in #{tag}"
    end
  end

  def room(tag, &block)
    Node.new(self, tag, DEFAULTS[:room], &block)
  end

  def item(tag, name, *words, &block)
    i = Node.new(self, tag, DEFAULTS[:item])
    i.name = name
    i.words = words
    i.instance_eval(&block) if block_given?
  end

  def player(&block)
    Node.new(self, :player, DEFAULTS[:player], &block)
  end

  def self.root(&block)
    Node.new(nil, :root, &block)
  end

  def find(thing)
    case thing
    when Symbol
      find_by_tag(thing)
    when String
      find_by_string(thing)
    when Node
      thing
    end
  end

  def find_by_tag(tag)
    return self if self.tag == tag

    children.each do|c|
      res = c.find_by_tag(tag)
      return res unless res.nil?
    end

    return nil
  end

  def find_by_name(words, nodes=[])
    words = words.split unless words.is_a?(Array)
    nodes << self if words.include?(name)

    children.each do |c|
      c.find_by_name(words, nodes)
    end

    return nodes
  end

  def find_by_string(words)
    words = words.split unless words.is_a?(Array)
    nodes = find_by_name(words)

    if nodes.empty?
      puts "I don't see that here"
      return nil
    end

    # Score the nodes by number of matching adjectives
    nodes.each do |i|
      i.search_score = (words & i.words).length
    end

    # Sort the score so that highest scores are
    # at the beginning of the list
    nodes.sort! do |a,b|
      b.search_score <=> a.search_score
    end

    # Remove any nodes with a search score less
    # than the score of the first item in the list
    nodes.delete_if do |i|
      i.search_score < nodes.first.search_score
    end

    # Interpret the results
    if nodes.length == 1
      return nodes.first
    else
      puts "Which item do you mean?"
      nodes.each do |i|
        puts " * #{i.name} (#{i.words.join(', ')})"
      end
      
      return nil
    end
  end

  def get_room
    if parent.tag == :root
      return self
    else
      return parent.get_room
    end
  end

  def get_root
    if tag == :root || parent.nil?
      return self
    else
      return parent.get_root
    end
  end

  def hidden?
    if parent.tag == :root
      return false
    elsif parent.open == false
      return true
    else
      return parent.hidden?
    end
  end

  def move(thing, to, check=true)
    item = find(thing)
    dest = find(to)

    return if item.nil?
    if check && item.hidden?
      puts "You can't get to that right now"
      return
    end

    return if dest.nil?
    if check && (dest.hidden? || dest.open == false)
      puts "You can't put that there"
      return
    end

    item.parent.children.delete(item)
    dest.children << item
    item.parent = dest
  end

  def player(&block)
    Player.new(self, :player, DEFAULTS[:player], &block)
  end

  def ancestors(list=[])
    if parent.nil?
      return list
    else
      list << parent
      return parent.ancestors(list)
    end
  end

  def move(thing, to, check=true)
    item = find(thing)
    dest = find(to)

    return if item.nil?
    if check && item.hidden?
      puts "You can't get to that right now"
      return
    end

    return if dest.nil?
    if check && (dest.hidden? || dest.open == false)
      puts "You can't put that there"
      return
    end

    if dest.ancestors.include?(item)
      puts "Are you trying to destroy the universe?"
      return
    end

    item.parent.children.delete(item)
    dest.children << item
    item.parent = dest
  end

  def script(key, *args)
    if respond_to?("script_#{key}")
      return eval(self.send("script_#{key}"))
    else
      return true
    end
  end

  def describe
    base = if !described? && respond_to?(:desc)
      self.described = true
      desc
    elsif respond_to?(:short_desc)
      short_desc
    else
      # Just make something up
      "You are in #{tag}"
    end

    # Append presence of children nodes if open
    if open
      children.each do|c|
        base << (c.presence || '')
      end
    end

    puts base
  end

end

#####################################################

class Player < Node
  def command(words)
    verb, *words = words.split(' ')
    verb = "do_#{verb}"

    if respond_to?(verb)
      send(verb, *words)
    else
      puts "I don't know how to do that"
    end
  end

  def do_go(direction, *a)
    dest = get_room.send("exit_#{direction}")

    if dest.nil?
      %x[ #{'say You cannot go that way'} ]
    else
      dest = get_root.find(dest)

      if dest.script('enter', direction)
        get_root.move(self, dest)
      end
    end

    room(:hall) do
      self.exit_west = :living_room

      self.script_enter = <<-SCRIPT
        puts "A forcefield stops you from entering the hall"
        return false
      SCRIPT
    end
  end

  def do_examine(*thing)
    item = get_room.find(thing)
    return if item.nil?

    item.described = false
    item.describe
  end

  def do_inventory(*a)
    puts "You are carrying:"

    if children.empty?
      puts " * Nothing"
    else
      children.each do|c|
        puts " * #{c.short_description} (#{c.words.join(' ')})"
      end
    end
  end
  alias_method :do_inv, :do_inventory
  alias_method :do_i, :do_inventory

  def do_take(*thing)
    thing = get_room.find(thing)
    return if thing.nil?

    if thing.script('take')
      puts 'Taken.' if get_root.move(thing, self)
    end

    item(:cat, 'cat', 'sleeping', 'fuzzy') do
      self.script_take = <<-SCRIPT
        if find(:dead_mouse)
          puts "The cat makes a horrifying noise and throws up a dead mouse"
          get_room.move(:dead_mouse, get_room, false)
        end

        puts "The cat refused to be picked up (how degrading!)"
        return false
      SCRIPT

      self.script_control = <<-SCRIPT
        puts "The cat sits upright, awaiting your command"
        return true
      SCRIPT

      self.desc = <<-DESC
        A pumpkin-colored long-haired cat.  He is well-groomed
        and certainly a house cat and seems perfectly content
        to sleep the day away on the couch.
      DESC

      self.short_desc = <<-DESC
        A pumpkin-colored long-haired cat.
      DESC

      self.presence = <<-PRES
        A cat dozes lazily here.
      PRES

      item(:dead_mouse, 'mouse', 'dead', 'eaten')
    end
  end
  alias_method :do_get, :do_take

  def do_drop(*thing)
    move(thing.join(' '), get_room)
  end

  def open_close(thing, state)
    container = get_room.find(thing)
    return if container.nil?
    
    if container.open == state
      puts "It's already #{state ? 'open' : 'closed'}"
    else
      container.open = state
    end
  end

  def do_open(*thing)
    open_close(thing, true)
  end

  def do_close(*thing)
    open_close(thing, false)
  end

  def do_look(*a)
    puts "You are in #{get_room.tag}"
  end

  def do_inventory(*a)
    puts "You are carrying:"

    if children.empty?
      puts " * Nothing"
    else
      children.each do|c|
        puts " * #{c.name} (#{c.words.join(' ')})"
      end
    end
  end

  def do_put(*words)
    prepositions = [' in ', ' on ']

    prep_regex = Regexp.new("(#{prepositions.join('|')})")
    item_words, _, cont_words = words.join(' ').split(prep_regex)

    if cont_words.nil?
      puts "You want to put what where?"
      return
    end

    item = get_room.find(item_words)
    container = get_room.find(cont_words)

    return if item.nil? || container.nil?

    if container.script('accept', item)
      get_room.move(item, container)
    end

    item(:remote_control, 'remote', 'control') do
      self.script_accept = <<-SCRIPT
        if [:new_batteries, :dead_batteries].include?(args[0].tag) &&
            children.empty?
          return true
        elsif !children.empty?
          puts "There are already batteries in the remote"
          return false
        else
          puts "That won't fit into the remote"
          return false
        end
      SCRIPT

      self.script_use = <<-SCRIPT
        if !find(:new_batteries)
          puts "The remote doesn't seem to work"
          return
        end

        if args[0].tag == :cat
          args[0].script('control')
          return
        else
          puts "The remote doesn't seem to work with that"
          return
        end
      SCRIPT

      item(:dead_batteries, 'batteries', 'dead', 'AA')
    end
  end

  %w{ north south east west up down }.each do|dir|
    define_method("do_#{dir}") do
      do_go(dir)
    end

    define_method("do_#{dir[0]}") do
      do_go(dir)
    end
  end
  alias_method :do_get, :do_take
  alias_method :do_inv, :do_inventory
  alias_method :do_i, :do_inventory

  def do_use(*words)
    prepositions = %w{ in on with }
    prepositions.map!{|p| " #{p} " }

    prep_regex = Regexp.new("(#{prepositions.join('|')})")
    item1_words, _, item2_words = words.join(' ').split(prep_regex)

    if item2_words.nil?
      puts "I don't quite understand you"
      return
    end

    item1 = get_room.find(item1_words)
    item2 = get_room.find(item2_words)
    return if item1.nil? || item2.nil?

    item1.script('use', item2)
  end

  def play
    loop do
      do_look
      print "What now? "
      command(gets.chomp)
    end
  end

end

#####################################################

class String
  def word_wrap(width=80)
    # Replace newlines with spaces
    gsub(/\n/, ' ').   
    
    # Replace more than one space with a single space
    gsub(/\s+/, ' ').

    # Replace spaces at the beginning of the
    # string with nothing
    gsub(/^\s+/, '').

    # This one is hard to read.  Replace with any amount
    # of space after it with that punctuation and two
    # spaces
    gsub(/([\.\!\?]+)(\s+)?/, '\1  ').

    # Similar to the call above, except replace commas
    # with a comma and one space
    gsub(/\,(\s+)?/, ', ').

    # The meat of the method, replace between 1 and width
    # characters followed by whitespace or the end of the
    # line with that string and a newline.  This works
    # because regular expression engines are greedy,
    # they'll take as many characters as they can.
    gsub(%r[(.{1,#{width}})(?:\s|\z)], "\\1\n")
  end
end