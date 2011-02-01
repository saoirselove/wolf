require 'wolfram'
require 'hirb'
require 'wolf/stomach'
require 'wolf/mouth'
require 'wolf/version'

module Wolf
  extend self

  ALIASES = {}
  OPTIONS = {:o => :open, :m => :menu, :x => :xml, :v => :verbose, :h => :help,
    :a => :all, :l => :load, :t => :title }
  HELP_OPTIONS = [
    ['-m, --menu', 'Choose from links in a menu and requery with one'],
    ['-o, --open', 'Open query in the browser (mac only)'],
    ['-a, --all', 'Print all tables and rows (uninteresting ones are hidden by default)'],
    ['-t, --title=TITLE', 'Only display tables whose title match TITLE'],
    ['-x, --xml', 'Print raw xml response instead of printing tables'],
    ['-l, --load', "Load one or more xml files to print"],
    ['-v, --verbose', 'Print additional information'],
    ['-h, --help', 'Print help']
  ]

  def devour(argv=ARGV)
    options, fetch_options = parse_options(argv)
    return puts(help) if argv.empty? || options[:help]
    load_rc '~/.wolfrc'
    query = build_query(argv)
    Mouth.eat(query, options, fetch_options)
  end

  def help
    name_max = HELP_OPTIONS.map {|e| e[0].length }.max
    desc_max = HELP_OPTIONS.map {|e| e[1].length }.max
    ["Usage: wolf [OPTIONS] [ARGS]", "\nOptions:",
      HELP_OPTIONS.map {|k,v| "  %-*s  %-*s" % [name_max, k, desc_max, v] },
      "", "Append parameters to a query with options in the format --PARAM=VALUE i.e.",
    "    --reinterpret=true --format=html"]
  end

  def parse_options(argv)
    options, fetch_options = {}, {}
    arg = argv.find {|e| e[/^-/] }
    index = argv.index(arg)
    while arg =~ /^-/
      if arg[/^--?(\w+)=(\S+)/]
        opt = $1.to_sym
        option?(opt) ? options[OPTIONS[opt] || opt] = $2 :
          fetch_options[$1.to_sym] = $2
      elsif (opt = arg[/^--?(\w+)/, 1]) && option?(opt.to_sym)
        options[OPTIONS[opt.to_sym] || opt.to_sym] = true
      end
      argv.delete_at(index)
      arg = argv[index]
    end
    [options, fetch_options]
  end

  def option?(opt)
    OPTIONS.key?(opt) || OPTIONS.value?(opt)
  end

  def load_rc(file)
    load file if File.exists?(File.expand_path(file))
  rescue StandardError, SyntaxError, LoadError => e
    warn "Wolf Error while loading #{file}:\n"+
      "#{e.class}: #{e.message}\n    #{e.backtrace.join("\n    ")}"
  end

  def build_query(args)
    cmd = args.shift
    cmd_alias = ALIASES[cmd]  || ALIASES[cmd.to_sym]
    if cmd_alias.to_s.include?('%s')
      cmd_alias % args
    else
      cmd = cmd_alias || cmd
      ([cmd] + args).join(' ')
    end
  rescue ArgumentError
    abort "Wolf Error: Wrong number of arguments"
  end
end
