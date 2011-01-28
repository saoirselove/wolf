require 'wolfram'
require 'hirb'

module Wolf
  ALIASES = {}
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

  def devour(argv=ARGV)
    return puts('wolf [-o|--open] [-m|--menu] QUERY') if argv.empty?
    load_rc '~/.wolfrc'
    options = {}
    options[:open] = argv.delete('-o') || argv.delete('--open')
    options[:menu] = argv.delete('-m') || argv.delete('--menu')
    query = build_query(argv)
    _devour(query, options)
  end

  def _devour(query, options={})
    if options[:open]
      browser_opens Wolfram.query(query,
        :query_uri => "http://www.wolframalpha.com/input/").uri(:i => query)
    else
      result = Wolfram.fetch(query)
      puts render(result)

      if options[:menu]
        choices = []
        result.pods.select {|e| e.states.size > 0 }.each {|e|
          choices += e.states.map {|s| [e.title, s.name] } }
        choice = Hirb::Menu.render(choices, :change_fields => ['Section', 'Choice'],
          :prompt =>"Choose one link to requery: ")[0]
        if choice && (pod = result[choice[0]]) && state = pod.states.find {|e| e.name == choice[1] }
          puts render(state.refetch)
        else
          abort "Wolf Error: Unable to find this link to requery it"
        end
      end
    end
  end

  def render(result)
    Hirb.enable
    body = ''
    pods = result.pods.reject {|e| e.title == 'Input interpretation' || e.plaintext == '' }
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
          pod.plaintext.split(/\n{2,}/).each {|text|
            body << render_pod_rows(text_rows(text), text)
          }
        else
          body << render_pod_rows(pod_rows(pod), pod.plaintext)
        end
      end
    end
    body
  end

  def render_pod_rows(rows, text)
    # delete comments
    rows.delete_if {|e| e.size == 1 } if rows.size > 1
    headers = text[/^\s*\|/] ? rows.shift : false
    render_table(rows, headers) << "\n\n"
  end

  def render_table(rows, headers=false)
    Hirb::Helpers::AutoTable.render(rows, :description => false, :headers => headers)
  end

  def pod_rows(pod)
    text_rows pod.plaintext
  end

  def text_rows(text)
    text.split(/\n+/).map {|e| e.split(/\s+\|\s+/) }.delete_if {|e| e.size == 0 }
  end
end
