#!/usr/bin/ruby
#
# RSDownloader - A small script to easily download files from http://rapidshare.com
# Copyright (c) 2009 Renaud "Rhino" Bourassa <To.Rhino@gmail.com>
#
Version = 0.1
#
# Usage:   Pass a list, separated by spaces, of links and/or files of links of the files 
#          you want to download as argument. Each links in a file of links must be
#          seperated by a newline character. Use the "-h" option to see all other
#          options.
#
# Depend.: ruby, wget
#
# Example: ./rsdownloader.rb --dir=/home/user/Downloads http://rapidshare.com/files/12341234/example.rar

# ----------------------------------------------------------
# CONFIGURATION
# ----------------------------------------------------------

USERAGENT  = "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.8) Gecko/2009033017 GranParadiso/3.0.8"
DIRECTORY  = "/home/rhino/Downloads"
VERBOSE    = true

# ----------------------------------------------------------
# DOWNLOAD SCRIPT
# ----------------------------------------------------------

require 'uri'
require 'net/http'
require 'optparse'
require 'ostruct'

#RSDownload objects represents a single download from RapidShare
class RSDownload
  attr_accessor :url, :dir, :name, :header

  #Create a new instance of RSDownload
  def initialize(url,dir,header)
    @url = url
    @dir = dir
    @header = header
  end

  #Test if the given URL is valid and operational
  def test
    return Net::HTTP.get_response(URI.parse(url)).body.include?("<h1>FILE DOWNLOAD</h1>")
  end

  #Execute the download of the RSDownload object
  def download
    wait = 0
    url = URI.parse(@url)

    http = Net::HTTP.new(url.host)
    response = http.request_get(url.path,@header)
    url = URI.parse(/<form id="ff" action="(.+)" method="post">/.match(response.body)[1])

    http = Net::HTTP.new(url.host)
    data = "dl.start=Free"
    response = http.request_post(url.path,data,@header)
    while wait = /Or try again in about (.+) minutes\./.match(response.body) do
      self.wait(wait[1].to_i*60,"The next download will start in approximately %H:%M:%S")
      response = http.request_post(url.path,data,@header)
    end
    url = URI.parse(/<input checked type="radio" name="mirror" onclick="document.dlf.action=\\'(.+)\\';" \/>/.match(response.body)[1])
    wait = /var c=(.+);/.match(response.body)[1].to_i

    self.wait(wait,"The download will start in %H:%M:%S")

    cmd = "wget -c --user-agent=\"#{@header['User-Agent']}\""
    cmd += " -q" if !$verbose
    cmd += " --directory-prefix=\"#{@dir}\"" if @dir

    IO.popen(cmd + " #{url}"){|f|} 
  end

  #Wait a certain time and display a counter
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

#Rapidshare objects represent a full download session
class RapidShare

  #Create a new instance of RapidShare
  def initialize(options)
    @options = options
    @files = []
    @dir = options.directory
    @header = {
      'User-Agent' => options.useragent
    }
    $verbose = @options.verbose
  end

  #Start the download session
  def start
    $stdout = File.new('/dev/null', 'w') if !$verbose
    puts ":: Initializing the download session..."
    puts "Setting the download directory to: #@dir"
    if @options.files.length == 1
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

    self.download
  end

  #Load the downloads in memory
  def load
    @options.files.each do |file|
      if file =~ /http:\/\/(.+)/
        rsd = RSDownload.new(file,@dir,@header)
        if rsd.test
          puts "  #{rsd.url}...Ok"
          @files << rsd
        else
          puts "  #{rsd.url}...Failed"
        end
      elsif File.exist?(file)
        File.open(file,"r") do |f|
          while url = f.gets
            rsd = RSDownload.new(url.delete("\n"),@dir,@header)
            if rsd.test
              puts "  #{rsd.url}...Ok"
              @files << rsd
            else
              puts "  #{rsd.url}...Failed"
            end
          end
        end
      end
    end
    begin
      raise "None of the files are valid" if @files.empty?
    rescue => err
      STDERR.puts err
      exit 1
    end
  end

  #Execute the downloads
  def download
    @files.each do |f|
      f.download
    end
  end
end

#This class hold the arguments parsing information
class OptParser

  #Parse the command-line arguments
  def self.parse(args)
    options = OpenStruct.new
    if VERBOSE.nil?
      options.verbose = true
    else
      options.verbose = VERBOSE
    end
    if USERAGENT.nil?
      options.useragent = "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.8) Gecko/2009033017 GranParadiso/3.0.8"
    else
      options.useragent = USERAGENT
    end
    if DIRECTORY.nil?
      options.directory = Dir.pwd
    else
      options.directory = DIRECTORY
    end
    
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: rapidshare.rb [OPTION] FILES"
      
      opts.separator ""
      opts.separator "Options:"

      opts.on("-v", "--[no-]verbose=[FLAG]", "Toggle the output. Default is on.") do |v|
        options.verbose = v
      end

      opts.on("-d", "--dir=PATH", "Set the download directory. Default is current directory.") do |d|
        options.directory = d
      end

      opts.on("-u", "--user-agent=STRING", "Set the User-Agent for the requests.") do |u|
        options.useragent = u
      end

      opts.on_tail("-h", "--help", "Show this message.") do
        puts opts
        exit
      end

      opts.on_tail("--version", "Show version") do
        puts "RSDownloader #{Version}"
        exit
      end

      begin files = opts.parse!(args)
        if(files.length < 1)
          raise OptionParser::InvalidArgument.new("You must specify at least one file.")
        else
          options.files = files
        end
      rescue OptionParser::ParseError => err
        STDERR.puts err
        puts opts
        exit 1
      end
    end

    return options
  end
end

#The main program, it creates a download session and execute it
rs = RapidShare.new(OptParser.parse(ARGV))
rs.start

