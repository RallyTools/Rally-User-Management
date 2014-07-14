# encoding: UTF-8
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

# Usage: ruby simple_user_loader.rb user_permissions_loader.txt
# Expected input files are defined as global variables below

# Delimited list of user attributes/permissions:
# $input_filename    = 'simple_user_loader.txt'
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
$file_encoding                      = "UTF-8"

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

# When this flag is set to true, Users provisioned via the simple_user_loader.rb script will ignore
# the Default Workspace,Project permissions, and will receive _only_ those permissions specified
# via the input file (via the source user permissions, for example)
$ignore_default_permissions        = false

# Maximum parameters for Workspaces/Projects to process
$max_workspaces                     = 100000
$max_projects                       = 100000

# Limited load mode for testing - triggers circuit-breaker if true
$test_mode                          = false


# MAKE NO CHANGES BELOW THIS LINE!!
# =====================================================================================================

#Setup Role constants
$ADMIN          = 'Admin'
$USER           = 'User'
$PROJECTADMIN   = "Admin"
$EDITOR         = 'Editor'
$VIEWER         = 'Viewer'
$NOACCESS       = 'No Access'
$TEAMMEMBER_YES = 'Yes'
$TEAMMEMBER_NO  = 'No'

# Permission types
$type_workspacepermission        = "WorkspacePermission"
$type_projectpermission          = "ProjectPermission"

def strip_role_from_permission(str)
    # Removes the role from the Workspace,ProjectPermission String so we're left with just the
    # Workspace/Project Name
    str.gsub(/\bAdmin|\bUser|\bEditor|\bViewer/,"").strip
end

