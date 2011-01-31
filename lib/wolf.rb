require 'wolfram'
require 'hirb'

module Wolf
  ALIASES = {}
  OPTIONS = {:o => :open, :m => :menu, :x => :xml, :v => :verbose, :h => :help,
    :a => :all, :l => :load, :t => :title }
  extend self

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

  def browser_opens(uri)
    system('open', uri)
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

  def devour(argv=ARGV)
    options, fetch_options = parse_options(argv)
    if argv.empty? || options[:help]
      return puts('wolf [-o|--open] [-m|--menu] [-x|--xml] [-v|--verbose]' +
        ' [-a|--all] [-l|--load] [-h|--help] ARGS')
    end
    load_rc '~/.wolfrc'
    query = build_query(argv)
    _devour(query, options, fetch_options)
  end

  def load_result(file)
    Wolfram::Result.new(File.read(file))
  rescue Errno::ENOENT
    abort "Wolf Error: File '#{file}' does not exist"
  end

  def _devour(query, options, fetch_options)
    if options[:open]
      browser_opens Wolfram.query(query,
        :query_uri => "http://www.wolframalpha.com/input/").uri(:i => query)
    elsif options[:xml]
      puts Wolfram.fetch(query, fetch_options).xml
    elsif options[:load]
      query.split(/\s+/).each {|file|
        result = load_result(file)
        render_result result, options
      }
    else
      result = Wolfram.fetch(query, fetch_options)
      render_result result, options

      if options[:menu]
        choices = []
        result.pods.select {|e| e.states.size > 0 }.each {|e|
          choices += e.states.map {|s| [e.title, s.name] } }
        puts "\n** LINKS **"
        choice = Hirb::Menu.render(choices, :change_fields => ['Section', 'Choice'],
          :prompt =>"Choose one link to requery: ", :description => false,
          :directions => false)[0]
        if choice && (pod = result[choice[0]]) && state = pod.states.find {|e| e.name == choice[1] }
          render_result(state.refetch, options)
        else
          abort "Wolf Error: Unable to find this link to requery it"
        end
      end
    end
  end

  def render_result(result, options)
    if result.success
      puts render(result, options)
    else
      warn "No results found"
    end
    puts "\nURI requested: #{result.uri}\n" if options[:verbose]
    puts "Found #{result.pods.size} pods" if options[:verbose]
  end

  def render(result, options)
    Hirb.enable
    body = ''
    pods = options[:all] ? result.pods :
      result.pods.reject {|e| e.title == 'Input interpretation' || e.plaintext == '' }
    pods = pods.select {|e| e.title[/#{options[:title]}/i] } if options[:title]
    # multiple 1-row tables i.e. math results
    if pods.all? {|e| !e.plaintext.include?('|') }
      body << render_table(pods.map {|e| [e.title, e.plaintext] })
    # one one-row table i.e. word results
    elsif pods.size == 1 && pod_rows(pods[0]).size == 1
      body << pods[0].title.capitalize << "\n"
      body << render_table(pod_rows(pods[0])[0])
    else
      pods.each do |pod|
        body << pod.title.capitalize << "\n"

        # Handle multiple tables divided by graphs i.e. when comparing stocks
        if pod.plaintext.include?("\n\n") && pod.states.empty?
          strip(pod.plaintext).split(/\n{2,}/).each {|text|
            body << render_pod_rows(text_rows(text), text, options)
          }
        else
          body << render_pod_rows(pod_rows(pod), strip(pod.plaintext), options)
        end
      end
    end
    body
  end

  def render_pod_rows(rows, text, options)
    # delete comments
    rows.delete_if {|e| e.size == 1 } if rows.size > 1 && !options[:all]
    headers = text[/^\s*\|/] ? rows.shift : false
    render_table(rows, headers) << "\n\n"
  end

  def render_table(rows, headers=false)
    Hirb::Helpers::AutoTable.render(rows, :description => false, :headers => headers)
  end

  def pod_rows(pod)
    text_rows strip(pod.plaintext)
  end

  def strip(text)
    text.sub(/\A(\s+\|){2,}/m, '').sub(/(\s+\|){2,}\s*\Z/, '').strip
  end

  def text_rows(text)
    text.split(/\n+/).map {|e| e.split(/\s*\|\s+/) }
  end
end
