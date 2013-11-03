# Copyright (c) 2013 Rally Software Development
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# encoding: UTF-8

# Usage: ruby user_permissions_loader.rb user_permissions_loader.txt
# Expected input files are defined as global variables below

# Delimited list of user permissions:
# $permissions_filename    = 'user_permissions_loader.txt'

require 'rally_api'
require 'csv'
require 'logger'
require './multi_io.rb'
require File.dirname(__FILE__) + "/user_helper.rb"

# User-defined variables
$my_base_url                        = "https://rally1.rallydev.com/slm"
$my_username                        = "user@company.com"
$my_password                        = "password"

$user_synclist_filename = ARGV[0]

if $user_synclist_filename == nil
# This is the default of the file to be used for uploading user permissions
  $user_synclist_filename             = 'user_sync_list.txt'
end

if File.exists?(File.dirname(__FILE__) + "/" + $user_synclist_filename) == false
  puts "User permissions sync list file #{$user_synclist_filename} not found. Exiting."
  exit
end

# Field delimiter for permissions file
$my_delim                           = ","


# Note: When creating or updating many users, pre-fetching UserPermissions
# can improve performance

# However, when creating/updating only one or two users, the up-front cost of caching is probably more expensive
# than the time saved, so setting this flag to false probably makes sense when creating/updating small
# numbers of users
$enable_cache                       = true

#Setting custom headers
$headers                            = RallyAPI::CustomHttpHeader.new()
$headers.name                       = "Ruby User Management Tool 2::User Permissions Syncer"
$headers.vendor                     = "Rally Labs"
$headers.version                    = "0.50"

#API Version
$wsapi_version                      = "1.43"

# Fetch/query/create parameters
$my_headers                         = $headers
$my_page_size                       = 200
$my_limit                           = 50000
$user_create_delay                  = 0 # seconds buffer time after creating user and before adding permissions

# Maximum age of workspace/project cache in days before triggering
# automatic refresh
$max_cache_age                      = 1

# Flag specifying whether to sync team memberships along with
# user permissions
$sync_team_memberships              = true

# MAKE NO CHANGES BELOW THIS LINE!!
# =====================================================================================================

def sync_permissions(header, row)

  target_user_name_field             = row[header[0]]
  source_user_name_field             = row[header[1]]

  # Check to see if any input fields are nil
  required_field_isnil = false
  required_nil_fields = ""

  if target_user_name_field.nil? then
    required_field_isnil = true
    required_nil_fields += "TargetUserID"
  else
    target_user_name = target_user_name_field.strip
  end

  if source_user_name_field.nil? then
    required_field_isnil = true
    required_nil_fields += " SourceUserID"
  else
    source_user_name = source_user_name_field.strip
  end

  if required_field_isnil then
    @logger.warn "One or more required fields: "
    @logger.warn required_nil_fields
    @logger.warn "Is missing! Skipping this row..."
    return
  end

  # look up users
  source_user = @uh.find_user(source_user_name)
  target_user = @uh.find_user(target_user_name)

  if target_user == nil
    @logger.warn "User #{target_user_name} to whom permissions are being mirrored does not exist. Skipping..."
    return
  end

  if source_user == nil
    @logger.warn "Source User: #{source_user_name} for template permissions does not exist. Skipping..."
    return
  end

  @logger.info "Syncing permissions from: #{source_user_name} to #{target_user_name}."
  @uh.sync_project_permissions(source_user_name, target_user_name)

  source_user = @uh.refresh_user(source_user_name)
  if $sync_team_memberships then
    @logger.info "Syncing team memberships from: #{source_user_name} to #{target_user_name}."
    @uh.sync_team_memberships(source_user_name, target_user_name)
  end
end

begin

  # Load (and maybe override with) my personal/private variables from a file...
  my_vars= File.dirname(__FILE__) + "/my_vars.rb"
  if FileTest.exist?( my_vars ) then require my_vars end

  log_file = File.open("user_permissions_syncer.log", "a")
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
  @uh = UserHelper.new(@rally, @logger, true, $max_cache_age)

  # Note: pre-fetching Workspaces and Projects can help performance
  # Plus, we pretty much have to do it because later Workspace/Project queries
  # in UserHelper, that don't come off the Subscription List, will fail
  # unless they are in the user's Default Workspace

  # The following block will pre-fetch Workspaces and Projects either:
  # (1) From Rally directly, if no local cache exists or local cache is stale
  #     (older than $max_cache_age, as specified in my_vars.rb)
  # (2) Load from local cache files (much faster) if local cache is current
  #     (newer than $max_cache_age, as specified in my_vars.rb)
  @logger.info "Caching workspaces and projects..."
  refresh_needed, reason = @uh.cache_refresh_needed()
  if refresh_needed then
    @logger.info "Refresh of Workspace/Project Cache from Rally is required because #{reason}."
    @logger.info "Refreshing Workspace/Project by querying Rally for needed data."
    @uh.cache_workspaces_projects()
  else
    @logger.info "Reading Workspace/Project info from local cache."
    @uh.read_workspace_project_cache()
  end

  # Caching Users can help performance if we're doing updates for a lot of users
  if $enable_user_cache
    @logger.info "Caching user list..."
    @uh.cache_users()
  end

  input  = CSV.read($user_synclist_filename, {:col_sep => $my_delim })

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    sync_permissions(header, row)
  end

  log_file.close

rescue => ex
  @logger.error ex
  @logger.error ex.backtrace
  @logger.error ex.message
end