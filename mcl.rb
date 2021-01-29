#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'net/http'
require 'nokogiri'
require 'rainbow'

require 'pry'
require 'pp'

# constants
IOS_MEDIATION = "https://github.com/mopub/mopub-ios-mediation"
AOS_MEDIATION = "https://github.com/mopub/mopub-android-mediation"

CHANGE_LOG_AOS_BASE_URL = "https://github.com/mopub/mopub-android-mediation/blob/master/"
CHANGE_LOG_IOS_BASE_URL = "https://github.com/mopub/mopub-ios-mediation/blob/master/"
CHANGE_LOG_FILE_NAME = "/CHANGELOG.md"


def getChangeLogUrls()
  available_networks = getAvailableNetworks()
  change_log_urls = {}

  available_networks.each do |platform, networks|
    networks.each do |network|
      change_log_url = platform == :ios ? CHANGE_LOG_IOS_BASE_URL + network : CHANGE_LOG_AOS_BASE_URL + network
      change_log_url += CHANGE_LOG_FILE_NAME

      if change_log_urls[platform].nil? 
        change_log_urls[platform] = { network.downcase.to_sym => change_log_url }
      else
        change_log_urls[platform][network.downcase.to_sym] = change_log_url
      end
    end
  end

  return change_log_urls
end

def getAvailableNetworks()
	ios_uri = URI(IOS_MEDIATION)
	aos_uri = URI(AOS_MEDIATION)
	
	available_networks_ios = []
	available_networks_aos = []

	html_ios = ""
	html_aos = ""

	Net::HTTP.start("github.com", 443, :use_ssl => true) do |http|
		request = Net::HTTP::Get.new ios_uri
		response = http.request request # Net::HTTPResponse object
		html_ios = response.body

		request = Net::HTTP::Get.new aos_uri
		response = http.request request # Net::HTTPResponse object
		html_aos = response.body
	end

	doc_ios = Nokogiri::HTML(html_ios)
	doc_aos = Nokogiri::HTML(html_aos)

	doc_ios.css("a[title][href*='/tree/master/']").each do |link|
		if link.content.start_with?(/[A-Z]/)
			available_networks_ios.push(link.content)
		end
	end

	doc_aos.css("a[title][href*='/tree/master/']").each do |link|
		if link.content.start_with?(/[A-Z]/)
      available_networks_aos.push(link.content) unless link.content == "Testing"
		end
	end

	return { :aos => available_networks_aos, :ios => available_networks_ios }
end

# uri = URI(IOS_MEDIATION)
# uri = URI(AOS_CHANGE_LOG_URLS[:AdColony])

# html_response = ""

# Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
#   request = Net::HTTP::Get.new uri
#   response = http.request request # Net::HTTPResponse object
#   html_response = response.body
# end

# doc = Nokogiri::HTML(html_response)

# version list
# doc.css("[id=readme] ul li p").each do |link|
# puts link
#   # puts link.content
# end

# version list
# doc.css("[id=readme] ul ul li").each do |li_object|
# 	content = li_object.content

# 	if content.include? "5.13"
# 		# puts content
# 		puts li_object.parent.parent.content
# 	end
	
# end

# doc.css("a[title][href*='/tree/master/']").each do |link|
# puts link
#   # puts link.content
# end

# result = doc.xpath("//div[@class='df-block-raw']/pre[@class='df-raw']/text()").to_html.split("\n")


options = {}

oparser = OptionParser.new do |opts| 
	opts.banner = "Usage: mcl.rb [options]"
	opts.version = "1.0"

	# required (if desc is all capital)
	opts.on("-n", "--network NETWORK_NAME", String, "specify network case insensitive") do |value|
		# -n list, available, networks
		# -n all
		options[:network] = value.downcase
	end
	
	opts.on("-p", "--platform PLATFORM", String, "ios/aos/unity available") do |value|
		options[:platform] = value.downcase
	end

	opts.on("-m", "--minimum MIN_SDK_VERSION", "minimum mopub sdk version") do |value|
		options[:sdk] = value
	end

	opts.on("-a", "--available", "show available networks") do |value|
		# show available network list both ios/aos
		networks = getAvailableNetworks()
		networks.each do |key, value|
			puts Rainbow(key).blue.bright.underline
			puts value
		end
		
		exit
	end

	# opts.on("-l") do |value|
	# 	options[:latest] = true
	# end

	opts.on("-h", "--help", "show available options") do |value|
		puts oparser
		exit
	end

	opts.on("-v", "--version", "show script version") do |value|
		puts opts.version
		exit
	end
end

# parse options, [To-Do] add exception missing argument
oparser.parse!

# [TEMP] print options
puts options



# main logic starts here

# get get change logs links
change_log_urls = getChangeLogUrls()



change_log_urls.each do |platform, network_urls|
  network_urls.each do |network, url|
    if options[:network] == network.to_s
      puts network, url
    end
  end
end


