require 'mpath'
require 'active_support'

class Dot
  
  attr_accessor :name, :nodes, :edges, :clean_names
  
  def initialize name
    @name = name
    @nodes = {}
    @clean_names = {}
    @edges = []
    yield self
  end

  def node name, params = {}
    @nodes[clean_name(name)] = params.stringify_keys.reverse_merge "label"=>name
  end 

  def clean_name name
    @clean_names[name] = "node#{@clean_names.length+1}" if @clean_names[name].nil?
    @clean_names[name]
  end
  
  def edge from, to
    edge = [clean_name(from), clean_name(to)]
    @edges << edge unless @edges.member? edge
  end 

  def to_s
    dot = "digraph #{@name} {\n"
    @nodes.each do |node_name, options|
      dot += "\t#{node_name.to_s}"
      optionstrings = []
      options.keys.sort.each do |key|
        optionstrings << "#{key}=\"#{options[key]}\""
      end
      dot += " [#{optionstrings.join(', ')}]" if optionstrings.length>0
      dot += ";\n"
    end
    @edges.each {|e| dot += "\t#{e[0].to_s}->#{e[1].to_s};\n"}
    dot += "}\n"
  end
  
  def == other
    (other.name == name) && (other.nodes == nodes) && (other.edges == edges) && (other.clean_names == clean_names)
  end
end

class TraceProcessor < ActiveMessaging::Processor
  subscribes_to :trace

  @@dot = Dot.new("Trace") {}

  class << self

  end
  
  def dot
    @@dot
  end
  
  def on_message(message)    
    xml = Mpath.parse(message)
    if (xml.sent?) then
      from = xml.sent.from.to_s
      queue = xml.sent.queue.to_s

      @@dot.node from
      @@dot.node queue, "shape" => 'box'
      @@dot.edge from, queue #hah - could do from => to
    elsif (xml.received?) then
      by = xml.received.by.to_s
      queue = xml.received.queue.to_s

      @@dot.node queue, "shape" => 'box'
      @@dot.node by
      @@dot.edge queue, by
    elsif (xml.trace_control) then
      command = xml.trace_control.to_s
     begin
        send command
      rescue
        puts "TraceProcessor: I don't understand the command #{command}"
      end
    end
    create_image
  end

  def create_image
    File.open(DOT_FILE, "w") {|f| f.puts @@dot.to_s }
    output_file = RAILS_ROOT + "/public/trace.png"
    `dot -Tpng -o #{output_file} #{DOT_FILE}`
  end

  def clear
    @@dot = Dot.new("Trace") {}
  end

end