#!/usr/bin/ruby
#
# RSDownloader - a small script to easily download files from filehosting websites.
# Copyright 2009 Renaud Bourassa <To.Rhino@gmail.com>
#
Version = "0.2.0"
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# ----------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------

# Your filestube API key (Required for search)
FTKEY = nil

# The user-agent for the requests (Default is Wget)
USERAGENT = nil         

# The download directory (Default is pwd)
DIRECTORY = nil

# Toggle the output (Default is true)
VERBOSE = nil

# ----------------------------------------------------------
# RSDOWNLOADER
# ----------------------------------------------------------

require 'uri'
require 'cgi'
require 'net/http'
require 'optparse'
require 'ostruct'
require 'rexml/document'

# The Download superclass
class Download
  attr_accessor :url, :name

  # Initializes a download
  def initialize(url, opts)
    @url = url
    @opts = opts
    @file = nil
  end

  # Tests the url
  def test
    begin
      Net::HTTP.get_response(URI.parse(url)).value
    rescue
      return false
    end
    return true
  end

  # Executes the download
  def execute
    self.set_file
    self.download
  end

  # Sets the file for the download
  def set_file
    @file = @url
  end

  # Downloads the file
  def download
    cmd = "wget -c --user-agent=\"#{@opts[:header]['User-Agent']}\""
    cmd += " -q" if !$verbose
    cmd += " --directory-prefix=\"#{@opts[:dir]}\"" if @opts[:dir]
    
    IO.popen(cmd + " #{@file}"){|f|} 
  end
end

# RapidShareDownload objects represents a single download from rapidshare.com
class RapidShareDownload < Download

  # Tests if the given URL is valid and operational
  def test
    begin
      Net::HTTP.get_response(URI.parse(url)) do |r|
        r.value
        raise unless r.body.include?("<h1>FILE DOWNLOAD</h1>")
      end
    rescue
      return false
    end
    return true
  end

  # Sets the file for the download and display the wait times
  def set_file
    wait = 0
    url = URI.parse(@url)

    Net::HTTP.start(url.host) do |http|
      response = http.request_get(url.path,@opts[:header])
      result = /<form id="ff" action="(.+)" method="post"/.match(response.body)
      url = URI.parse(result[1])
    end

    Net::HTTP.start(url.host) do |http|
      data = "dl.start=Free"
      response = http.request_post(url.path,data,@opts[:header])

      while wait = /about (.+) minutes/.match(response.body) do
        self.wait(wait[1].to_i*60,
                  "The next download will start in approximately %H:%M:%S")
        response = http.request_post(url.path,data,@opts[:header])
      end

      result = /<input checked type="radio" name="mirror" onclick="document.dlf.action=\\'(.+)\\';" \/>/.match(response.body)
      url = URI.parse(result[1])

      wait = /var c=(.+);/.match(response.body)[1].to_i
    end

    self.wait(wait,"The download will start in %H:%M:%S")

    @file = url
  end

  # Waits a certain time and display a counter
  def wait(time,message)
    t = Time.at(time-68400)
    $stdout.sync = true
    time.downto(0) do
      print "\r" + t.strftime(message)
      sleep 1
      t -= 1
    end
    print "\r" + " " * message.length + "\r"
    $stdout.sync = false
  end
end

# FilesTubeDownload objects represents a single download from filestube.com
class FilesTubeDownload < Download

  # Initializes the download by fetching the real url
  def initialize(url,opts)
    @url = url
    @opts = opts

    unless url =~ /go\.html/
      response = Net::HTTP.get_response(URI.parse(url))
      result = /class="gobut" href="(.+)" title="Download Now!"/.match(response.body)
      if result
        @url = result[1]
      else
        raise "Invalid URL"
      end
    end

    response = Net::HTTP.get_response(URI.parse(@url))
    result = /<iframe style="width: 99%;height:80%;margin:0 auto;border:1px solid grey;" src="(.+)" scrolling="auto" id="iframe_content">/.match(response.body)

    if result
      @download = init_download(result[1])
    else
      raise "Invalid URL"
    end
  end

  # Initiates the actual download
  def init_download(url)
    case url
    when /rapidshare\.com/
      return RapidShareDownload.new(url,@opts)
    else
      raise "Website not supported"
    end
  end

  # Tests the actual url
  def test
    @download.test
  end
  
  # Executes the actual download
  def execute
    @download.set_file
    @download.download
  end
end

# Downloader objects represent a full download session
class Downloader

  # Creates a new downloader session and initializes it
  def initialize(opts)
    @opts = opts
    @files = []
    header = {
      'User-Agent' => opts.useragent
    }
    @download_opts = {
      :dir    => opts.directory,
      :header => header
    }
    $verbose = @opts.verbose
  end

  # Starts the download session
  def start
    $stdout = File.new('/dev/null', 'w') unless $verbose

    puts ":: Initializing the download session..."
    puts "Setting the download directory to: #{@opts.directory}"

    if @opts.input.length == 1
      puts "Testing the file:"
    else
      puts "Testing the files:"
    end

    self.load

    if @files.length == 1
      puts ":: Starting the download..."
    else
      puts ":: Starting the downloads..."
    end

    self.execute
  end

  # Loads the downloads
  def load
    @opts.input.each do |file|
      if file =~ /http:\/\/(.+)/
        begin
          d = init_download(file)
        rescue
          next
        end

        if d.test
          puts "  #{d.url}...Ok"
          @files << d
        else
          puts "  #{d.url}...Failed"
        end

      elsif File.exist?(file)
        File.open(file,"r") do |f|
          while url = f.gets
            begin
              d = init_download(url.delete("\n"))
            rescue
              next
            end
            
            if d.test
              puts "  #{d.url}...Ok"
              @files << d
            else
              puts "  #{d.url}...Failed"
            end
          end
        end
      end
    end
    
    raise "None of the files are valid" if @files.empty?
  end

  # Initializes a download based on its URL
  def init_download(url)
    case url
    when /rapidshare\.com/
      return RapidShareDownload.new(url,@download_opts)
    when /filestube\.com/
      return FilesTubeDownload.new(url,@download_opts)
    else
      raise "Website not supported"
    end
  end

  # Executes the downloads
  def execute
    @files.each do |f|
      f.execute
    end
  end
