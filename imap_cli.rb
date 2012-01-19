#!/usr/bin/env ruby

require 'rubygems'
require 'net/imap'
require 'mail'
require 'tmail'

$DEBUG = false

$CONFIG = {
  :host     => 'imap.gmail.com',
  :username => 'fred900rbc@gmail.com',
  :password => 't0utate2',
  :port     => 993,
  :ssl      => true
}

class MyImap < Net::IMAP
  def initialize(config)
    super(config[:host], config[:port], config[:ssl])
    @result = Hash.new
    @config = config
    self.login(config[:username], config[:password])
    self.select('INBOX')

    rescue SocketError, SystemCallError, Net::IMAP::Error, IOError,
	   OpenSSL::SSL::SSLError => e
      raise "IMAP error (class #{e.class.name}: #{e.message.inspect} " +
            "(server: " + @config[:host] + ":" + @config[:port].to_s + ")"
  end

  def treat_multi_part(parts, seqno)
    if not parts.disposition.nil?
      if ($DEBUG)
        puts parts.disposition
        puts "+++++++++++++++++"
      end
      mail = TMail::Mail.parse(self.fetch(seqno, 'RFC822')[0].attr['RFC822'])
      #puts mail
      if not mail.attachments.blank?
        filename = mail.attachments.first.original_filename
        @result[seqno]['attachments'].push(Hash.new)
	length = @result[seqno]['attachments'].length
	@result[seqno]['attachments'][length - 1].store('filename', filename)
        File.open($DIRECTORY + '/' + filename,"w+") { |local_file|
          local_file << mail.attachments.first.gets(nil)
        } 
        @result[seqno]['attachments'][length - 1].
	              store('path', File.expand_path($DIRECTORY + '/' +
		                                     filename))
      end
    end
  end

  def collect_data
    #self.search(['ALL']).each do |seqno|
    #self.search(['RECENT']).each do |seqno|
    self.search(['NOT', 'SEEN']).each do |seqno|
      if ($DEBUG)
        puts "not seen:#{seqno}"
      end
      # Store the message seqno in the hash result
      @result.store(seqno, Hash.new)
      @result[seqno].store('id', seqno)
      @result[seqno].store('urls', Array.new)
      @result[seqno].store('attachments', Array.new)
      if ($DEBUG)
        puts "------------------------------------------------------"
        # fetch the envelope
        envelope = self.fetch(seqno, 'ENVELOPE')[0].attr['ENVELOPE']
        puts "Envelope:"
        p envelope

        # from field
        from = envelope.from[0]
        puts "From: " + from.mailbox + "@" + from.host

        # subject field
        puts "subject: " + Mail::Encodings.value_decode(envelope.subject)
      end
      # fetch the body structure
      bodyStruct = self.fetch(seqno, 'BODYSTRUCTURE')[0].attr['BODYSTRUCTURE']

      # retrieve the body as text
      body = self.fetch(seqno, 'BODY[TEXT]')[0].attr['BODY[TEXT]']

      # This is a regexp to mach a URL 
      regexp = /(ftp|https?):\/\/[-\w]+(\.\w[-\w]*)+(:\d+)?(\/)?
               [^=!.,?;"'<>()\[\]\s\x7F-\xFF]*/xi
      decoded_body = Mail::Encodings.value_decode(body)
      # Split the decoded body in strings to be matched with the URL regex
      decoded_body.split.each do |str|
        url = regexp.match(str)
        if not url.nil?
	  if ($DEBUG)
            puts "url: #{url}"
	  end
          @result[seqno]['urls'].push(url)
        end
      end
      # Let's have a look to the body structure
      case bodyStruct
      when Net::IMAP::BodyTypeBasic
        if ($DEBUG)
          puts "BodyType: Basic"
	end
      when Net::IMAP::BodyTypeText
        if ($DEBUG)
          puts "BodyType: Text"
	end
      when Net::IMAP::BodyTypeMessage
        if ($DEBUG)
          puts "BodyType: Message"
	end
      when Net::IMAP::BodyTypeMultipart
        if ($DEBUG)
          puts "BodyType: Multipart"
	  puts "#################################"
	end
        bodyStruct.parts.each do |parts|
	  self.treat_multi_part(parts, seqno)
	end
      end
      self.store(seqno, "+FLAGS", [:Seen])
    end  
    rescue SocketError, SystemCallError, Net::IMAP::Error, IOError,
           OpenSSL::SSL::SSLError => e
      raise "IMAP error (class #{e.class.name}: #{e.message.inspect} " +
            "(server: " + @config[:host] + ":" + @config[:port].to_s + ")"
  end

  def dump_result
    puts "["
    result_len = @result.length
    # display each message object
    @result.keys.sort.each do |seqno|
      puts "\t{"
      # number of messages
      #result_len = result_len - 1
      result_len -= 1
      # display the id
      puts "\t\t\"id\": #{@result[seqno]['id']},"
      # display the urls found
      puts "\t\t\"urls\":"
      print "\t\t\t["
      urls_len = @result[seqno]['urls'].length;
      if (urls_len == 0)
	  puts "]"
      else
          puts
      end
      0.upto(urls_len - 1) do |j|
        print "\t\t\t\t\{ \"url\": \"#{@result[seqno]['urls'][j]}\" }"
	if (j != urls_len - 1)
	  puts ", "
	else
	  puts
	end
      end
      if (urls_len != 0)
	  puts "\t\t\t]"
      end
      # display the attachments found
      puts "\t\t\"attachments\":"
      print "\t\t\t{"
      attachments_len = @result[seqno]['attachments'].length;
      if (attachments_len == 0)
	  puts "}"
      else
          puts
      end
      0.upto(attachments_len - 1) do |j|
	puts "\t\t\t\t{ \"filename\": \"#{@result[seqno]['attachments'][j]['filename']}\" },"
	puts "\t\t\t\t{ \"path\": \"#{@result[seqno]['attachments'][j]['path']}\" }"
	if (j != attachments_len - 1)
	  puts ", "
	else
	  puts
	end
      end
      if (attachments_len != 0)
	  puts "\t\t\t}"
      end
      if (result_len != 0)
        puts "\t},"
	next
      end
      puts "\t}"
    end
    puts "]"
  end
end

unless ARGV.length < 2
  puts "Usage: #{ARGV[0]} [download directory]}"
  exit
end
if ARGV.length == 1
  $DIRECTORY = ARGV[0]
else
  time = Time.new
  $DIRECTORY = "#{time.year}" + '-' + "#{time.month}" + '-' + "#{time.day}" +
               '-' + "#{time.hour}" + "#{time.min}" + "#{time.sec}"
end
if File.exist?($DIRECTORY)
  puts "Error: #{$DIRECTORY} already exists... exiting"
  exit
end
Dir.mkdir($DIRECTORY)
imap = MyImap.new($CONFIG)
imap.collect_data
imap.dump_result
