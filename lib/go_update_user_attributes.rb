# Copyright (c) 2014 Rally Software Development
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

# Usage: ruby update_user_attributes.rb update_user_attributes.txt
# Expected input files are defined as global variables below

# Delimited list of user attributes:
# $input_filename    = 'update_user_attributes.txt'
fileloc = File.dirname(__FILE__)

require 'rally_api'
require fileloc + '/rally_user_helper.rb'
require fileloc + '/multi_io.rb'
require fileloc + '/version.rb'
require 'csv'
require 'logger'

# User-defined variables
$my_base_url                        = "https://rally1.rallydev.com/slm"
$my_username                        = "user@company.com"
$my_password                        = "password"

# Encoding
$file_encoding                     = "UTF-8"

# Field delimiter for permissions file
$my_delim                           = "\t"

# Note: When creating or updating many users, pre-fetching UserPermissions
# can improve performance

# However, when creating/updating only one or two users, the up-front cost of caching is probably more expensive
# than the time saved, so setting this flag to false probably makes sense when creating/updating small
# numbers of users
$enable_cache                       = true

#Setting custom headers
@user_mgmt_version                  = RallyUserManagement::Version.new()
$headers                            = RallyAPI::CustomHttpHeader.new()
$headers.name                       = "Ruby User Management Tool 2"
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

# upgrade_only_mode - when running in upgrade_only_mode, check existing permissions
# first, and only apply the change if it represents an upgrade over existing permissions
$upgrade_only_mode                  = false

# Maximum parameters for Workspaces/Projects to process
$max_workspaces                     = 100000
$max_projects                       = 100000

# Limited load mode for testing - triggers circuit-breaker if true
$test_mode                          = false


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

# Permission types
$type_workspacepermission        = "WorkspacePermission"
$type_projectpermission          = "ProjectPermission"

def strip_role_from_permission(str)
    # Removes the role from the Workspace,ProjectPermission String so we're left with just the
    # Workspace/Project Name
    str.gsub(/\bAdmin|\bUser|\bEditor|\bViewer/,"").strip
end

