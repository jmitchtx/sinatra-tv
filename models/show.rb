require 'mongoid'
require 'net/http'
require 'open-uri'

class Show
  include Mongoid::Document
  
  SHOW_PATTERN = /^(-?)(.+)s([0-9]+)e([0-9]+)(.+)$/i
  BINARY_TYPES = %w(mkv avi mp4 mpg m4v ts divx)
  EPISODE_PATH = 'rage_summary.Episodelist.episode'
    
  field :name,              type: String
  field :name_in_lowercase, type: String
  field :name_on_disk,      type: String
  field :name_in_dots,      type: String
  field :showid,            type: String
  field :last_calculated,   type: Date, default: ->{ Date.today }
  field :ignore_unwatched,  type: Boolean, default: false
  
  field :tags,              type: Hash,  default: []
  field :files,             type: Array, default: []  # ToDo - this is supposed to hold 'special episodes' or anything not matching a regular season or episode
  field :genres,            type: Array, default: []
  field :spam,              type: Array, default: []
  field :aliases,           type: Array
  
  field :rage_summary,      type: Hash, default: {}
  field :rage_timestamp,    type: Time
  field :started_as_date,   type: Date
  field :ended_as_date,     type: Date
  
  index({ name: 1 }, { unique: true, name: "name_index" })
  
  scope :minus_ignored,           lambda{                 where(:ignore_unwatched.ne => true)}
  scope :with_airday,             lambda{|airday|         where(:"rage_summary.airday"          => airday) }
  scope :with_genre,              lambda{|genre|          where(:"rage_summary.genres.genre"    => genre) }
  scope :has_not_yet_ended,       lambda{                 where(:"rage_summary.ended"           => nil) }
  scope :has_unwatched_episodes,  lambda{                 where(:"rage_summary.Episodelist.episode.watched" => false) }
  scope :has_downloadable_episodes, lambda{               where(:"rage_summary.Episodelist.episode.available" => true) }
  scope :this_and_last_month,     lambda{                 any_of(:"rage_summary.Episodelist.episode.airdate" => this_month, 
                                                                 :"rage_summary.Episodelist.episode.airdate" => last_month)}
  
  validates_presence_of :name_on_disk
  validates_uniqueness_of :name_on_disk
  
  before_save do
    self.name = self.name_on_disk if self.name.blank? and self.name_on_disk.present?
    if self.name
      self.name_in_lowercase  = self.name.downcase
      self.name_in_dots       = self.name_on_disk.downcase.gsub(/ /, '.')
    end
    self.started_as_date  = Date.parse(self.started.gsub(/0000/, '1971').gsub(/-00/, '-01'))  rescue nil
    self.ended_as_date    = Date.parse(self.ended.gsub(  /0000/, '1971').gsub(/-00/, '-01'))  rescue nil
  end
  
  after_save :fetch_cover
  
  before_destroy :remove_cover
  
  def self.this_month
    /^#{Date.today.year}-#{Date.today.month.to_s.rjust(2, '0')}/
  end
  
  def self.last_month
    /^#{30.days.ago.year}-#{30.days.ago.month.to_s.rjust(2, '0')}/
  end
  
  def self.any_episodes_updated_since? timestamp
    all.select{|show| Time.parse(show.rage_timestamp) > Time.parse(timestamp)}
  end
  
  def self.filter_shows_by f, v
    f ||= 'all'
    case f.to_sym
    when :all
      all.asc(:name_in_lowercase)
    when :states
      filter_groups[:states][v.to_sym]
    when :genres
      with_genre(v).asc(:name_in_lowercase)
    when :available
      with_airday(v).has_downloadable_episodes.asc(:name_in_lowercase)
    when :unwatched
      has_unwatched_episodes.minus_ignored.this_and_last_month.asc(:name_in_lowercase)
    end
  end
  
  def self.filter_groups
    @fg ||= {
      :unwatched        => {:unwatched => has_unwatched_episodes.minus_ignored.this_and_last_month},
      :available        => weekday_sort(airdays.inject({}) {|m,         airday| m[airday]         = with_airday(airday).has_downloadable_episodes; m}),
      :genres           =>               genres.inject({}) {|m,          genre| m[genre]          = with_genre(genre); m},
    }
  end
  
  def self.weekday_sort hsh
    day_lookup = {
      :sunday    => 1,
      :monday    => 2,
      :tuesday   => 3,
      :wednesday => 4,
      :thursday  => 5,
      :friday    => 6,
      :saturday  => 7,
    }
    hsh.sort do |a, b|
      (day_lookup[a.first.downcase.to_sym] || 999) <=> (day_lookup[b.first.downcase.to_sym] || 999)
    end
  end
  
  def self.airdays
    @uniq_airdays ||= all.map{|s| s.rage_summary.try(:[], 'airday')}.compact.uniq.sort
  end
  
  def self.genres
    @uniq_genres ||= [all.map{|s| s.rage_summary.try(:[], 'genres').try(:[], 'genre')}].flatten.compact.uniq.sort
  end
  
  def airday
    rage_summary['airday'].try :pluralize
  end
  
  def genres
    [rage_summary.try(:[], 'genres').try(:[], 'genre')].flatten.compact.unshift(classification)
  end
  
  def classification
    rage_summary['classification']
  end
  
  def airtime
    rage_summary['airtime']
  end
  
  def runtime
    rage_summary['runtime']
  end
  
  def network
    rage_summary['network']
  end
  
  def started
    rage_summary['started']
  end
  
  def ended
    rage_summary['ended'] || "(#{status})"
  end
  
  def status
    rage_summary['status']
  end
  
  def classification
    rage_summary['classification']
  end
  
  def slug
    self._id
  end
  
  def self.with_episode criteria, value, &block
    shows = where("#{EPISODE_PATH}.#{criteria}".to_sym => value)
    return unless shows.count > 0
    shows.each do |show|
      show.rage_summary["Episodelist"].each do |seasons|
        seasons.each do |k, episodes|
          next unless k == 'episode'
          episodes.each do |episode|
            if episode[criteria.to_s] == value
              block.call show, episode
            end
          end
        end
        show.save
      end
    end
  end
  
  def self.seen_it show, episode_path
    with_episode("#{EPISODE_PATH}.binary".to_sym, episode_path) do |show, season, episode|
      episode.merge!('binary' => watched_for(episode_path))
      episode.merge!('watched' => true)
    end
  end
  
  def episode_for binary
    rage_summary["Episodelist"].each do |seasons|
      seasons.each do |k, episodes|
        next unless k == 'episode'
        episodes.each do |episode|
          return episode['binary'] if episode['binary'] == binary
        end
      end
    end
  end

  def self.watched_for show_path
    dash = (show_path =~ /\/-/) ? '-' : ''
    "#{File.dirname(show_path)}/#{dash}#{File.basename(show_path)}"
  end
  
  def fetch_cover
    return true unless image.present?
    open(cached_cover_path, 'wb') do |f|
      f << open(image).read
    end unless File.exist? cached_cover_path
  end
  
  def remove_cover
    return true unless image.present?
    return true unless File.exist? cached_cover_path
    File.delete cached_cover_path
  end
  
  def cached_cover_path
    rage_to_cover[2]
  end
  
  def cover
    return '/assets/no_cover.jpg' unless image
    file, img = rage_to_cover[1..2]
    cvr = %{#{File.dirname(__FILE__)}/../public#{img}}
    return "/covers/#{file}" if File.exist?(cvr)
    '/assets/no_cover.jpg'
  end
  
  def image
    (rage_summary and rage_summary["image"])
  end
  
  def rage_to_cover
    ext = File.extname(URI.parse(image).path)
    file = "#{name}#{ext}"
    img = "/covers/#{file}"
    [ext, file, img]
  end
  
  def last_updated_ago
    rage_timestamp
  end
  
  def seasons
    begin
      rage_summary.try(:[], "Episodelist") || []
    rescue Exception => e
      raise "#{e.message} (#{name}) #{rage_summary.inspect}"
    end
  end
  
  def self.refresh_everything
    fetch_rage_data all
    fetch_rage_summary all
    refresh_episodes
    import
  end
  
  def self.import files_pattern=EPISODES_FILE
    Dir.glob(EPISODES_FILE).each do |file|
      base_path     = `head -n 1 #{file}`.chomp
      current_shows = `egrep -i "^#{base_path}/[^/_]*$" #{file} | egrep -vi 's[0-9]{2,}' | sed "s,#{base_path}/,current@,"`.chomp
      tagged_shows  = `egrep -i "^#{base_path}/_[^/]*/[^/_]*$" #{file} | grep -v _flix | egrep -vi 's[0-9]{2,}' | sed "s,#{base_path}/_,," | sed "s,/,@,"`.chomp

      [current_shows.split("\n") + tagged_shows.split("\n")].flatten.each do |tag_show|
        tag, show_name = tag_show.split("@")
        show = Show.where(name_on_disk: show_name).one
        Show.find_or_create_by(name_on_disk: show_name)
      end
    end
  end

  def self.calculate_availability shows = all
    shows.each do |show|
      show.calculate_availability
    end
  end
  
  def calculate_availability
    return unless self.rage_summary
    self.rage_summary["Episodelist"].each do |season|
      season["episode"].each do |episode|
        next unless airdate = Date.parse(episode['airdate']) rescue nil
        episode.merge!('available' => (airdate > 1.week.ago.to_date and airdate < Date.today and episode['binary'].blank?))
      end
    end
    self.last_calculated = Date.today
    self.save
  end

  def fetch_rage_data
    self.class.fetch_rage_data [self]
  end

  def self.fetch_rage_data shows
    rage_uri = URI("http://services.tvrage.com")
    Net::HTTP.start(rage_uri.host, rage_uri.port) do |http|
      shows.each do |show|
        next if show.showid
        rage_search_uri = URI("http://services.tvrage.com/tools/quickinfo.php?show=#{URI.encode(show.name_on_disk)}")
        request = Net::HTTP::Get.new rage_search_uri.request_uri
        debug "Attempting to load basic show info for: #{show.name_on_disk}"
        response = http.request(request)
        code, body = response.code, response.body
        data = body.split("\n")
        show.showid = data[0].split('@').last
        show.name   = data[1].split('@').last
        show.save
      end
    end
  end

  def fetch_rage_summary
    self.class.fetch_rage_summary [self]
  end

  def self.new_show_for new_show
    show = Show.create(:name_on_disk => new_show.humanize)
    fetch_rage_data [show]
  end

  def self.fetch_rage_summary shows = has_not_yet_ended
    shows.each do |show|
      show.fetch_rage_data unless show.showid
      rage_uri = URI("http://services.tvrage.com")
      Net::HTTP.start(rage_uri.host, rage_uri.port) do |http|
        details_uri = URI("http://services.tvrage.com/feeds/full_show_info.php?sid=#{URI.encode(show.showid)}")
        request = Net::HTTP::Get.new details_uri.request_uri
        debug "Attempting to load rage_summary for: #{show.name}"
        begin
          response = http.request(request)
          code, body = response.code, response.body
        rescue Timeout::Error => e
          code = "500"
          body = e.message
        end
        if code == "200"
          rage_summary = Hash.from_xml(body)["Show"]
          rage_summary["Episodelist"] = [rage_summary["Episodelist"]["Season"]].flatten

          # self.airdate_as_date = Date.parse self.airdate.gsub(/0000/, '1971').gsub(/-00/, '-01') rescue nil

          show.rage_summary = rage_summary
          show.rage_timestamp = Time.now
        else
          # show.rage_summary = {:code => code, :error => body}
        end
        show.save
      end
    end
  end

  def self.unknown_episodes files_pattern=EPISODES_FILE
    names_in_dots = all.map(&:name_in_dots)
    names_on_disk = all.map(&:name_on_disk)
    remaining_episodes = []
    Dir.glob(files_pattern).each do |file|
      raise "#{file} doesn't exist" unless File.exist?(file)
      names_in_dots.in_groups_of(10)
      remaining_episodes << %x{egrep -v '#{names_in_dots.join('|')} #{file} | egrep -v #{names_on_disk.join('|')}' #{file}}
    end
    remaining_episodes
  end

  def episodes_from file
    raise "Name too short (#{name_in_dots})" unless (name_in_dots.try(:length) || 0) > 3
    (%x{egrep -i #{name_in_dots.inspect} #{file} | sed 's/.*://'} || '').split("\n")
  end

  def self.refresh_episodes files_pattern=EPISODES_FILE
    all.each do |show|
      show.refresh_episodes
    end
  end

  def refresh_episodes files_pattern=EPISODES_FILE
    # Spam.delete_all
    already_searched_rage = []
    Dir.glob(files_pattern).each do |file|
      raise "#{file} doesn't exist" unless File.exist?(file)
      episodes_from(file).each do |path|
        # if path =~ /.DS_Store/
        #   next
        # end
        file = File.basename(path)
        watched, show_name, season, episode, spams = file.scan(SHOW_PATTERN).try(:first)
        debug <<-DEBUG
          path:       #{path.inspect}
          watched:    #{watched.inspect}
          show_name:  #{show_name.inspect}
          season:     #{season.inspect}
          episode:    #{episode.inspect}
          spams:      #{spams.inspect}
        DEBUG

        unless show_name
          debug(" -------------------------------> show_name missing -- skipping")
          next
        end

        # show_name = show_name.downcase.gsub(/\.|_|-/, ' ').strip
        #
        # if self.name_in_lowercase !~ /^#{show_name}$/
        #   debug("-------------------------------> #{show_name} doesn't match #{show.name_in_lowercase} -- skipping")
        #   next
        # end

        unless season and episode
          # show = Show.find_or_create_by(name: show_name)
          self.files.push file
          self.save
          # show = nil
          debug(" -------------------------------> season or episode missing -- skipping")
          next
        end

        spam = (spam || '').gsub(/-/, '.')
        spam = (spams || '').split('.').reject{|s| s.blank? }
        extension = spam.pop
        unless BINARY_TYPES.include? extension
          debug(" -------------------------------> extension(#{extension}) doesn't match acceptable types -- skipping")
          next
        end
        self.spam = spam

        watched = (watched || '').match(/-/).present?

        begin
          tv_seasons      = self.rage_summary["Episodelist"]
          tv_season       = (tv_seasons || []).select{|sn| sn["no"] == season.to_i.to_s}.first
          tv_episode      = ((tv_season || {})["episode"] || []).select{|ep| ep["seasonnum"] == episode}
          tv_episode_hash = tv_episode.first
        rescue Exception => e
          raise "An exception occurred processing #{show_name} : #{e.message}"
        end
        unless tv_episode_hash
          debug(" -------------------------------> No episode info show found for #{show_name} -- skipping")
          next
        end

        tv_episode_hash.merge!('binary' => path)
        tv_episode_hash.merge!('watched' => watched)
        self.save
      end
    end
  end

  def self.debug(sttmt)
    # @debug_info.push sttmt
    # puts sttmt
    # Rails.logger.debug sttmt
  end

  def debug(sttmt)
    # @debug_info.push sttmt
    # puts sttmt
    # Rails.logger.debug sttmt
  end
  
  
end


# def import
#   @binaries_adapter.import(:binary_files_pattern => (ENV['binary_files_pattern'] || TVR.config['binary_files_pattern'] || DEFAULT_BINARIES_PATTERN))
# end

# def self.refresh_everything
#   fetch_rage_data all
#   fetch_rage_summary all
#   refresh_episodes
# end

# def import options
#   Dir.glob(options[:binary_files_pattern]).each do |file|
#     base_path     = `head -n 1 #{file}`.chomp
#     current_shows = `egrep -i "^#{base_path}/[^/_]*$" #{file} | egrep -vi 's[0-9]{2,}' | sed "s,#{base_path}/,current@,"`.chomp
#     tagged_shows  = `egrep -i "^#{base_path}/_[^/]*/[^/_]*$" #{file} | grep -v _flix | egrep -vi 's[0-9]{2,}' | sed "s,#{base_path}/_,," | sed "s,/,@,"`.chomp
#
#     [current_shows.split("\n") + tagged_shows.split("\n")].flatten.each do |tag_show|
#       tag, show_name = tag_show.split("@")
#       show = Show.where(name_on_disk: show_name).one
#       Show.find_or_create_by(name_on_disk: show_name)
#     end
#   end
# end

# def unknown_episodes binary_files_pattern=EPISODES_FILE
#   names_in_dots = all.map(&:name_in_dots)
#   names_on_disk = all.map(&:name_on_disk)
#   remaining_episodes = []
#   Dir.glob(binary_files_pattern).each do |file|
#     raise "#{file} doesn't exist" unless File.exist?(file)
#     names_in_dots.in_groups_of(10)
#     remaining_episodes << %x{egrep -v '#{names_in_dots.join('|')} #{file} | egrep -v #{names_on_disk.join('|')}' #{file}}
#   end
#   remaining_episodes
# end

# def calculate_availability shows = all
#   shows.each do |show|
#     show.calculate_availability
#   end
# end
#
# def fetch_rage_data shows
#   rage_uri = URI("http://services.tvrage.com")
#   Net::HTTP.start(rage_uri.host, rage_uri.port) do |http|
#     shows.each do |show|
#       next if show.showid
#       rage_search_uri = URI("http://services.tvrage.com/tools/quickinfo.php?show=#{URI.encode(show.name_on_disk)}")
#       request = Net::HTTP::Get.new rage_search_uri.request_uri
#       debug "Attempting to load basic show info for: #{show.name_on_disk}"
#       response = http.request(request)
#       code, body = response.code, response.body
#       data = body.split("\n")
#       show.showid = data[0].split('@').last
#       show.name   = data[1].split('@').last
#       show.save
#     end
#   end
# end
#
#
# def new_show_for new_show
#   show = Show.create(:name_on_disk => new_show.humanize)
#   fetch_rage_data [show]
# end
#
# def fetch_rage_summary shows = has_not_yet_ended
#   shows.each do |show|
#     show.fetch_rage_data unless show.showid
#     rage_uri = URI("http://services.tvrage.com")
#     Net::HTTP.start(rage_uri.host, rage_uri.port) do |http|
#       details_uri = URI("http://services.tvrage.com/feeds/full_show_info.php?sid=#{URI.encode(show.showid)}")
#       request = Net::HTTP::Get.new details_uri.request_uri
#       debug "Attempting to load rage_summary for: #{show.name}"
#       begin
#         response = http.request(request)
#         code, body = response.code, response.body
#       rescue Timeout::Error => e
#         code = "500"
#         body = e.message
#       end
#       if code == "200"
#         rage_summary = Hash.from_xml(body)["Show"]
#         rage_summary["Episodelist"] = [rage_summary["Episodelist"]["Season"]].flatten
#
#         # self.airdate_as_date = Date.parse self.airdate.gsub(/0000/, '1971').gsub(/-00/, '-01') rescue nil
#
#         show.rage_summary = rage_summary
#         show.rage_timestamp = Time.now
#       else
#         # show.rage_summary = {:code => code, :error => body}
#       end
#       show.save
#     end
#   end
# end
#
# def refresh_episodes files_pattern=EPISODES_FILE
#   all.each do |show|
#     show.refresh_episodes
#   end
# end
#
#
# def refresh_episodes files_pattern=EPISODES_FILE
#   # Spam.delete_all
#   already_searched_rage = []
#   Dir.glob(files_pattern).each do |file|
#     raise "#{file} doesn't exist" unless File.exist?(file)
#     episodes_from(file).each do |path|
#       # if path =~ /.DS_Store/
#       #   next
#       # end
#       file = File.basename(path)
#       watched, show_name, season, episode, spams = file.scan(SHOW_PATTERN).try(:first)
#       debug <<-DEBUG
#         path:       #{path.inspect}
#         watched:    #{watched.inspect}
#         show_name:  #{show_name.inspect}
#         season:     #{season.inspect}
#         episode:    #{episode.inspect}
#         spams:      #{spams.inspect}
#       DEBUG
#
#       unless show_name
#         debug(" -------------------------------> show_name missing -- skipping")
#         next
#       end
#
#       # show_name = show_name.downcase.gsub(/\.|_|-/, ' ').strip
#       #
#       # if self.name_in_lowercase !~ /^#{show_name}$/
#       #   debug("-------------------------------> #{show_name} doesn't match #{show.name_in_lowercase} -- skipping")
#       #   next
#       # end
#
#       unless season and episode
#         # show = Show.find_or_create_by(name: show_name)
#         self.files.push file
#         self.save
#         # show = nil
#         debug(" -------------------------------> season or episode missing -- skipping")
#         next
#       end
#
#       spam = (spam || '').gsub(/-/, '.')
#       spam = (spams || '').split('.').reject{|s| s.blank? }
#       extension = spam.pop
#       unless BINARY_TYPES.include? extension
#         debug(" -------------------------------> extension(#{extension}) doesn't match acceptable types -- skipping")
#         next
#       end
#       self.spam = spam
#
#       watched = (watched || '').match(/-/).present?
#
#       begin
#         tv_seasons      = self.rage_summary["Episodelist"]
#         tv_season       = (tv_seasons || []).select{|sn| sn["no"] == season.to_i.to_s}.first
#         tv_episode      = ((tv_season || {})["episode"] || []).select{|ep| ep["seasonnum"] == episode}
#         tv_episode_hash = tv_episode.first
#       rescue Exception => e
#         raise "An exception occurred processing #{show_name} : #{e.message}"
#       end
#       unless tv_episode_hash
#         debug(" -------------------------------> No episode info show found for #{show_name} -- skipping")
#         next
#       end
#
#       tv_episode_hash.merge!('binary' => path)
#       tv_episode_hash.merge!('watched' => watched)
#       self.save
#     end
#   end
# end
#
# def self.debug(sttmt)
#   # @debug_info.push sttmt
#   # puts sttmt
#   # Rails.logger.debug sttmt
# end
#
# def debug(sttmt)
#   # @debug_info.push sttmt
#   # puts sttmt
#   # Rails.logger.debug sttmt
# end
#
# def self.watched_for show_path
#   dash = (show_path =~ /\/-/) ? '-' : ''
#   "#{File.dirname(show_path)}/#{dash}#{File.basename(show_path)}"
# end
#
# # def self.seen_it show, episode_path
# #   with_episode("#{EPISODE_PATH}.binary".to_sym, episode_path) do |show, season, episode|
# #     episode.merge!('binary' => watched_for(episode_path))
# #     episode.merge!('watched' => true)
# #   end
# # end
#
# def self.with_episode criteria, value, &block
#   shows = where("#{EPISODE_PATH}.#{criteria}".to_sym => value)
#   return unless shows.count > 0
#   shows.each do |show|
#     show.rage_summary["Episodelist"].each do |seasons|
#       seasons.each do |k, episodes|
#         next unless k == 'episode'
#         episodes.each do |episode|
#           if episode[criteria.to_s] == value
#             block.call show, episode
#           end
#         end
#       end
#       show.save
#     end
#   end
# end



# def play
#   send_media_box %Q{open \\"#{seen_it}\\"}
#   render_show
# end

# def seen_it
#   unless File.basename(episode) =~ /\/-/
#     show_name = "#{File.dirname(episode)}/-#{File.basename(episode)}"
#     send_media_box %Q{mv \\"#{episode}\\" \\"#{show_name}\\"}
#     sleep 1
#   end
#   show_name
# end


# def new_show
#   Show.new_show_for params[:new_show]
#   redirect_to :back
# end
#
# def add_tag
#   show.tap{|s| s.tags.push show_tag}.save if show_tag
#   render_show
# end
#
# def remove_tag
#   show.tap{|s| s.tags.delete show_tag} if show_tag
#   render_show
# end
#
# def render_show shw = nil
#   shw ||= show
#   expire_fragment(shw.name)
#   render :partial => 'show', :locals => {:show => shw, :row => row}
# end
#
# def show_path
#   "#{params[:show]}"
# end
#
# def set_volume
#   osascript "set Volume #{params["vol"]}"
#   render :nothing => true
# end
#
# def volume
#   result = osascript('set curVolume to output volume of (get volume settings)')
#   render :json => result
# end
#
#
#
# def osascript cmd
#   send_media_box %Q{osascript -e '#{cmd}'}
# end
#
# def send_media_box cmd
#   command = %Q{ssh #{Tv.tv.name} "#{cmd}"}
#   Rails.logger.debug "===============> #{command}"
#   `#{command}`
# end
#
# def tv_clear_cache
#   TvDatabase.clear_cache
# end
#
# def tv_rage
#   tv_db.tv_rage params[:show]
#   redirect_to :back and return unless params[:show]
#   render :nothing => true
# end
#
# def choose_device
#   Tv.all.map{|tv| tv.tap{|t| t.current = false}.save}
#   Tv.where(name: params[:device]).one.tap{|t| t.current = true}.save
#   redirect_to :back
# end
#
# def destroy
#   show.destroy
#   render :nothing => true
# end
#
# def ignore_unwatched
#   show.tap{|s| s.ignore_unwatched = true}.save
#   render_show
# end