end

# Finder objects represent a full search session
class Finder

  # Creates a new search session
  def initialize(opts)
    @key = opts.ftkey
  end

  # Searches for a certain keyphrase
  def search(keyword,extension=nil)
    print ":: Searching for #{keyword}"
    print " (.#{extension})" if extension
    puts "..."

    url = "http://api.filestube.com/?key=#@key"
    url += "&phrase=#{CGI::escape(keyword)}"
    url += "&extension=#{CGI::escape(extension)}" if extension
    
    xml = REXML::Document.new(request(url))
    raise xml.root.elements[1].text if xml.root.name == "error"
      
    nb = nb_results(xml)
    
    if nb == 0
      puts "No results found"
      return
    elsif nb > 1
      puts "#{nb} results found"
    else
      puts "#{nb} result found"
    end
    
    page = 0
    
    begin
      page += 1
      xml = REXML::Document.new(request(url + "&page=#{page}"))
      raise xml.root.elements[1].text if xml.root.name == "error"
      parse_results(xml)
      break if page > nb/10
    end while(more?)
  end
  
  # Makes a search request to filestubes
  def request(url)
    response = Net::HTTP.get_response(URI.parse(url))
    response.value

    return response.body
  end

  # Extracts the number of results return
  def nb_results(xml)
    if xml.root.elements['hasResults'].text.to_i != 0
      return nb_results = xml.root.elements['results/hitsTotal'].text.to_i
    else
      return 0
    end
  end
  
  # Parses and displays the results
  def parse_results(xml)
    results = xml.root.elements.each('results/hits') do |d|
      print d.elements['size'].text + " - "
      print d.elements['name'].text + " - "
      print d.elements['address'].text
      puts ""
    end
  end

  # Asks for more results
  def more?
    print "More results? [Y/n] "
    answer = STDIN.gets

    if answer.chomp == 'Y'
      return true
    else
      return false
    end
  end
end

# The main program class
class RSDownloader
  
  # Creates a new instance of RSDownloader
  def initialize
    @opts = parse(ARGV)
    execute
  end

  # Execute an instance of RSDownloader
  def execute
    case @opts.mode
    when "download"
      d = Downloader.new(@opts)
      d.start
    when "search"
      f = Finder.new(@opts)
      f.search(@opts.input[0])
    end
  end

  # Parses the command-line arguments
  def parse(args)
    opts = OpenStruct.new

    opts.mode      = "download"
    opts.verbose   = VERBOSE   ? VERBOSE   : true
    opts.useragent = USERAGENT ? USERAGENT : "Wget"
    opts.directory = DIRECTORY ? DIRECTORY : Dir.pwd
    opts.ftkey     = FTKEY

    mode = false
    
    o = OptionParser.new do |o|
      o.banner = "Usage: rapidshare.rb [MODE] [OPTIONS] INPUT"
      
      o.on("-h", "--help", "Show this message") do
        puts o
        exit(0)
      end

      o.on("-V", "--version", "Show version") do
        puts "RSDownloader #{Version}"
        exit(0)
      end

      o.separator " "
      o.separator "Mode:"
      
      o.on("-d", "--download", 
           "Set the mode to download. Default to",
           "this mode") do
        if mode 
          raise OptionParser::InvalidArgument.new("You can't specify more than one mode")
        else
          opts.mode = "download"
          mode = true
        end
      end

      o.on("-s", "--search", 
           "Set the mode to search") do
        if mode 
          raise OptionParser::InvalidArgument.new("You can't specify more than one mode")
        else
          opts.mode = "search"
          mode = true
        end
      end

      o.separator " "
      o.separator "Options:"

      o.on("-v", "--[no-]verbose=[FLAG]", 
           "Toggle the output") do |v|
        opts.verbose = v
      end

      o.on("-D", "--dir=PATH", 
           "Set the download directory. Default to",
           "present working directory") do |d|
        opts.directory = d
      end

      o.on("-u", "--user-agent=STRING", 
           "Set the User-Agent for the requests") do |u|
        opts.useragent = u
      end

      o.on("--filestubekey=STRING", 
           "Set the filestube API key for the searches.",
           "Required to use the search mode") do |k|
        opts.ftkey = k
      end

      begin input = o.parse!(args)
        if(opts.mode == "download")
          if input.length < 1
            raise OptionParser::InvalidArgument.new("You must specify at least one file")
          end
        elsif(opts.mode == "search")
          if input.length != 1
            raise OptionParser::InvalidArgument.new("You must specify one keyphrase")
          elsif opts.ftkey.nil?
            raise OptionParser::MissingArgument.new("You must specify a filestube API key")
          end
        end
        opts.input = input
      rescue OptionParser::ParseError => err
        STDERR.puts err
        puts o
        exit(1)
      end
    end

    return opts
  end
end

# The main program
begin
  RSDownloader.new
rescue Interrupt => err
  STDERR.puts "\nInterrupt signal received"
rescue SystemExit => err
  
rescue Exception => err
  STDERR.puts err
  exit(1)
end
