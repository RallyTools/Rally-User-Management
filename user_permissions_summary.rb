#include for rally json library gem
require 'rally_api'
require 'csv'

#Setting custom headers
$headers = RallyAPI::CustomHttpHeader.new()
$headers.name           = "Ruby User Permissions Summary Report"
$headers.vendor         = "Rally Labs"
$headers.version        = "0.10"

#API Version
$wsapi_version          = "1.41"

# constants
$my_base_url            = "https://rally1.rallydev.com/slm"
$my_username            = "user@company.com"
$my_password            = "password"
$my_headers             = $headers
$my_page_size           = 200
$my_limit               = 50000

# Mode options:
# :standard => Outputs permission attributes only
# :extended => Outputs enhanced field list including Enabled/Disabled,NetworkID,Role,CostCenter,Department,OfficeLocation
$summary_mode = :standard

$type_workspacepermission = "WorkspacePermission"
$type_projectpermission   = "ProjectPermission"
$standard_output_fields   =  %w{UserID LastName FirstName DisplayName Type Workspace WorkspaceOrProjectName Role TeamMember ObjectID}
$extended_output_fields   =  %w{UserID LastName FirstName DisplayName Type Workspace WorkspaceOrProjectName Role TeamMember ObjectID Disabled NetworkID Role CostCenter Department OfficeLocation }

$my_output_file           = "user_permissions_summary.txt"
$my_delim                 = "\t"

$initial_fetch            = "UserName,FirstName,LastName,DisplayName"
$standard_detail_fetch    = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,State,Project,ObjectID,State,TeamMemberships"
$extended_detail_fetch    = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,State,Project,ObjectID,State,TeamMemberships,Disabled,NetworkID,Role,CostCenter,Department,OfficeLocation"

$enabled_only_filter = "(Disabled = \"False\")"

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

if $my_delim == nil then $my_delim = "," end

def strip_role_from_permission(str)
  # Removes the role from the Workspace,ProjectPermission String so we're left with just the
  # Workspace/Project Name
  str.gsub(/\bAdmin|\bUser|\bEditor|\bViewer/,"").strip
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
  user_query = RallyAPI::RallyQuery.new()
  user_query.type = :user
  user_query.fetch = $initial_fetch
  user_query.page_size = 200 #optional - default is 200
  user_query.limit = 50000 #optional - default is 99999
  user_query.order = "UserName Asc"
  
  # Filter for enabled only
  if $summarize_enabled_only then
    user_query.query_string = $enabled_only_filter
    number_found_suffix = "Enabled Users."
  else
    number_found_suffix = "Users."
  end

  # Query for users
  puts "Running initial query of users..."

  initial_user_query_results = @rally.find(user_query)
  n_users = initial_user_query_results.total_result_count
  
  # Summarize number of found users
  
  puts "Found a total of #{n_users} " + number_found_suffix
  
  # Set a default value for workspace_name
  workspace_name = "N/A"

  count = 1
  notify_increment = 10

  # loop through all users and output permissions summary
  puts "Summarizing users and writing permission summary output file..."
  
  # Open file for output of summary
  # Output CSV header
  summary_csv = CSV.open($my_output_file, "w", {:col_sep => $my_delim})
  summary_csv << $output_fields
  
  # Run stepwise query of users
  # More expansive fetch on single-user query
  user_query.fetch = $detail_fetch
  
  initial_user_query_results.each do | this_user_init |
    
    # Setup query parameters for Rally query of detailed user info
    this_user_name = this_user_init["UserName"]
    query_string = "(UserName = \"#{this_user_name}\")"
    user_query.query_string = query_string
    
    # Query Rally for single-user detailed info, including Permissions, Projects, and
    # Team Memberships
    detail_user_query_results = @rally.find(user_query)
    
    number_found = detail_user_query_results.total_result_count
    if number_found > 0 then
      this_user = detail_user_query_results.first
      
      # Summarize where we are in processing
      notify_remainder=count%notify_increment
      if notify_remainder==0 then puts "Processed #{count} of #{n_users} " + number_found_suffix end
      count+=1
  
      user_permissions = this_user.UserPermissions
      user_permissions.each do |this_permission|
  
        # Set default for team membership
        team_member = "No"
  
        permission_type = this_permission._type
        if this_permission._type == $type_workspacepermission then
          workspace_name = strip_role_from_permission(this_permission.Name)
          workspace_project_obj = this_permission["Workspace"]
          team_member = "N/A"
          
          # Don't summarize permissions for closed Workspaces
          workspace_state = workspace_project_obj["State"]
          
          if workspace_state == "Closed"
            next          
          end          
  
          # Grab the ObjectID
          object_id = workspace_project_obj["ObjectID"]
        else
          workspace_project_obj = this_permission["Project"]
          
          # Don't summarize permissions for closed Projects
          project_state = workspace_project_obj["State"]
          
          if project_state == "Closed"
            next          
          end  
  
          # Grab the ObjectID
          object_id = workspace_project_obj["ObjectID"]
  
          # Convert OID to a string so is_team_member can do string comparison
          object_id_string = object_id.to_s
  
          # Determine if user is a team member on this project
          these_team_memberships = this_user["TeamMemberships"]
          team_member = is_team_member(object_id_string, these_team_memberships)
        end
  
        # Grab workspace or project name from permission name
        workspace_project_name = strip_role_from_permission(this_permission.Name)
  
        output_record = []
        output_record << this_user.UserName
        output_record << this_user.LastName
        output_record << this_user.FirstName
        output_record << this_user.DisplayName
        output_record << this_permission._type
        output_record << workspace_name
        output_record << workspace_project_name
        output_record << this_permission.Role
        output_record << team_member
        output_record << object_id
        "Disabled,NetworkID,Role,CostCenter,Department,OfficeLocation"
        if $summary_mode == :extended then
          output_record << this_user.Disabled
          output_record << this_user.NetworkID
          output_record << this_user.Role
          output_record << this_user.CostCenter
          output_record << this_user.Department
          output_record << this_user.OfficeLocation
        end
        summary_csv << output_record
      end
      if user_permissions.length == 0
        output_record = []
        output_record << this_user.UserName
        output_record << this_user.LastName
        output_record << this_user.FirstName
        output_record << this_user.DisplayName
        output_record << "N/A"
        output_record << "N/A"
        output_record << "N/A"
        output_record << "N/A"
        output_record << "N/A"
        output_record << "N/A"
        if $summary_mode == :extended then
          output_record << this_user.Disabled
          output_record << this_user.NetworkID         
          output_record << this_user.Role
          output_record << this_user.CostCenter
          output_record << this_user.Department
          output_record << this_user.OfficeLocation
        end        
        summary_csv << output_record
      end
    # User not found in follow-up detail Query - skip this user 
    else
      puts "User: #{this_user_name} not found in follow-up query. Skipping..."
      next
    end        
    
  end

  puts "Done! Permission summary written to #{$my_output_file}."

rescue Exception => ex
  puts ex.backtrace
  puts ex.message
end