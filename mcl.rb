#!/usr/bin/env ruby

require 'optparse'
require 'net/http'
require 'nokogiri'
require 'rainbow'
require 'word_wrap'
require 'terminal-table'

IOS_MEDIATION = "https://github.com/mopub/mopub-ios-mediation"
AOS_MEDIATION = "https://github.com/mopub/mopub-android-mediation"

CHANGE_LOG_AOS_BASE_URL = "https://github.com/mopub/mopub-android-mediation/blob/master/"
CHANGE_LOG_IOS_BASE_URL = "https://github.com/mopub/mopub-ios-mediation/blob/master/"
CHANGE_LOG_FILE_NAME = "/CHANGELOG.md"

MIN_NETWORK_NAME_CHAR = 3
NUMBER_OF_LOGS_TO_PRINT = 10
BULLET_CHAR = "-"
WORD_WRAP_COUNT = 60

CMD_EXAMPLES = %Q[
# Show Facebook iOS change logs
  $ mcl -n facebook -p ios

# Show only the latest logs from all networks for both iOS and Android
  $ mcl -l 1

# Show all available networks
  $ mcl -n all

# Show Pangle Android change logs for MoPub SDK 5.13 certified 
  $ mcl -n pangle -p aos -v 5.13
].strip

def getChangeLogUrls(available_networks)
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
  begin
    Net::HTTP.start("github.com", 443, :use_ssl => true) do |http|
      urls.each do |key, url|
        uri = URI(url)
        request = Net::HTTP::Get.new uri
        response = http.request request
        content[key] = response.body
      end
    end
  rescue => e
    # Exit script if there is a http error
    puts "Error: #{e.message}"
    exit
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
    result_after = each_msg.match(/(?:mopub).*[^0-9]([4-7]\.[0-9](?:[0-9])?\.[0-9])[^0-9]?.*/i)

    # See if the message includes SDK version before "MoPub". ex) 5.14.1 MoPub
    result_before = each_msg.match(/.*[^0-9]([4-7]\.[0-9](?:[0-9])?\.[0-9])[^0-9]?.*(?:mopub)/i)

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
  final = ""

  messages.each do |msg|
    # For first and second level, use - only. Otherwise increase the number of dash
    if not msg.kind_of? Array
      if dash == "" || dash == BULLET_CHAR
        # puts %Q[ #{Rainbow(BULLET_CHAR + ">").green.bright} #{WordWrap.ww(msg, 150)}]
        # final += %Q[ #{Rainbow(BULLET_CHAR + ">").bright} #{WordWrap.ww(msg, WORD_WRAP_COUNT)}]
        final += %Q[#{BULLET_CHAR}> #{WordWrap.ww(msg, WORD_WRAP_COUNT)}]
      else
        # puts %Q[ #{Rainbow(dash + ">").green.bright} #{WordWrap.ww(msg, 150)}]
        # final += %Q[ #{Rainbow(dash + ">").bright} #{WordWrap.ww(msg, WORD_WRAP_COUNT)}]
        final += %Q[#{dash}> #{WordWrap.ww(msg, WORD_WRAP_COUNT)}]
      end
    else
      return final + printMessages(msg, dash + BULLET_CHAR)  
    end
  end

  return final
end

def printChangeLogs(change_logs, filter)
  number_of_logs_to_print = filter[:num_of_logs] == nil ? NUMBER_OF_LOGS_TO_PRINT : filter[:num_of_logs]
  sdk_version = filter[:sdk_version] == nil ? "0" : createVersionObj(filter[:sdk_version])

  change_logs.each do |platform, logs|
    puts Rainbow(platform.upcase).yellow.underline.bright

    number_of_printed_logs = 0

    # Test
    rows = []
    table = Terminal::Table.new do |t|
      t.headings = ["Adapter", "Certified SDK", "Network SDK", "Change Logs"] 
      t.rows = rows
      t.style = {:all_separators => true }
    end

    logs.each do |each_adapter_log|
      # Version filtering
      if sdk_version != "0"
        certified_sdk_version = createVersionObj(each_adapter_log[:certified_sdk_version])
        if certified_sdk_version != sdk_version 
          next
        end
      end

      # Formatting
      adapter_version_colored = Rainbow(each_adapter_log[:version]).red.bright
      sdk_version_colored = Rainbow(each_adapter_log[:certified_sdk_version]).bright.blue

      hello = each_adapter_log[:version].split(".")
      hello.pop()
      network_sdk_version_colored = Rainbow(hello.join(".")).green

      # puts %Q[#{adapter_version_colored} #{sdk_version_colored}]
      # printMessages(each_adapter_log[:logs])

      # temp = adapter_version_colored + " " + sdk_version_colored + "\n" + printMessages(each_adapter_log[:logs])
      columns = []
      columns.push(adapter_version_colored)
      columns.push(sdk_version_colored)
      columns.push(network_sdk_version_colored)
      columns.push(printMessages(each_adapter_log[:logs]))
      # columns.push(temp)

      table.add_row columns

      number_of_printed_logs += 1
      number_of_printed_logs == number_of_logs_to_print ? break : next
    end

    puts table


  end  
end


def createVersionObj(version_string)
  begin
     return Gem::Version.new(version_string)
  rescue ArgumentError
     return Gem::Version.new("")
  end
end


def findMatchingNetwork(input_network, network_list)
  matched = false

  network_list.each do |network|
    matching_result = network.match(/(#{input_network})/i)
    if matching_result.nil?
      next
    elsif matching_result.captures.first.downcase == "network"
      next
    else
      matched = network
      break
    end
  end

 return matched == false ? false : matched 
end

# global variables
options = {}
available_networks = {}

oparser = OptionParser.new do |opts| 
	opts.banner = "Usage: mcl.rb [options]"
  opts.version = "1.0.0"

	# Network
  opts.on("-n", "--network NETWORK", String, "Network name for change logs. Use 'all' to see available networks") do |value|
    value.strip!
    if value.length < MIN_NETWORK_NAME_CHAR
      puts "Entered network does not exist. Use 'all' to see available networks"
      exit
    end
    available_networks = getAvailableNetworks()
    if value == "all"
      available_networks.each do |key, value|
        puts Rainbow(key.upcase).blue.bright.underline
        puts value
      end
      exit
    end
    network = findMatchingNetwork(value, (available_networks[:ios] + available_networks[:aos]).uniq)
    if network
      options[:network] = network.downcase
    else
      puts "Entered network does not exist. Use 'all' to see available networks"
      exit
    end
	end

  # MoPub SDK version
  opts.on("-v", "--sdk_version SDK_VERSION", "Show change logs certified with specified MoPub SDK only") do |value|
    sdk_version = value.match(/([4-7]\.[0-9](?:[0-9])?(?:\.[0-9])?)/)
    if sdk_version == nil 
      puts "SDK version is not in the right format. Example: 5.16 or 5.15.1"
      exit
    else
      options[:sdk] = sdk_version.captures.first
    end
	end

  # Platform  
  opts.on("-p", "--platform PLATFORM", String, "Choose platform. 'ios' or 'aos' case insensitive") do |value|
    value.downcase!
    if not ["ios", "aos"].include? value
      puts %Q[You can only enter "iOS" or "AOS" (case insensitive)]
      exit
    end
		options[:platform] = value.downcase
	end

  # Number of logs
  opts.on("-l", "--logs NUMBER_OF_LOGS", "Number of logs to print. Default #{NUMBER_OF_LOGS_TO_PRINT}. Outputs from the latest") do |value|
    options[:num_of_logs] = value.to_i
  end


	opts.on("-e", "--example", "Show command examples") do |value|
    puts CMD_EXAMPLES
		exit
	end

	opts.on("-h", "--help", "Print help message") do |value|
		puts oparser
		exit
	end
end

# parse options, [To-Do] add exception missing argument

begin
  oparser.parse!
rescue OptionParser::MissingArgument, OptionParser::InvalidOption => e
  puts "Error: #{e.message}"
  exit
end


# [TEMP] print options
puts "entered options"
puts options


# main logic starts here

# -n is mandantory, if not then dont run this
# get get change logs links
change_log_urls = getChangeLogUrls(available_networks)

target_network_urls = change_log_urls.each_with_object({}) do |(platform, network_urls), target_urls|
  # Check the platform entered
  if options[:platform] == platform.to_s || options[:platform].nil?
    network_urls.each do |network, url|
      if options[:network] == network.to_s
        target_urls[platform] = url
      end
    end
  end 
end

changelog_htmls = getContentFromGitHub(target_network_urls)

parsed_change_logs = changelog_htmls.each_with_object({}) do |(platform, html), parsed_logs|
  parsed_logs[platform] = parseChangeLogHtml(html)
end

printChangeLogs(parsed_change_logs, { :num_of_logs => options[:num_of_logs], :sdk_version => options[:sdk] })
