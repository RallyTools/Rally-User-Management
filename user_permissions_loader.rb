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
require './user_mgmt_version'
require 'csv'
require 'logger'
require './multi_io.rb'
require File.dirname(__FILE__) + "/user_helper.rb"

# User-defined variables
$my_base_url                        = "https://rally1.rallydev.com/slm"
$my_username                        = "user@company.com"
$my_password                        = "password"

$permissions_filename = ARGV[0]

if $permissions_filename == nil
# This is the default of the file to be used for uploading user permissions
  $permissions_filename             = 'user_permissions_loader.txt'
end

if File.exists?(File.dirname(__FILE__) + "/" + $permissions_filename) == false
  puts "User permissions loader file #{$permissions_filename} not found. Exiting."
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
@user_mgmt_version                  = UserManagementVersion.new()
$headers                            = RallyAPI::CustomHttpHeader.new()
$headers.name                       = "Ruby User Management Tool 2::User Permissions Loader"
$headers.vendor                     = "Rally Labs"
$headers.version                    = @user_mgmt_version.revision()

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

def update_permission(header, row)

  # LastName, FirstName, DisplayName, WorkspaceName are optional fields
  username_field               = row[header[0]]
  last_name_field              = row[header[1]]
  first_name_field             = row[header[2]]
  display_name_field           = row[header[3]]
  permission_type_field        = row[header[4]]
  workspace_name_field         = row[header[5]]
  workspace_project_name_field = row[header[6]]
  permission_level_field       = row[header[7]]
  team_member_field            = row[header[8]]
  object_id_field              = row[header[9]]

  # Check to see if any required fields are nil
  required_field_isnil = false
  required_nil_fields = ""

  if username_field.nil? then
    required_field_isnil = true
    required_nil_fields += "UserName"
  else
    username = username_field.strip
  end
  if permission_type_field.nil? then
    required_field_isnil = true
    required_nil_fields += " PermissionType"
  else
    permission_type = permission_type_field.strip
  end
  if workspace_project_name_field.nil? then
    required_field_isnil = true
    required_nil_fields += " Workspace/ProjectName"
  else
    workspace_project_name = workspace_project_name_field.strip
  end
  if permission_level_field.nil? then
    required_field_isnil = true
    required_nil_fields += " PermissionLevel"
  else
    permission_level = permission_level_field.strip
  end
  if team_member_field.nil? then
    required_field_isnil = true
    required_nil_fields += " TeamMember"
  else
    team_member = team_member_field.strip
  end
  if object_id_field.nil? then
    required_field_isnil = true
    required_nil_fields += " ObjectID"
  else
    object_id = object_id_field.strip
  end

  if required_field_isnil then
    @logger.warn "One or more required fields: "
    @logger.warn required_nil_fields
    @logger.warn "Is missing! Skipping this row..."
    return
  end

  # Filter for possible nil values in optional fields
  if !last_name_field.nil? then
    last_name = last_name_field.strip
  else
    last_name = "N/A"
  end

  if !first_name_field.nil? then
    first_name = first_name_field.strip
  else
    first_name = "N/A"
  end

  if !display_name_field.nil? then
    display_name = display_name_field.strip
  else
    display_name = "N/A"
  end

  if !workspace_project_name_field.nil? then
    workspace_project_name = workspace_project_name_field.strip
  else
    workspace_project_name = "N/A"
  end

  # look up user
  user = @uh.find_user(username)

  #create user if they do not exist
  #Warning: if you opt to allow new user creation as part of the script:
  #New users are created with one default WorkspacePermission and one default ProjectPermission, as follows:
  #WorkspacePermission: User, First Workspace alphabetically
  #ProjectPermission: No Access, First Project within above workspace, alphabetically
  #This behavior is necessary because a user must have at least one Workspace,Project permission pairing
  #The above grants provide no write-able access, but, will result in a "creation" artifact within the new user's
  #permission set

  if user == nil
    @logger.info "User #{username} does not yet exist. Creating..."
    begin
        user = @uh.create_user(username, display_name, first_name, last_name)
        sleep $user_create_delay
        new_user = true
    rescue => ex
        @logger.error "Cound not create user #{username}."
        @logger.error "NOTE: Workspace Admins must be granted permissions to create Users in order to run this script to setup new users."
        @logger.error ex
        return
    end
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
  @logger.error ex.message
end