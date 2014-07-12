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

fileloc = File.dirname(__FILE__)

require 'rally_api'
require fileloc + '/rally_user_helper.rb'
require fileloc + '/multi_io.rb'
require fileloc + '/version.rb'
require 'csv'
require 'logger'

#API Version
$wsapi_version          = "1.43"

# constants
$my_base_url            = "https://rally1.rallydev.com/slm"
$my_username            = "user@company.com"
$my_password            = "password"
$my_headers             = $headers
$my_page_size           = 200
$my_limit               = 50000

# Encoding
$file_encoding          = "UTF-8"

# Mode options:
# :standard => Outputs permission attributes only
# :extended => Outputs enhanced field list including Enabled/Disabled,NetworkID,Role,CostCenter,Department,OfficeLocation
$summary_mode = :standard

$type_workspacepermission = "WorkspacePermission"
$type_projectpermission   = "ProjectPermission"
$standard_output_fields   =  %w{UserID LastName FirstName DisplayName Type Workspace WorkspaceOrProjectName Role TeamMember ObjectID}
$extended_output_fields   =  %w{UserID LastName FirstName DisplayName Type Workspace WorkspaceOrProjectName Role TeamMember ObjectID LastLoginDate Disabled NetworkID Role CostCenter Department OfficeLocation }

$my_output_file           = "project_permissions_summary.txt"
$input_delim              = ","
$output_delim             = "\t"

#Setup role constants
$ADMIN = 'Admin'
$EDITOR = 'Editor'
$VIEWER = 'Viewer'
$NOACCESS = 'No Access'

# Load (and maybe override with) my personal/private variables from a file...
my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
if FileTest.exist?( my_vars ) then require my_vars end

$initial_fetch            = "UserName,FirstName,LastName,DisplayName"
$standard_detail_fetch    = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,State,Project,ObjectID,State,TeamMemberships"
$extended_detail_fetch    = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,State,Project,ObjectID,State,TeamMemberships,LastLoginDate,Disabled,NetworkID,Role,CostCenter,Department,OfficeLocation"

$enabled_only_filter      = "(Disabled = \"False\")"

if $summary_mode == :extended then
  $summarize_enabled_only = false
  $output_fields = $extended_output_fields
  $detail_fetch = $extended_detail_fetch
else
  # For purposes of speed/efficiency, summarize Enabled Users ONLY
  $summarize_enabled_only = true
  $output_fields = $standard_output_fields
  $detail_fetch = $standard_detail_fetch
end

if $output_delim == nil then $my_delim = "," end

def strip_role_from_permission(str)
  # Removes the role from the Workspace,ProjectPermission String so we're left with just the
  # Workspace/Project Name
  str.gsub(/\bAdmin|\bUser|\bEditor|\bViewer/,"").strip
end

def project_id_type(project_id)
    if /\d+/.match(project_id) then
        return :object_id
    else
        return :name
    end
end

def is_workspace_admin(user, project)
    is_admin = false
    user_permissions = user["UserPermissions"]

    this_workspace = project["Workspace"]
    this_workspace_oid = this_workspace["ObjectID"].to_s

    user_permissions.each do  | this_permission |
        if this_permission._type == "WorkspacePermission" then
            if this_permission.Workspace.ObjectID.to_s == this_workspace_oid then
                permission_level = this_permission.Role
                if permission_level == $ADMIN then
                    is_admin = true
                    break
                end
            end
        end
    end
    return is_admin
end

def is_team_member(project_oid, team_memberships)

  # Default values
  is_member = false
  return_value = "No"

  # First check if team_memberships are nil then loop through and look for a match on
  # Project OID
  if team_memberships != nil then

    team_memberships.each do |this_membership|
      this_membership_ref = this_membership._ref

      # Grab the Project OID off of the ref URL
      this_membership_oid = this_membership_ref.split("\/")[-1].split("\.")[0]

      if this_membership_oid == project_oid then
        is_member = true
      end
    end
  end

  if is_member then return_value = "Yes" end
  return return_value
end

