# Current Progress


## Current Features

 - Dashboard - Display the currently available shows that I can watch
 - Rage support - Download and organizes season and episode metadata about your shows
 - NZB support - Support for searching configurable (torrent, nzb, etc) search sites for new episode availability


### TODO
  - check for ./.shows/list-of-shows.txt or will assume none
  - on start .. clone, start, lightbox 'You have not configured the system'
    - if new system
      - is mongo running?
      - has existing collection?
  - manage devices
  - many, many more features that were implemented as part of another Rails app ... be patient as I port them to Sinatra
 

## Maybe Features (if someone asks nicely)
 - package TVR as a downloadable gem, executable or something that can be dropped (and run) on a local or remote media box
 - launch VLC to stream back to an embedded viewer, so you can 'play it in the browser'