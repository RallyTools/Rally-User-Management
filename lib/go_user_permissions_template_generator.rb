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

#include for rally json library gem
fileloc = File.dirname(__FILE__)

require 'rally_api'
require fileloc + '/rally_user_helper.rb'
require fileloc + '/multi_io.rb'
require fileloc + '/version.rb'
require 'csv'
require 'set'
require 'logger'

#Setting custom headers
@user_mgmt_version              = RallyUserManagement::Version.new()
$headers                        = RallyAPI::CustomHttpHeader.new()
$headers.name                   = "Ruby User Management Tool 2"
$headers.vendor                 = "Rally Labs"
$headers.version                = @user_mgmt_version.revision()

#API Version
$wsapi_version                   = "1.43"

# constants
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "password"
$my_headers                      = $headers
$my_page_size                    = 200
$my_limit                        = 50000
$my_output_file                  = "user_permissions_loader_template.txt"
$type_workspacepermission        = "WorkspacePermission"
$type_projectpermission          = "ProjectPermission"

$template_output_fields          =  %w{UserID LastName FirstName DisplayName Type Workspace WorkspaceOrProjectName Role TeamMember ObjectID}

#Setup role constants
$ADMIN = 'Admin'
$USER = 'User'
$EDITOR = 'Editor'
$VIEWER = 'Viewer'
$NOACCESS = 'No Access'
$TEAMMEMBER_YES = 'Yes'
$TEAMMEMBER_NO = 'No'
$TEAMMEMBER_NA = 'N/A'

# symbols
# :type_workspace
# :type_project

# Output file delimiter
$my_delim                     = "\t"

# Encoding
$file_encoding                = "UTF-8"

# Preps output records to write to Permissions Template file
def prep_record_for_export(input_record, type, input_user, permission, is_teammember)

  # input_record is either a workspace or a project

  user_name_sample            = input_user["UserName"]
  last_name_sample            = input_user["LastName"]
  first_name_sample           = input_user["FirstName"]
  display_name_sample         = input_user["DisplayName"]
  workspace_or_project_name   = input_record["Name"]
  workspace_role_sample       = $USER
  project_role_sample         = $EDITOR

  if type == :type_workspace
    permission_type = "WorkspacePermission"
    # Below is needed in order to _repeat_ workspace name in output
    workspace_name            = workspace_or_project_name
    role_sample               = workspace_role_sample
    team_member               = $TEAMMEMBER_NA
  end
  if type == :type_project
    permission_type = "ProjectPermission"

    this_project = input_record
    this_workspace = input_record["Workspace"]
    workspace_name = this_workspace["Name"]
    role_sample = project_role_sample
    team_member = is_teammember
  end

  object_id = input_record["ObjectID"]

  output_data = []
  output_data << user_name_sample
  output_data << last_name_sample
  output_data << first_name_sample
  output_data << display_name_sample
  output_data << permission_type
  output_data << workspace_name
  output_data << workspace_or_project_name
  output_data << permission
  output_data << is_teammember
  output_data << object_id

  return(output_data)

end

def strip_role_from_permission(str)
    # Removes the role from the Workspace,ProjectPermission String so we're left with just the
    # Workspace/Project Name
    str.gsub(/\bAdmin|\bUser|\bEditor|\bViewer/,"").strip
end

