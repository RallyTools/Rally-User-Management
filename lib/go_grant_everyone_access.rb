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

$valid_roles = [$ADMIN, $EDITOR, $VIEWER, $NOACCESS]

# Load (and maybe override with) my personal/private variables from a file...
my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
if FileTest.exist?( my_vars ) then require my_vars end

$initial_fetch            = "UserName,FirstName,LastName,DisplayName"
$standard_detail_fetch    = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,State,Project,ObjectID,State,TeamMemberships"
$extended_detail_fetch    = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,State,Project,ObjectID,State,TeamMemberships,LastLoginDate,Disabled,NetworkID,Role,CostCenter,Department,OfficeLocation"

$enabled_only_filter      = "(Disabled = \"False\")"

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

def grant_project_access(user, project, permission_level)
    user_name = user["UserName"]

    # Check to see if the User is a Subscription or Workspace Administrator.
    # They will always have access to the Project of concern, so there's no point in
    # doing a Project-level permission change for them
    if user.SubscriptionAdmin then
        @number_subscription_admins += 1
        @logger.info "User #{user_name} is a Subscription Admin. No change in access to Project #{project["Name"]} applied."
        return
    end
    if is_workspace_admin(user, project) then
        @number_workspace_admins += 1
        @logger.info "User #{user_name} is a Workspace Admin for the Workspace containing #{project["Name"]}. No change in access to Project #{project["Name"]} applied."
        return
    end

    # Ok, they're a regular user. Proceed to process the update

    begin
        @logger.info "Updating permissions for User #{user_name}"
        create_new_user_flag = false
        @uh.update_project_permissions(project, user, permission_level, create_new_user_flag)
        @number_updated += 1
    rescue => ex
        @logger.error "Error occurred trying to update permissions for user #{user_name}."
        @logger.error ex
        return
    end
end

def is_permission_valid(permission_string)
    is_valid = false
    if $valid_roles.include?(permission_string) then
        is_valid = true
    end
    return is_valid
end

def go_grant_everyone_access(project_identifier, new_permission)

    # Load (and maybe override with) my personal/private variables from a file...
    my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
    if FileTest.exist?( my_vars ) then require my_vars end

    log_file = File.open("grant_everyone_access.log", "a")
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
    # Force upgrade-only mode for this script
    uh_config[:upgrade_only_mode]   = true
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

    # Check Permission type string to see if its valid
    if !is_permission_valid(new_permission) then
        @logger.error "Invalid permission string specified. Must be one of: "
        @logger.error $valid_roles.join(", ")
        @logger.error "Exiting..."
        log_file.close
        return
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

    begin
        #==================== Querying Rally ==========================
        user_query = RallyAPI::RallyQuery.new()
        user_query.type = :user
        user_query.fetch = $initial_fetch
        user_query.page_size = 200 #optional - default is 200
        user_query.limit = 50000 #optional - default is 99999
        user_query.order = "UserName Asc"
        user_query.query_string = $enabled_only_filter

        number_found_suffix = "Enabled Users."

        # Query for users
        puts "Running initial query of users..."

        initial_user_query_results = @rally.find(user_query)
        n_users = initial_user_query_results.total_result_count

        # Summarize number of found users
        puts "Found a total of #{n_users} " + number_found_suffix

        STDIN.flush
        affirmative_answer = "y"
        proceed = [(puts "Proceed to update permission to #{new_permission} for ALL non-(Sub,Workspace) Admin existing enabled users in Rally to Project: #{project_name}? [N/y]:"), STDIN.gets.rstrip][1]

        if !proceed.eql?(affirmative_answer) then
            @logger.info "User cancelled update operation. Exiting now..."
            log_file.close
            return
        end

        @number_updated = 0
        @number_workspace_admins = 0
        @number_subscription_admins = 0
        @logger.info "User affirmed. Proceeding to update permission to #{new_permission} on ALL non-(Sub,Workspace) Admin enabled users in Rally"
        initial_user_query_results.each do | this_user |
            # Do the detailed lookup...
            this_user_hydrated = @uh.find_user(this_user["UserName"])
            grant_project_access(this_user_hydrated, project, new_permission)
        end
        @logger.info "Completed granting Viewer access for all #{@number_updated} non-(Sub,Workspace) Admin enabled users."
        @logger.info "A total of #{@number_subscription_admins} Sub Admins and #{@number_workspace_admins} Workspace Admins will always have full access to Project #{project_name}."

        @logger.info "Done! Viewer-level project access grants completed."
        log_file.close

    rescue Exception => ex
        @logger.error ex.backtrace
        @logger.error ex.message
    end
end