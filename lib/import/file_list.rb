class FileList < Binaries
  
  # def self.import options
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
  
end