# Copyright 2002-2013 Rally Software Development Corp. All Rights Reserved.

#include for rally json library gem
require 'rally_api'
require 'csv'
require 'set'
require 'logger'
require './user_helper.rb'
require './multi_io.rb'

#Setting custom headers
$headers                        = RallyAPI::CustomHttpHeader.new()
$headers.name                   = "Ruby User Permissions Template Generator"
$headers.vendor                 = "Rally Labs"
$headers.version                = "0.20"

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

# Instantiate logger
log_file = File.open("user_template_generator.log", "a")
@logger = Logger.new MultiIO.new(STDOUT, log_file)

$user_list_filename = ARGV[0]

if $user_list_filename == nil
# This is the default for the file containing list of new users to create and load
  $user_list_filename            = 'new_user_list.txt'
end

if File.exists?(File.dirname(__FILE__) + "/" + $user_list_filename) == false
  @logger.info "New user file #{$user_list_filename} not found. Exiting."
  exit
end

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
:type_workspace
:type_project

# Output file delimiter
$my_delim = "\t"

def strip_role_from_permission(str)
  # Removes the role from the Workspace,ProjectPermission String so we're left with just the
  # Workspace/Project Name
  str.gsub(/\bAdmin|\bUser|\bEditor|\bViewer/,"").strip
end

# Preps output records to write to Permissions Template file
def prep_record_for_export(input_record, type, input_user)

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
    workspace_name = workspace_or_project_name
    role_sample = workspace_role_sample
    team_member_sample          = $TEAMMEMBER_NA
  end
  if type == :type_project
    permission_type = "ProjectPermission"

    this_project = input_record
    this_workspace = input_record["Workspace"]
    workspace_name = this_workspace["Name"]
    role_sample = project_role_sample
    team_member_sample = $TEAMMEMBER_YES
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
  output_data << role_sample
  output_data << team_member_sample
  output_data << object_id

  return(output_data)

end

# Preps input data from New User List
def process_template(header, row)

  # Assemble User data from input file
  this_user = {}
  this_user["UserName"]    = row[header[0]].strip
  this_user["LastName"]    = row[header[1]].strip
  this_user["FirstName"]   = row[header[2]].strip
  this_user["DisplayName"] = row[header[3]].strip

  # # Loop through open Workspaces, output Workspace information
  $open_workspaces.each_pair do | this_workspace_oid, this_workspace |
    # Output Workspace information
    output_workspace_record = prep_record_for_export(this_workspace, :type_workspace, this_user)
    $template_csv << output_workspace_record

    these_projects = $open_projects[this_workspace_oid]

    # Loop through open Projects, output Project information
    these_projects.each do | this_project |
      output_project_record = prep_record_for_export(this_project, :type_project, this_user)
      $template_csv << output_project_record
    end
  end
end

begin

  # Load (and maybe override with) my personal/private variables from a file...
  my_vars= File.dirname(__FILE__) + "/my_vars.rb"
  if FileTest.exist?( my_vars ) then require my_vars end

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
  @uh = UserHelper.new(@rally, @logger, true, $max_cache_age)

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

  # Workspace and Project caches
  $open_workspaces = @uh.get_cached_workspaces()
  $open_projects = @uh.get_workspace_project_hash()

  # Start output of template
  # Output CSV header
  $template_csv = CSV.open($my_output_file, "w", {:col_sep => $my_delim})

  # Write the output CSV header
  $template_csv << $template_output_fields

  # Read input CSV for source of User data
  input  = CSV.read($user_list_filename, {:col_sep => $my_delim })

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    process_template(header, row)
  end

  @logger.info "Permission upload template written to #{$my_output_file}."

end