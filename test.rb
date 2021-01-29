#!/usr/bin/env ruby

require 'optparse'
require 'json'
require 'net/http'
require 'nokogiri'
require 'rainbow'
require 'active_support/core_ext/hash/conversions'

require 'pry'
require 'pp'

# constants
IOS_MEDIATION = "https://github.com/mopub/mopub-ios-mediation"
AOS_MEDIATION = "https://github.com/mopub/mopub-android-mediation"

CHANGE_LOG_AOS_BASE_URL = "https://github.com/mopub/mopub-android-mediation/blob/master/"
CHANGE_LOG_IOS_BASE_URL = "https://github.com/mopub/mopub-ios-mediation/blob/master/"
CHANGE_LOG_FILE_NAME = "/CHANGELOG.md"


NUMBER_OF_LOGS_TO_PRINT = 5

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

# Takes key and url, returns HTML contents
def getContentFromGitHub(urls)
  content = Hash.new
	Net::HTTP.start("github.com", 443, :use_ssl => true) do |http|
    urls.each do |key, url|
      uri = URI(url)
      request = Net::HTTP::Get.new uri
      response = http.request request
      content[key] = response.body
    end
	end
  return content
end



def getAvailableNetworks()
	available_networks_ios = []
	available_networks_aos = []

  contents = getContentFromGitHub({:ios => IOS_MEDIATION, :aos => AOS_MEDIATION })

	doc_ios = Nokogiri::HTML(contents[:ios])
	doc_aos = Nokogiri::HTML(contents[:aos])

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

def parseList(li) 
  if li.css("ul").length == 0
    return li.content.strip.gsub("\n", " ")
  end

  # If this is nested list, duplicate the list without nested list.
  if li.css("ul").length != 0
    li_duplicated = li.dup
    li_duplicated.css("ul").remove

    # Get the text at the li
    log_messages = [li_duplicated.content.strip.gsub("\n", " ")]

    # Travel through nested list
    nested_log_messages = li.css("ul > li").each_with_object([]) do |li, array|
      array.push(parseList(li))
    end

    return log_messages.push(nested_log_messages)
  end
end




def findCertifiedSDKVersion(change_logs) # array
  sdk_version = "Unknown"
  log_messages = change_logs.flatten
  log_messages.each do |each_msg|

    # See if it includes SDK version after "MoPub". ex) MoPub SDK 5.14.1
    result_after = each_msg.match(/(?:mopub).*[^0-9]([4-7]\.[1-2][0-9]\.[0-9])[^0-9]?.*/i)

    # See if the message includes SDK version before "MoPub". ex) 5.14.1 MoPub
    result_before = each_msg.match(/.*[^0-9]([4-7]\.[1-2][0-9]\.[0-9])[^0-9]?.*(?:mopub)/i)

    # If both have the version number, then take the after one. ex) MoPub SDK 5.14.1
    if result_after and result_before
      sdk_version = result_after.captures.first
      break
    elsif result_after and result_before.nil?
      sdk_version = result_after.captures.first
      break
    elsif result_after.nil? and result_before
      sdk_version = result_before.captures.first
      break
    end
  end

  return sdk_version
end


def parseChangeLogHtml(changelog_html)
  doc = Nokogiri::HTML(changelog_html)

  def compareAdapterVerAndFindCertifiedSDKVer(unknown_sdk_adapter_version, change_logs)
    change_logs.each do |each_log|
      if each_log[:certified_sdk_version] != "Unknown"
        adapter_version = createVersionObj(each_log[:version])
        certified_sdk_version = each_log[:certified_sdk_version]
        if unknown_sdk_adapter_version > adapter_version
          return certified_sdk_version
        end
      end
    end
    return "Unknown"
  end

  change_logs = doc.css("article > ul > li").each_with_object([]) do |nodes, array|
    # Adapter Version 
    version = nodes.css("p").first.content.strip

    # Log Messages (each li contents)
    logs = nodes.css("p + ul > li").each_with_object([]) do |li, array|
      array.push(parseList(li))
    end

    # Certified SDK version for this log
    certified_sdk_version = findCertifiedSDKVersion(logs)

    array.push({ :version => version, :logs => logs, :certified_sdk_version => certified_sdk_version })
	end

  # Find certified SDK version for the adapter that has version "Unknown"
  change_logs.each do |each_log|
    if each_log[:certified_sdk_version] == "Unknown"
      unknown_sdk_adapter_version = createVersionObj(each_log[:version])
      each_log[:certified_sdk_version] = compareAdapterVerAndFindCertifiedSDKVer(unknown_sdk_adapter_version, change_logs)
    end
  end
  
  return change_logs
end

def printMessages(messages, dash = "") 
  messages.each do |msg|
    # For first and second level, use - only. Otherwise increase the number of dash
    if not msg.kind_of? Array
      if dash == "" || dash == "-"
        puts %Q[ - #{msg}]
      else
        puts %Q[ #{dash} #{msg}]
      end
    else
      printMessages(msg, dash + "-")  
    end
  end
end

def printChangeLogs(change_logs, number_of_logs_to_print = NUMBER_OF_LOGS_TO_PRINT)
  change_logs.each do |platform, logs|
    puts Rainbow(platform.upcase).blue.bright.underline

    logs.each_with_index do |each_version, index|

      puts Rainbow(each_version[:version]).bright.yellow + " " + Rainbow(each_version[:certified_sdk_version]).bright.red

      log_messages = each_version[:logs]
      printMessages(log_messages)

      case number_of_logs_to_print
        when 0
          # Latest only
          break
        when index + 1
          break
        else
          next
      end

    end

  end  
end


def createVersionObj(version_string)
  begin
     return Gem::Version.new(version_string)
  rescue ArgumentError
     return Gem::Version.new("")
  end
end



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
	
	opts.on("-p", "--platform PLATFORM", String, "ios/aos available") do |value|
		options[:platform] = value.downcase
	end

  opts.on("-l", "--logs NUMBER_OF_LOGS", "Specify number of logs to print. It will print from the latest") do |value|
		options[:latest] = true
  end

	opts.on("-v", "--sdk_version SDK_VERSION", "minimum mopub sdk version") do |value|
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

	opts.on("-h", "--help", "show available options") do |value|
		puts oparser
		exit
	end

	# opts.on("-v", "--version", "show script version") do |value|
	# 	puts opts.version
	# 	exit
	# end
end

# parse options, [To-Do] add exception missing argument
oparser.parse!

# [TEMP] print options
puts options



# main logic starts here

# get get change logs links
change_log_urls = getChangeLogUrls()

target_network_urls = {}

change_log_urls.each do |platform, network_urls|
  # Check the platform entered
  if options[:platform] == platform.to_s || options[:platform].nil?
    network_urls.each do |network, url|
      if options[:network] == network.to_s
        target_network_urls[platform] = url
      end
    end
  end 
end

changelog_htmls = getContentFromGitHub(target_network_urls)


parsed_change_logs = {}

changelog_htmls.each do |platform, html|
  parsed_change_logs[platform] = parseChangeLogHtml(html)
end

if options[:latest]
  printChangeLogs(parsed_change_logs, 0)
else
  printChangeLogs(parsed_change_logs )
end

