require 'sinatra/base'
require 'mongoid'
require 'haml'
require 'pp'

Dir.glob('models/**/*').each{|f| require_relative f }
Dir.glob('lib/**/*'   ).each{|f| require_relative f }


class TVR < Sinatra::Base
  
  ROOT = File.dirname(File.expand_path(__FILE__))
  DEFAULT_BINARIES_PATTERN = "#{ROOT}/.binaries/*"
  DEFAULT_YAML_CONFIG      = "#{ROOT}/config/tvr.yml"
  DEFAULT_MONGOID_CONFIG   = "#{ROOT}/config/mongoid.yml"
  DEFAULT_ENVIRONMENT      = :development
  
  def self.config
    @config ||= begin
      file = ENV['config'] || DEFAULT_YAML_CONFIG
      YAML::load(File.read(file))
    rescue Exception => e
      raise "There was a problem parsing the YAML config file: '#{file}'\n#{e.message}"
    end
  end
  
  configure do
    mongoid_config = ENV['mongoid_config'] || config['mongoid_config'] || DEFAULT_MONGOID_CONFIG
    environment    = ENV['environment']    || config['environment']    || DEFAULT_ENVIRONMENT
    Mongoid.load!(mongoid_config, environment)
  end

  helpers do
    def partial page, options={}
      haml page, options.merge!(:layout => false)
    end
  
    def tvs
      ::TV.all
    end
  
    def shows
      Show.filter_shows_by(params[:filter], params[:value])
    end
  
    def show
      Show.find_by(params[:show])
    end
  
    def row
      params[:row]
    end
  
    def index
      haml :index
    end
  end

  get '/' do
      index
  end

  get '/device/:device' do
    TV.default params[:device]
    haml :devices
  end

  get '/tv/volume/:volume' do
    TV.volume(params[:volume])
    redirect back
  end

  get '/vlc/:what' do
    what = params[:what].to_sym
    case what
    when :space
      send_system_events 'System Events', 'keystroke space'     # clear the screensaver
    when :volume_down
      vlc "decrease volume"
    when :volume_down
      vlc "decrease volume"
    when :volume_up
      vlc "increase volume"
    when :keystroke_f
      send_system_events 'System Events', %Q{keystroke \\"f\\"} # adjust vlc audio/video alignment forward
    when :keystroke_g
      send_system_events 'System Events', %Q{keystroke \\"g\\"} # adjust vlc audio/video alignment backward
    when :keystroke_s
      send_system_events 'System Events', %Q{keystroke \\"s\\"} # turn off subtitles
    when :step_back
      vlc "step backward"                                       # jump back 10 seconds
    when :step_forward
      vlc "step forward"                                        # jump ahead 10 seconds
    else
      vlc what
    end
    redirect back
  end

  get "/shows/refresh" do
    Show.refresh_everything
    redirect back
  end

  get "/shows/:filter/:value" do
    haml :index
  end

  get "/show/:show/refresh/:row_color" do
    # show.fetch_rage_summary
    # show.refresh_episodes
    render_show(show)
  end


  def render_show shw = nil
    haml :show
  end

  def vlc cmd
    send_system_events :VLC, cmd
  end

  def send_system_events app, cmd
    osascript %Q{tell application \\"#{app}\\" to #{cmd}}
  end

  def osascript cmd
    send_media_box %Q{osascript -e '#{cmd}'}
  end

  def send_media_box cmd
    %x{ssh #{TV.tv.name} "#{cmd}"}
  end
  
  run! if app_file == $0
end