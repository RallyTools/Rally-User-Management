require "base64"
require "rspec"
require File.dirname(__FILE__) + '/../lib/rally_user_helper.rb'
require File.dirname(__FILE__) + '/../lib/permissions_utility.rb'
require File.dirname(__FILE__) + '/../lib/multi_io.rb'
require File.dirname(__FILE__) + '/../lib/version.rb'
require 'csv'
require 'logger'

if !File.exists?(File.dirname(__FILE__) + "/test_configuration_helper.rb")
  puts ""
  puts "==="
  puts "ERROR"
  puts ""
  puts "You are missing a test/test_configuration_helper.rb file"
  puts ""
  puts "Copy example_test_configuration_helper.rb and put in your own values for testing"
  puts ""
  puts "==="
  puts ""
end

require File.dirname(__FILE__) + "/test_configuration_helper"

unless $LOAD_PATH.include?(File.dirname(__FILE__) + "/.." )
  $LOAD_PATH.unshift(File.expand_path("#{File.dirname(__FILE__)}/..") )
end

unless $LOAD_PATH.include?(File.dirname(__FILE__) + "/../lib/" )
  $LOAD_PATH.unshift(File.expand_path("#{File.dirname(__FILE__)}/../lib/") )
end

def create_logger(log_file_name)
  log_file = File.open(log_file_name, "a")
  logger = Logger.new(log_file)
  logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL
  return logger
end

def create_rally_connection(username, password, logger = nil, base_url = "https://rally1.rallydev.com/slm", wsapi_version = "v2.0")

  #==================== Making a connection to Rally ====================
  config                  = {:base_url => base_url}
  config[:username]       = username
  config[:password]       = password
  #config[:headers]        = headers #from RallyAPI::CustomHttpHeader.new()
  config[:version]        = wsapi_version

  if (logger)
    logger.info "Connecting to #{base_url} as #{username}..."
  end
  rally = RallyAPI::RallyRestJson.new(config)

  return rally
end

def has_permissions?(permissions, type, role, type_oid )
  exists = false
  permissions.each do |permission|
    if permission.Role == role && !permission[type].nil? && permission[type].ObjectID == type_oid
      exists = true
    end
  end
  return exists
end

def unique_name()
  return "#{Time.now.strftime('%m%d%H%M%S%L')}"
end

def create_arbitrary_rally_artifact(rally, type, fields=nil)
  if !fields.nil?  && fields[:Name].nil?
    name = Time.now.strftime("%y%m%d%H%M%S") + Time.now.usec.to_s
    fields[:Name] = name
  end
  return create_arbitrary_rally_object(rally, type, fields)
end

def create_arbitrary_rally_object(rally, type, fields = nil)
  item = rally.create(type, fields)
  return item
end

def destroy_rally_object(rally, obj)
  obj.destroy
end

def find_object_by_query(rally_connection,type,query_string)
  query_result = rally_connection.rally.find do |q|
    q.type = type
    q.workspace = rally_connection.workspace
    q.project = rally_connection.projects[0]
    q.fetch = true
    q.query_string = query_string
  end
  return query_result.first
end

def find_object(rally,type,object_id)
  query_result = rally.find do |q|
    q.type = type
   # q.workspace = rally.workspace
   # q.project = rally.projects[0]
    q.fetch = true
    q.query_string = "( ObjectID = \"#{object_id}\" )"
  end

  item = query_result.first

  return item
end