def update_attributes(header, row)

  # LastName, FirstName, DisplayName, WorkspaceName are optional fields
  username_field               = row[header[0]]
  last_name_field              = row[header[1]]
  first_name_field             = row[header[2]]
  display_name_field           = row[header[3]]
  role_field                   = row[header[4]]
  office_location_field        = row[header[5]]
  department_field             = row[header[6]]
  cost_center_field            = row[header[7]]
  phone_field                  = row[header[8]]
  network_id_field             = row[header[9]]
  default_workspace_field      = row[header[10]]
  default_project_field        = row[header[11]]
  timezone_field               = row[header[12]]

  # Check to see if any required fields are nil
  required_field_isnil = false
  required_nil_fields = ""

  if username_field.nil? then
    required_field_isnil = true
    required_nil_fields += "UserName"
  else
    # Downcase - Rally's WSAPI lookup finds user based on lower-case UserID
    username = username_field.strip.downcase
  end

  if required_field_isnil then
    @logger.warn "One or more required fields: "
    @logger.warn required_nil_fields
    @logger.warn "Is missing! Skipping this row..."
    return
  end

  user_fields = {}

  # Filter for possible nil values in optional fields
  if !last_name_field.nil? then
    last_name = last_name_field.strip
    user_fields["LastName"] = last_name
  end

  if !first_name_field.nil? then
    first_name = first_name_field.strip
    user_fields["FirstName"] = first_name
  end

  if !display_name_field.nil? then
    display_name = display_name_field.strip
    user_fields["DisplayName"] = display_name
  end

  if !role_field.nil? then
    role = role_field.strip
    user_fields["Role"] = role
  end

  if !office_location_field.nil? then
    office_location = office_location_field.strip
    user_fields["OfficeLocation"] = office_location
  end

  if !department_field.nil? then
    department = department_field.strip
    user_fields["Department"] = department
  end

  if !cost_center_field.nil? then
    cost_center = cost_center_field.strip
    user_fields["CostCenter"] = cost_center
  end

  if !phone_field.nil? then
    phone = phone_field.strip
    user_fields["Phone"] = phone
  end

  if !network_id_field.nil? then
    network_id = network_id_field.strip
    user_fields["NetworkID"] = network_id
  end

  need_profile_update = false
  if !default_workspace_field.nil? then
    default_workspace_name = default_workspace_field.strip
    need_default_workspace_update = true
  end

  if !default_project_field.nil? then
    default_project_name = default_project_field.strip
    need_default_project_update = true
  end

  if !timezone_field.nil? then
    timezone = timezone_field.strip
    need_timezone_update = true
  end

  # look up user
  user         = @uh.find_user(username)

  #update user if they exist

  if user == nil
    @logger.info "User #{username} does not exist. Cannot update attributes..."
    return
  else
    # Update attributes on User Object
    begin
        @uh.update_user(user, user_fields)
        @uh.refresh_user(user["UserName"])
        @logger.info "Updated User."
    rescue => ex
        @logger.error "Could not update user #{username}."
        @logger.error "   NOTE: Specified input values for Department,CostCenter, etc. MUST match valid values for these fields as defined in the Subscription."
        @logger.error "   NOTE: Workspace Admins must be granted permissions to create Users in order to run this script to adjust user attributes."
        @logger.error ex
        return
    end

    # Update attributes on UserProfile Object
    if need_default_workspace_update && need_default_project_update then
      user_profile = user["UserProfile"]
      user_profile.read

      # Construct refs for Default Workspace Project
      default_workspace, is_workspace_name_duplicate = @uh.find_workspace_by_name(default_workspace_name)
      default_project, is_project_name_duplicate   = @uh.find_project_by_name(default_project_name)

      if default_workspace.nil? then
        @logger.warn "    Default Workspace: #{default_workspace} Not found. Skipping update."
        return
      end

      if default_project.nil? then
        @logger.warn "    Default Project: #{default_project} Not found. Skipping update."
        return
      end

      # Check to see if default project is in the default workspace
      is_project_in_workspace = @uh.is_project_in_workspace(default_project, default_workspace)

      # Believe it or not WSAPI will let you set Default Workspace/Project attributes in
      # Workspaces/Projects where you have no permissions. Let's trap that.
      default_workspace_permission_exists = @uh.does_user_have_workspace_permission?(default_workspace, user)
      default_project_permission_exists = @uh.does_user_have_project_permission?(default_project, user)

      # Check multiple conditions needed to update Default Workspace/Project
      failed_reason = ""
      conditions_met = true
      if !is_project_in_workspace then
        conditions_met = false
        failed_reason += "   Default Project #{default_project_name} is not in Workspace: #{default_workspace_name}.\n"
      end

      if default_workspace.nil? then
        conditions_met = false
        failed_reason += "   Cannot find Default Workspace: #{default_workspace_name}\n"
      end

      if default_project.nil? then
        conditions_met = false
        failed_reason +=  "  Cannot find Default Project: #{default_project_name}"
      end

      if !default_workspace_permission_exists || !default_project_permission_exists then
        conditions_met = false
        failed_reason += "   User must have Permissions in both Default Workspace and Default Project."
      end

      if conditions_met then
        begin
          user_profile_fields = {
            "DefaultWorkspace" => default_workspace["_ref"],
            "DefaultProject"   => default_project["_ref"]
          }
          user_profile.update(user_profile_fields)
          @logger.info "Updated #{username} with Default Workspace: #{default_workspace_name} / Default Project: #{default_project_name}"
        rescue => ex
          @logger.error "Could not update user profile settings for Workspace/Project on User: #{username}."
          @logger.error ex
        end
      else
        @logger.warn "  Problem occurred setting Default Workspace/Project."
        @logger.warn failed_reason
        @logger.warn " Default Workspace/Project not set!"
      end
    end

    if need_timezone_update then
      begin

        # Check for "Default" as Timezone value
        if timezone.eql?("Default") then
          timezone = nil
        end

        user_profile_fields = {
          "TimeZone" => timezone
        }
        user_profile.update(user_profile_fields)
        @logger.info "Update #{username} with TimeZone: #{timezone}"
      rescue => ex
        @logger.error "Could not update user profile settings for TimeZone on User: #{username}."
        @logger.error ex
      end
    end
  end
end

def go_update_user_attributes(input_file)

  # Load (and maybe override with) my personal/private variables from a file...
  my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
  if FileTest.exist?( my_vars ) then require my_vars end

  log_file = File.open("update_user_attributes.log", "a")
  if $logger_mode == :stdout then
      @logger = Logger.new RallyUserManagement::MultiIO.new(STDOUT, log_file)
  else
      @logger = Logger.new(log_file)
  end

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
  uh_config                       = {}
  uh_config[:rally_api]           = @rally
  uh_config[:logger]              = @logger
  uh_config[:create_flag]         = true
  uh_config[:max_cache_age]       = $max_cache_age
  uh_config[:upgrade_only_mode]   = $upgrade_only_mode
  uh_config[:file_encoding]       = $file_encoding

  @uh = RallyUserManagement::UserHelper.new(uh_config)

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

  # User Permissions cache
  $user_permissions_cache = {}

  # Caching Users can help performance if we're doing updates for a lot of users
  if $enable_user_cache
    @logger.info "Caching user list..."
    @uh.cache_users()
    $user_permissions_cache = @uh.get_cached_users()
  end

  # Workspace and Project caches
  $open_workspaces = @uh.get_cached_workspaces()
  $open_projects = @uh.get_workspace_project_hash()

  $input_filename = input_file
  input  = CSV.read($input_filename, {:col_sep => $my_delim, :encoding => $file_encoding})

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    update_attributes(header, row)
  end

  log_file.close

rescue => ex
  @logger.error ex
  @logger.error ex.backtrace
  @logger.error ex.message
end