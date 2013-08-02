# Copyright 2002-2013 Rally Software Development Corp. All Rights Reserved.

# encoding: UTF-8

# Usage: ruby user_profile_loader.rb user_profile_loader.txt
# Expected input files are defined as global variables below

# Delimited list of user permissions:
# $permissions_filename    = 'user_profile_loader.txt'

#include for rally json library gem
require 'rally_api'
require 'csv'
require 'logger'
require File.dirname(__FILE__) + "/user_helper.rb"

# User-defined variables
$my_base_url                        = "https://rally1.rallydev.com/slm"
$my_username                        = "user@company.com"
$my_password                        = "password"

$profile_filename = ARGV[0]

if $profile_filename == nil
# This is the default of the file to be used for uploading user permissions
  $profile_filename               = 'user_profile_loader.txt'
end

if File.exists?(File.dirname(__FILE__) + "/" + $profile_filename) == false
  puts "User profile loader file #{$profile_filename} not found. Exiting."
  exit
end

# Field delimiter for permissions file
$my_delim                           = "\t"


# Note: When creating or updating many users, pre-fetching UserPermissions
# can improve performance

# However, when creating/updating only one or two users, the up-front cost of caching is probably more expensive
# than the time saved, so setting this flag to false probably makes sense when creating/updating small
# numbers of users
$enable_cache                       = true

#Setting custom headers
$headers                            = RallyAPI::CustomHttpHeader.new()
$headers.name                       = "Ruby User Management Tool 2"
$headers.vendor                     = "Rally Labs"
$headers.version                    = "0.10"

#API Version
$wsapi_version                      = "1.41"

# Fetch/query/create parameters
$my_headers                         = $headers
$my_page_size                       = 200
$my_limit                           = 50000
$user_create_delay                  = 0 # seconds buffer time after creating user and before adding permissions

# MAKE NO CHANGES BELOW THIS LINE!!
# =====================================================================================================

# Class to help Logger output to both STOUT and to a file
class MultiIO
  def initialize(*targets)
     @targets = targets
  end

  def write(*args)
    @targets.each {|t| t.write(*args)}
  end

  def close
    @targets.each(&:close)
  end
end

def update_profile(header, row)

  username_field               = row[header[0]]
  last_name_field              = row[header[1]]
  first_name_field             = row[header[2]]
  display_name_field           = row[header[3]]
  role_field		       = row[header[4]]
  office_location_field	       = row[header[5]]
  
   # Check to see if any required fields are nil
    required_field_isnil = false
    required_nil_fields = ""
    
    if username_field.nil? then
      required_field_isnil = true
      required_nil_fields += "UserName"
    else
      username = username_field.strip
    end
    if last_name_field.nil? then
      required_field_isnil = true
      required_nil_fields += " LastName"
    else
      last_name = last_name_field.strip
    end
    if first_name_field.nil? then
      required_field_isnil = true
      required_nil_fields += " FirstName"
    else
      first_name = first_name_field.strip
    end
    
    if display_name_field.nil? then
          required_field_isnil = true
          required_nil_fields += " DisplayName"
        else
          display_name = display_name_field.strip
    end
    
    if required_field_isnil then
      puts "One or more required fields: "
      puts required_nil_fields
      puts "Is missing! Skipping this row..."
      return
    end

    
  # look up user
  user = @uh.find_user(username)
  
  #create user if they do not exist
    #Warning: if you opt to allow new user creation as part of the script:
    #New users are created with one default WorkspacePermission and one default ProjectPermission, as follows:
    #WorkspacePermission: User, First Workspace alphabetically
    #ProjectPermission: No Access, First Project within above workspace, alphabetically
    #This behavior is necessary because a user must have at least one Workspace,Project permission pairing
    #The above grants provide no access, but, will result in a "creation" artifact within the new user's
    #permission set
  
  #  if user == nil
  #    @logger.info "User #{username} does not yet exist. Creating..."
  #    user = @uh.create_user(username, display_name, first_name, last_name)
  #    sleep $user_create_delay
  #    new_user = true
  #end
  
  #Update DisplayName if needed
  if user != nil then
  	if user.DisplayName != display_name then
  	   @uh.update_display_name(user, display_name)
  	else 
  	   @logger.info "  #{username} - No Display Name update"
  	end
  else
  	@logger.info "User #{username} does not exist."
  end
end

begin

  # Load (and maybe override with) my personal/private variables from a file...
  my_vars= File.dirname(__FILE__) + "/my_vars.rb"
  if FileTest.exist?( my_vars ) then require my_vars end

  log_file = File.open("user_permissions_loader.log", "a")
  @logger = Logger.new MultiIO.new(STDOUT, log_file)

  @logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL


  #==================== Making a connection to Rally ====================
  config                  = {:base_url => $my_base_url}
  config[:username]       = $my_username
  config[:password]       = $my_password
  config[:headers]        = $my_headers #from RallyAPI::CustomHttpHeader.new()
  config[:version]        = $wsapi_version

  @logger.info "Connecting to #{$my_base_url} as #{$my_username}..."
  @rally = RallyAPI::RallyRestJson.new(config)

  #Helper Methods
  @logger.info "Instantiating User Helper..."
  @uh = UserHelper.new(@rally, @logger, true)

  # Note: pre-fetching Workspaces and Projects can help performance
  # Plus, we pretty much have to do it because later Workspace/Project queries
  # in UserHelper, that don't come off the Subscription List, will fail
  # unless they are in the user's Default Workspace
  #@logger.info "Caching workspaces and projects..."
  #@uh.cache_workspaces_projects()
  
  # Caching Users can help performance if we're doing updates for a lot of users
  if $enable_user_cache
    @logger.info "Caching user list..."
    @uh.cache_users()
  end

  input  = CSV.read($profile_filename, {:col_sep => $my_delim })

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    update_profile(header, row)
  end

  log_file.close

rescue => ex
  @logger.error ex
  @logger.error ex.backtrace
  @logger.error ex.message
end