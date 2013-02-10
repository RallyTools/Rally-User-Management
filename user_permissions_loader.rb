# Copyright 2002-2013 Rally Software Development Corp. All Rights Reserved.

# encoding: UTF-8

# Usage: ruby user_permissions_loader.rb user_permissions_loader.txt
# Expected input files are defined as global variables below

# Delimited list of user permissions:
# $permissions_filename    = 'user_permissions_loader.txt'

#include for rally json library gem
require 'rally_api'
require 'csv'
require 'logger'
require File.dirname(__FILE__) + "/user_helper.rb"

# User-defined variables
$my_base_url                        = "https://rally1.rallydev.com/slm"
$my_username                        = "user@company.com"
$my_password                        = "password"

$permissions_filename = ARGV[0]

if $permissions_filename == nil
# This is the default of the file to be used for uploading user permissions
  $permissions_filename               = 'user_permissions_loader.txt'
end

if File.exists?(File.dirname(__FILE__) + "/" + $permissions_filename) == false
  puts "User permissions loader file #{$permissions_filename} not found. Exiting."
  exit
end

# Field delimiter for permissions file
$my_delim                           = "\t"

# Note: When creating many users, pre-fetching UserPermissions, Workspaces and Projects
# can radically improve performance since it also allows for
# a memory cache of existing Workspace/Projects and Workspace/Project permissions in Rally.
# This avoids the need to go back to Rally with a query in order to check for Workspace/Project existence and
# if a Permission update represents a change with respect to what's already there.
# Doing this in memory makes the code run much faster

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
$wsapi_version                      = "1.40"

# Fetch/query/create parameters
$my_headers                         = $headers
$my_page_size                       = 200
$my_limit                           = 50000
$user_create_delay                  = 0 # seconds buffer time after creating user and before adding permissions

# MAKE NO CHANGES BELOW THIS LINE!!
# =====================================================================================================

#Setup Role constants
$ADMIN = 'Admin'
$USER = 'User'
$EDITOR = 'Editor'
$VIEWER = 'Viewer'
$NOACCESS = 'No Access'
$TEAMMEMBER_YES = 'Yes'
$TEAMMEMBER_NO = 'No'

#Setup constants
$workspace_permission_type          = "WorkspacePermission"
$project_permission_type            = "ProjectPermission"

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

def update_permission(header, row)
  username               = row[header[0]].strip
  last_name              = row[header[1]].strip
  first_name             = row[header[2]].strip
  display_name           = row[header[3]].strip
  permission_type        = row[header[4]].strip
  workspace_name         = row[header[5]].strip
  workspace_project_name = row[header[6]].strip
  permission_level       = row[header[7]].strip
  team_member            = row[header[8]].strip
  object_id              = row[header[9]].strip

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

  if user == nil
    @logger.info "User #{username} does not yet exist. Creating..."
    user = @uh.create_user(username, display_name, first_name, last_name)
    sleep $user_create_delay
    new_user = true
  end

  # Update Workspace Permission if row type is WorkspacePermission
  if permission_type == "WorkspacePermission"
    workspace = @uh.find_workspace(object_id)
    if workspace != nil then
      @uh.update_workspace_permissions(workspace, user, permission_level, new_user)
    else
      @logger.error "Workspace #{workspace_project_name}, OID: #{object_id} not found. Skipping permission grant for this workspace."
    end
  end

  # Update Project Permission if row type is ProjectPermission
  # Warning: note this will error out if this is a new ProjectPermission within a
  # Workspace for which there is no existing WorkspacePermission for the user
  if permission_type == "ProjectPermission"
    project = @uh.find_project(object_id)
    if project != nil then
      @uh.update_project_permissions(project, user, permission_level, new_user)
    else
      @logger.error "Project #{workspace_project_name}, OID: #{object_id} not found. Skipping permission grant for this project."
    end

    # Update Team Membership (Only applicable for Editor Permissions at Project level)
    if permission_level == $EDITOR then
      @uh.update_team_membership(user, object_id, workspace_project_name, team_member)
    else
      @logger.info "  Permission level: #{permission_level}, Team Member: #{team_member}. #{$EDITOR} Permission needed to be " + \
         "Team Member. No Team Membership update: N/A."
    end
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
  if $enable_cache
    @logger.info "Caching workspaces and projects..."
    @uh.cache_workspaces_projects()

    @logger.info "Caching user list..."
    @uh.cache_users()
  end

  input  = CSV.read($permissions_filename, {:col_sep => $my_delim })

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    update_permission(header, row)
  end

  log_file.close

rescue => ex
  @logger.error ex
  @logger.error ex.backtrace
end