def create_user(header, row)

  # LastName, FirstName, DisplayName, WorkspaceName are optional fields
  username_field               = row[header[0]]
  last_name_field              = row[header[1]]
  first_name_field             = row[header[2]]
  display_name_field           = row[header[3]]
  default_permissions_field    = row[header[4]]
  role_field                   = row[header[5]]
  office_location_field        = row[header[6]]
  department_field             = row[header[7]]
  cost_center_field            = row[header[8]]
  phone_field                  = row[header[9]]
  network_id_field             = row[header[10]]

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

  if !default_permissions_field.nil? then
    default_permissions = default_permissions_field.strip
  else
    default_permissions = $NOACCESS
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

  # look up user
  user = @uh.find_user(username)

  #create user if they do not exist

  if user == nil
    @logger.info "User #{username} does not yet exist. Creating..."
    begin
        user = @uh.create_user(username, user_fields)
        sleep $user_create_delay
        new_user = true
    rescue => ex
        @logger.error "Could not create user #{username}."
        @logger.error "   NOTE: Specified input values for Department,CostCenter, etc. MUST match valid values for these fields as defined in the Subscription."
        @logger.error "   NOTE: Workspace Admins must be granted permissions to create Users in order to run this script to setup new users."
        @logger.error ex
        return
    end
  end

  # Check for "type" of DefaultPermissions
  # if field value contains '@' we know that we are copying Default Permissions from
  # an existing user
  default_permission_type = @uh.check_default_permission_type(default_permissions)

  if default_permission_type == :stringsource then

      default_permission_string = default_permissions

      # If default permissions are No Access, we're donesetup initially
      if default_permission_string.eql?($NOACCESS) then
        @logger.info "User created without specifying any permissions."
        return
      end

      if !default_permission_string.eql?($EDITOR) && !default_permission_string.eql?($VIEWER) then
        @logger.warn "Default Permission level isn't one of: Editor, Viewer, or an existing Rally UserID."
        @logger.warn "No Default Permissions assigned!"
        return
      end

      workspace_count = 0
      $open_workspaces.each_pair do | this_workspace_oid, this_workspace |

        workspace_count += 1
        if workspace_count > $max_workspaces && $test_mode then
          @logger.info "  TEST MODE: Breaking workspaces at maximum of #{$max_workspaces}."
          break
        end

        # Update Workspace Permissions
        @logger.info "Workspace Name: #{this_workspace["Name"]}"
        @uh.update_workspace_permissions(this_workspace, user, default_permission_string, new_user)

        these_projects = $open_projects[this_workspace_oid]
        # Loop through open Projects, output Permission entries information

        # Default the user to be a team member if they are an Editor
        if default_permission_string.eql?($EDITOR) && $default_editors_to_team_members then
            team_membership = $TEAMMEMBER_YES
        else
            team_membership = $TEAMMEMBER_NO
        end

        project_count = 0
        if !these_projects.nil? then
          these_projects.each do | this_project |

            # Circuit-breaker for testing mode
            project_count += 1
            if project_count > $max_projects && $test_mode then
              @logger.info "  TEST MODE: Breaking projects at maximum of #{$max_projects}."
              break
            end

            this_project_name             = this_project["Name"]
            this_project_state            = this_project["State"]
            this_project_object_id        = this_project["ObjectID"]
            this_project_object_id_string = this_project_object_id.to_s

            @uh.update_project_permissions(this_project, user, default_permission_string, new_user)

            # Update Team Membership (Only applicable for Editor Permissions at Project level)
            if default_permission_string == $EDITOR then
              @uh.update_team_membership(user, this_project_object_id_string, this_project_name, team_membership)
            else
              @logger.info "  Permission level: #{default_permission_string}, Team Member: #{team_membership}. #{$EDITOR} Permission needed to be " + \
                 "Team Member. No Team Membership update: N/A."
            end
          end
        end
      end
  else
      # Template user id
      permission_template_username = default_permissions

      # We _are_ ignoring default permissions assigned by Rally, so if we do a user_permissions_sync, those permissions
      # not present on the source user, will be removed from the target
      if $ignore_default_permissions then
          @logger.info "$ignore_default_permissions == true"
          @logger.info "Permissions will be synced from the template user onto the new user."
          @logger.info "Permissions not present on the template user will be removed from the new user."
          @uh.sync_project_permissions(permission_template_username, user["UserName"])

          # We're not ignoring default permissions assigned by Rally, so, copy the template users permissions onto
      # the new user additively
      else
          # Check to see if we have cached user permissions for this user source
          if $user_permissions_cache.include?(permission_template_username)
              permission_source_user = $user_permissions_cache[permission_template_username]
          else
              # Go to Rally
              user_fetch                    = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,State,Project,ObjectID,State,TeamMemberships"
              user_query                    = RallyAPI::RallyQuery.new()
              user_query.type               = :user
              user_query.fetch              = user_fetch
              user_query.page_size          = 200 #optional - default is 200
              user_query.limit              = 50000 #optional - default is 99999
              user_query.order              = "UserName Asc"
              user_query.query_string       = "(UserName = \"#{permission_template_username}\")"

              user_query_results = @rally.find(user_query)
              n_users = user_query_results.total_result_count

              if n_users == 0 then
                  @logger.warn "User #{permission_template_username} not found in Rally for source of Default Permissions. Skipping permissions grants for user #{user['UserName']}"
                  return
              end

              permission_source_user = user_query_results.first
          end

          workspace_count = 0
          project_count = 0
          user_permissions = permission_source_user.UserPermissions

          @logger.info "Source User: #{permission_source_user} has #{user_permissions.length} permissions."

          user_permissions.each do | this_permission |

              # Set default for team membership
              team_member = "No"

              # Grab needed data from query/cache
              permission_type = this_permission._type
              permission_role = this_permission.Role

              if permission_type == $type_workspacepermission then

                  workspace_count += 1
                  if workspace_count > $max_workspaces && $test_mode then
                    @logger.info "  TEST MODE: Breaking workspaces at maximum of #{$max_workspaces}."
                    break
                  end

                  workspace_name = strip_role_from_permission(this_permission.Name)
                  this_workspace = this_permission["Workspace"]
                  team_member = "N/A"

                  # Don't summarize permissions for closed Workspaces
                  workspace_state = this_workspace["State"]

                  if workspace_state == "Closed"
                    next
                  end

                  @uh.update_workspace_permissions(this_workspace, user, permission_role, new_user)
              else
                  project_count += 1
                  if project_count > $max_projects && $test_mode then
                    @logger.info "  TEST MODE: Breaking projects at maximum of #{$max_projects}."
                    next
                  end

                  this_project = this_permission["Project"]

                  # Don't summarize permissions for closed Projects
                  project_state = this_project["State"]
                  if project_state == "Closed"
                      next
                  end

                  # Grab the Project Name
                  project_name = this_project["Name"]

                  # Grab the ObjectID
                  project_object_id = this_project["ObjectID"]

                  # Convert OID to a string so is_team_member can do string comparison
                  project_object_id_string = project_object_id.to_s

                  # Determine if user is a team member on this project
                  these_team_memberships = permission_source_user["TeamMemberships"]
                  team_member = @uh.is_team_member(project_object_id_string, permission_source_user)

                  @uh.update_project_permissions(this_project, user, permission_role, new_user)

                  @logger.info "Source User: #{permission_template_username}; #{project_name}; #{team_member}"

                  # Update Team Membership (Only applicable for Editor Permissions at Project level)
                  if permission_role == $EDITOR then
                    @uh.update_team_membership(user, project_object_id_string, project_name, team_member)
                  else
                    @logger.info "  Permission level: #{permission_role}, Team Member: #{team_member}. #{$EDITOR} Permission needed to be " + \
                      "Team Member. No Team Membership update: N/A."
                  end
              end
          end
      end
  end
  @uh.refresh_user(user["UserName"])
end

def go_simple_user_loader(input_file)

  # Load (and maybe override with) my personal/private variables from a file...
  my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
  if FileTest.exist?( my_vars ) then require my_vars end

  log_file = File.open("simple_user_loader.log", "a")
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
    create_user(header, row)
  end

  log_file.close

rescue => ex
  @logger.error ex
  @logger.error ex.backtrace
  @logger.error ex.message
end