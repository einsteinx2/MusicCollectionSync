# MusicCollectionSync
A multithreaded swift script for macOS and Linux to recursively sync a folder of music files of various formats to another folder, converting any lossless files to mp3 and copying any lossy files. 

## What's it for?
Let's say you have a huge lossless music collection. Maybe you're a DJ and you have all your files in AIFF for the highest quality and compatibility. However those files are huge, and maybe you want to sync them all to a media player, or keep a USB stick with your music on it. This script allows you to keep a parallel folder structure of all lossy files for easy transporting and syncing.

## How do I use it?
### macOS
1. Install dependencies
   * Install Homebrew if you don't have it: http://brew.sh
   * Open Terminal and run `brew install flac lame mediainfo`
   * Alternatively you can install the flac, lame, and mediainfo command line tools manually 
2. Run the script
   * You should be able to just copy the main.swift file somewhere, and run `swift main.swift inDirectory outDirectory`
   * Or you can compile it first and run it similarly.
   
### Linux
1. Install dependencies
   * Run `apt-get install flac lame mediainfo` or the similar command for your distro
   * Install Swift 3: https://swift.org/download
2. Run the script
   * For some reason it can't find the CoreFoundation library when run as a script, so you have to compile it first by running `swiftc main.swift`
   * Run the script: `./main inDirectory outDirectory`

## Notes
* Supported tags are artist, album, title, track number, total track number, genre, bpm, initialkey, and cover art 
* Supports AIFF, WAV, FLAC, MP3, AAC, and OGG files as input
* MP3s are encoded to V0
* Paths to the tools are hard coded
* Number of concurrent threads is hard coded at 8
* Files are copied and converted atomatically, so don't worry about killing the script in the middle
* On linux, it seems to die randomly because it can't open an output pipe on one of the shell commands. Just restart it and it will continue where it left off.

## Todos
* Add replaygain support (copy the replaygain tag if it exists, or calculate it if it doesn't)
* Support more tags
* Update existing tags when file exists if tags are different
* Figure out the correct tag name for energy level
* Add ability to remove files from output directory that don't exist in the input directory
* Support more lame encoder options
* Support more output formats
* Don't hard code paths
* Add ability to view LAME status output
* Fix "fatal error: Could not open pipe file handles: file Foundation/NSFileHandle.swift, line 336" on linux
