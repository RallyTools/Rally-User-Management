# Copyright 2002-2013 Rally Software Development Corp. All Rights Reserved.

#include for rally json library gem
require 'rally_api'
require 'csv'
require 'set'

#Setting custom headers
$headers                        = RallyAPI::CustomHttpHeader.new()
$headers.name                   = "Ruby User Permissions Template Generator"
$headers.vendor                 = "Rally Labs"
$headers.version                = "0.10"

#API Version
$wsapi_version                   = "1.41"

# constants
$my_base_url                     = "https://rally1.rallydev.com/slm"
$my_username                     = "user@company.com"
$my_password                     = "password"
$my_headers                      = $headers
$my_page_size                    = 200
$my_limit                        = 50000
$my_output_file                  = "user_permissions_loader_template.txt"

$user_list_filename = ARGV[0]

if $user_list_filename == nil
# This is the default for the file containing list of new users to create and load
  $user_list_filename               = 'new_user_list.txt'
end

if File.exists?(File.dirname(__FILE__) + "/" + $user_list_filename) == false
  puts "New user file #{$user_list_filename} not found. Exiting."
  exit
end

$template_output_fields          =  %w{UserID LastName FirstName DisplayName Role OfficeLocation Disabled Type Workspace WorkspaceOrProjectName Role TeamMember ObjectID}
#$template_output_fields          =  %w{UserID LastName FirstName DisplayName Type Workspace WorkspaceOrProjectName Role TeamMember ObjectID}

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

#==================== Get a list of OPEN projects in Workspace  ========================
#
def get_open_projects (input_workspace)
  project_query    		               = RallyAPI::RallyQuery.new()
  project_query.workspace		       = input_workspace
  project_query.project		               = nil
  project_query.project_scope_up	       = true
  project_query.project_scope_down             = true
  project_query.type		               = :project
  project_query.fetch		               = "Name,State,ObjectID,Workspace,Name"
  project_query.query_string	               = "(State = \"Open\")"

  begin
    open_projects   	= @rally.find(project_query)
  rescue Exception => ex
    open_projects = nil
  end
  return (open_projects)
end

# Preps output records to write to Permissions Template file
def prep_record_for_export(input_record, type, input_user)

  # input_record is either a workspace or a project

  user_name_sample            = input_user["UserName"]
  last_name_sample            = input_user["LastName"]
  first_name_sample           = input_user["FirstName"]
  display_name_sample         = input_user["DisplayName"]
  role_sample		      = input_user["Role"]
  office_location_sample      = input_user["OfficeLocation"]
  disabled_sample             = input_user["Disabled"]
  workspace_or_project_name   = input_record["Name"]
  workspace_role_sample       = $USER
  project_role_sample         = $VIEWER

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
  output_data << role_sample
  output_data << office_location_sample
  output_data << disabled_sample
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
  this_user["UserName"]       = row[header[0]].strip
  this_user["LastName"]       = row[header[1]].strip
  this_user["FirstName"]      = row[header[2]].strip
  this_user["DisplayName"]    = row[header[3]].strip
  this_user["Role"]           = row[header[4]].strip
  this_user["OfficeLocation"] = row[header[5]].strip
  this_user["Disabled"]       = row[header[6]].strip
  

  # # Loop through open Workspaces, output Workspace information
  $open_workspaces.each do | this_workspace |
    # Output Workspace information
    output_workspace_record = prep_record_for_export(this_workspace, :type_workspace, this_user)
    $template_csv << output_workspace_record

    these_projects = $open_projects[this_workspace.ObjectID.to_s]

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

  puts "Connecting to Rally: #{$my_base_url} as #{$my_username}..."

  @rally = RallyAPI::RallyRestJson.new(config)

  #==================== Querying Rally ==========================
  # Query for Subscription information.
  #
  subscription_query	            = RallyAPI::RallyQuery.new()
  subscription_query.type	    = :subscription
  subscription_query.fetch          = "Name,Workspaces,Name,ObjectID,State"
  my_subscription		    = @rally.find(subscription_query)

  # Workspace and Project caches
  $open_workspaces = Set.new()
  $open_projects = {}

  # Get all Workspaces in the Subscription
  workspaces = my_subscription.first.Workspaces

  puts "Querying Workspace/Projects and caching results..."
  workspaces.each do | this_workspace |    
    these_projects = get_open_projects(this_workspace)
    if this_workspace.State != "Closed" && these_projects != nil
      # Cache Workspace information
      $open_workspaces.add(this_workspace)

      # Cache Project information
      $open_projects[this_workspace.ObjectID.to_s] = these_projects
    end
  end

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

  puts "Permission upload template written to #{$my_output_file}."

end