# Preps input data from New User List
def process_template(header, row)

  # Assemble User data from input file
  this_user = {}
  this_username_field           = row[header[0]]
  this_lastname_field           = row[header[1]]
  this_firstname_field          = row[header[2]]
  this_displayname_field        = row[header[3]]
  this_defaultpermissions_field = row[header[4]]

  # Check to see if any input fields are nil
  required_field_isnil = false
  required_nil_fields = ""

  if this_username_field.nil? then
    required_field_isnil = true
    required_nil_fields += "UserName"
  else
    target_username = this_username_field.strip
  end

  if this_defaultpermissions_field.nil? then
    required_field_isnil = true
    required_nil_fields += " DefaultPermissions"
  else
    target_defaultpermissions = this_defaultpermissions_field.strip
  end

  if required_field_isnil then
    @logger.warn "One or more required fields: "
    @logger.warn required_nil_fields
    @logger.warn "Is missing! Skipping this row..."
    return
  end

  # Assemble User data from input file
  this_user = {}
  this_user["UserName"]           = target_username
  this_user["DefaultPermissions"] = target_defaultpermissions
  if !this_lastname_field.nil? then
    this_user["LastName"]         = this_lastname_field.strip
  end
  if !this_firstname_field.nil? then
    this_user["FirstName"]        = this_firstname_field.strip
  end
  if !this_displayname_field.nil? then
    this_user["DisplayName"]      = this_displayname_field.strip
  end

  # Check for "type" of DefaultPermissions
  # if field value contains '@' we know that we are copying Default Permissions from
  # an existing user
  default_permission_type = @uh.check_default_permission_type(this_user["DefaultPermissions"])

  if default_permission_type == :stringsource then

      default_permission_string = this_user["DefaultPermissions"]

      # # Loop through open Workspaces, output Workspace information
      $open_workspaces.each_pair do | this_workspace_oid, this_workspace |
        # Output Workspace information
        output_workspace_record = prep_record_for_export(this_workspace, :type_workspace, this_user, $USER, $TEAMMEMBER_NA)
        $template_csv << output_workspace_record

        these_projects = $open_projects[this_workspace_oid]

        # Loop through open Projects, output Permission entries information

        # Default the user to be a team member if they are an Editor
        if $default_permission_string.eql?($EDITOR) && $default_editors_to_team_members then
            team_membership = $TEAMMEMBER_YES
        else
            team_membership = $TEAMMEMBER_NO
        end

        these_projects.each do | this_project |
          output_project_record = prep_record_for_export(this_project, :type_project, this_user,
                                                         default_permission_string, team_membership)
          $template_csv << output_project_record
        end
      end
  else
      # Template user id
      permission_template_username = this_user["DefaultPermissions"]

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
              @logger.warn "User #{permission_source_user} not found in Rally for source of Default Permissions. Skipping new user #{this_user['UserName']}"
              return
          end

          permission_source_user = user_query_results.first
      end

      user_permissions = permission_source_user.UserPermissions
      user_permissions.each do | this_permission |

          # Set default for team membership
          team_member = "No"

          # Grab needed data from query/cache
          permission_type = this_permission._type
          permission_role = this_permission.Role

          if permission_type == $type_workspacepermission then
              workspace_name = strip_role_from_permission(this_permission.Name)
              this_workspace = this_permission["Workspace"]
              team_member = "N/A"

              # Don't summarize permissions for closed Workspaces
              workspace_state = this_workspace["State"]

              if workspace_state == "Closed"
                  next
              end

              output_workspace_record = prep_record_for_export(this_workspace, :type_workspace, this_user,
                                                               permission_role, $TEAMMEMBER_NA)
              $template_csv << output_workspace_record
          else
              this_project = this_permission["Project"]

              # Don't summarize permissions for closed Projects
              project_state = this_project["State"]

              if project_state == "Closed"
                  next
              end

              # Grab the ObjectID
              object_id = this_project["ObjectID"]

              # Convert OID to a string so is_team_member can do string comparison
              object_id_string = object_id.to_s

              # Determine if user is a team member on this project
              team_member = @uh.is_team_member(object_id_string, permission_source_user)

              # Grab workspace or project name from permission name
              workspace_project_name = strip_role_from_permission(this_permission.Name)

              output_project_record = prep_record_for_export(this_project, :type_project, this_user,
                                                             permission_role, team_member)
              $template_csv << output_project_record
          end
      end
  end
end

def go_user_permissions_template_generator(input_file)

  # Load (and maybe override with) my personal/private variables from a file...
  my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
  if FileTest.exist?( my_vars ) then require my_vars end

  # Instantiate logger
  log_file = File.open("user_permissions_template_generator.log", "a")
  if $logger_mode == :stdout then
      @logger = Logger.new RallyUserManagement::MultiIO.new(STDOUT, log_file)
  else
      @logger = Logger.new(log_file)
  end

  #==================== Making a connection to Rally ====================
  config                  = {:base_url => $my_base_url}
  config[:username]       = $my_username
  config[:password]       = $my_password
  config[:version]        = $wsapi_version
  config[:headers]        = $my_headers #from RallyAPI::CustomHttpHeader.new()

  @logger.level = Logger::INFO #DEBUG | INFO | WARNING | FATAL

  @logger.info "Connecting to Rally: #{$my_base_url} as #{$my_username}..."

  @rally = RallyAPI::RallyRestJson.new(config)

  # Instantiate the User Helper
  @logger.info "Instantiating User Helper..."
  uh_config                       = {}
  uh_config[:rally_api]           = @rally
  uh_config[:logger]              = @logger
  uh_config[:create_flag]         = true
  uh_config[:max_cache_age]       = $max_cache_age
  uh_config[:upgrade_only_mode]   = $upgrade_only_mode
  uh_config[:file_encoding]       = $file_encoding

  @uh = RallyUserManagement::UserHelper.new(uh_config)

  @logger.info "Querying Workspace/Projects and caching results..."
  refresh_needed, reason = @uh.cache_refresh_needed()
  if refresh_needed then
    @logger.info "Refresh of Workspace/Project Cache from Rally is required because #{reason}."
    @logger.info "Refreshing Workspace/Project by querying Rally for data."
    @uh.cache_workspaces_projects()
  else
    @logger.info "Reading Workspace/Project info from local cache."
    @uh.read_workspace_project_cache()
  end

  # User Permissions cache
  $user_permissions_cache = {}

  # Workspace and Project caches
  $open_workspaces = @uh.get_cached_workspaces()
  $open_projects = @uh.get_workspace_project_hash()

  # Start output of template
  # Output CSV header
  $template_csv = CSV.open($my_output_file, "wb", {:col_sep => $my_delim, :encoding => $file_encoding})

  # Write the output CSV header
  $template_csv << $template_output_fields

  # Read input CSV for source of User data
  input  = CSV.read($user_list_filename, {:col_sep => $my_delim, :encoding => $file_encoding })

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    process_template(header, row)
  end

  @logger.info "Permission upload template written to #{$my_output_file}."

end