def find_role(user, project)
    this_user = user
    this_user_role = "N/A"
    project_oid = project["ObjectID"]

    user_permissions = this_user.UserPermissions
    user_permissions.each do | this_permission |
        permission_type = this_permission._type
        if permission_type == $type_projectpermission then
            project_obj = this_permission["Project"]
            # Grab the ObjectID
            object_id = project_obj["ObjectID"].to_s
            if object_id == project_oid then
                this_user_role = this_permission.Role
            end
        end
    end
    return this_user_role
end

def summarize_user(this_user, project)

    project_name = project["Name"]
    project_oid = project["ObjectID"].to_s

    this_workspace = project["Workspace"]
    workspace_name = this_workspace["Name"]

    # Check to see if the User is a Subscription or Workspace Administrator.
    if this_user.SubscriptionAdmin then
        this_user_role = "Subscription Admin"
    elsif is_workspace_admin(this_user, project) then
        this_user_role = "Workspace Admin"
    # Not an admin - so lookup the actual role the user has in the project
    else
        this_user_role = find_role(this_user, project)
    end

    team_memberships = this_user["TeamMemberships"]
    team_member = is_team_member(project_oid, team_memberships)

    @logger.info "Summarizing #{this_user.UserName}'s permissions in Project #{project_name}"

    output_record = []
    output_record << this_user.UserName
    output_record << this_user.LastName
    output_record << this_user.FirstName
    output_record << this_user.DisplayName
    output_record << $type_projectpermission
    output_record << workspace_name
    output_record << project_name
    output_record << this_user_role
    output_record << team_member
    output_record << project_oid
    output_record << this_user.Disabled
    if $summary_mode == :extended then
        output_record << this_user.LastLoginDate
        output_record << this_user.NetworkID
        output_record << this_user.Role
        output_record << this_user.CostCenter
        output_record << this_user.Department
        output_record << this_user.OfficeLocation
    end
    return output_record
end

def go_summarize_project_permissions(project_identifier)

    # Load (and maybe override with) my personal/private variables from a file...
    my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
    if FileTest.exist?( my_vars ) then require my_vars end

    log_file = File.open("summarize_project_permissions.log", "a")
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
    @rally                  = RallyAPI::RallyRestJson.new(config)

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

    # Caching Users can help performance if we're doing updates for a lot of users
    if $enable_user_cache
        @logger.info "Caching user list..."
        @uh.cache_users()
    end

    project_identifier_string = project_identifier.to_s
    type_of_project_id = project_id_type(project_identifier_string)

    if type_of_project_id == :name then
        project, is_duplicate_proj = @uh.find_project_by_name(project_identifier_string)
        if is_duplicate_proj then
            @logger.info "More than one project named #{project_identifier_string} found in Rally."
            @logger.info "Please specify your project by ObjectID instead, to guarantee selection of the correct Project."
            @logger.info "Exiting..."
            return
        end
    elsif type_of_project_id == :object_id then
        project = @uh.find_project(project_identifier_string)
    else
        @logger.info "Invalid project identifier specified: #{project_identifier_string}."
        @logger.info "Please use either a Project Name or a Project ObjectID. Exiting."
        return
    end

    if project.nil? then
        @logger.info "Project #{project_identifier_string} not found in Rally. Exiting now..."
        return
    end

    project_name = project["Name"]
    project_oid = project["ObjectID"]

    # All checks passed. Proceed...

    # loop through all users and output permissions summary
    @logger.info "Summarizing users and writing permission summary output file..."

    begin
        # Open file for output of summary
        # Output CSV header
        summary_csv = CSV.open($my_output_file, "w", {:col_sep => $output_delim, :encoding => $file_encoding})
        summary_csv << $output_fields

        project_users = @uh.get_project_users(project_oid)

        number_found = project_users.length
        @logger.info "Found #{number_found} users for project #{project_name}."

        if number_found == 0 then
            @logger.warn "No users found in Project #{project_name}. Exiting now..."
            log_file.close
            return
        end

        project_users.each do | this_user_record |
            summary_csv << summarize_user(this_user_record, project)
        end

        @logger.info "Done! Permission summary written to #{$my_output_file}."
        log_file.close

        rescue Exception => ex
        @logger.error ex.backtrace
        @logger.error ex.message
    end
end