# Copyright 2002-2013 Rally Software Development Corp. All Rights Reserved.

# markwilliams 2012-Jun: Re-written to rally_api and to handle update/import of project permissions
require 'rally_api'
require 'pp'

class Workspace
  def initialize(workspace_name)
    @Name = workspace_name
  end
  def Name
    @Name
  end
end

class Project
  def initialize(project_name, ref)
    @Name = project_name
    @_ref = ref
  end
  def Name
    @Name
  end
  def _ref
    @_ref
  end
end

class UserHelper
  
  #Setup constants
  ADMIN = 'Admin'
  USER = 'User'
  EDITOR = 'Editor'
  VIEWER = 'Viewer'
  NOACCESS = 'No Access'
  TEAMMEMBER_YES = 'Yes'
  TEAMMEMBER_NO = 'No'
  
  def initialize(rally, logger, create_flag = true)
    @rally = rally
    @rally_json_connection = @rally.rally_connection
    @logger = logger 
    @create_flag = create_flag
    @cached_users = {}
    @cached_workspaces = {}
    @cached_projects = {}
  end

  def get_cached_users()
    return @cached_users
  end
  
  # Helper methods
  # Does the user exist? If so, return the user, if not return nil
  # Need to downcase the name since user names are downcased when created. Without downcase, we would not be
  #  able to find 'Mark@acme.com'
  def find_user(name)
    if ( name.downcase != name )
      @logger.info "Looking for #{name.downcase} instead of #{name}"
    end

    if @cached_users.has_key?(name.downcase)
      return @cached_users[name.downcase]
    end

    single_user_query = RallyAPI::RallyQuery.new()
    single_user_query.type = :user
    single_user_query.fetch = "UserName,FirstName,LastName,DisplayName,Disabled,UserPermissions,Name,Role,Project"
    single_user_query.page_size = 200 #optional - default is 200
    single_user_query.limit = 90000 #optional - default is 99999
    single_user_query.order = "UserName Asc"
    single_user_query.query_string = "(UserName = \"" + name + "\")"

    query_results = @rally.find(single_user_query)
    
    if query_results.total_result_count == 0
      return nil
    else
      return query_results.first
    end
  end

  #==================== Get a list of OPEN projects in Workspace  ========================
  #
  def get_open_projects (input_workspace)
    project_query    		                   = RallyAPI::RallyQuery.new()
    project_query.workspace		             = input_workspace
    project_query.project		               = nil
    project_query.project_scope_up	       = true
    project_query.project_scope_down       = true
    project_query.type		                 = :project
    project_query.fetch		                 = "Name,State,ObjectID,Workspace,ObjectID"
    project_query.query_string	           = "(State = \"Open\")"

    begin
      open_projects   	= @rally.find(project_query)
    rescue Exception => ex
      open_projects = nil
    end
    return (open_projects)
  end

  #added for performance
  def cache_users()

    user_query = RallyAPI::RallyQuery.new()
    user_query.type = :user
    user_query.fetch = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,Project,ObjectID,TeamMemberships"
    user_query.page_size = 200 #optional - default is 200
    user_query.limit = 90000 #optional - default is 99999
    user_query.order = "UserName Asc"

    query_results = @rally.find(user_query)

    number_users = query_results.total_result_count
    count = 1
    notify_increment = 25
    @cached_users = {}
    query_results.each do |user|
      notify_remainder=count%notify_increment
      if notify_remainder==0 then @logger.info "Cached #{count} of #{number_users} users" end
      @cached_users[user.UserName] = user
      count+=1
    end
  end

  def find_workspace(object_id)
    if @cached_workspaces.has_key?(object_id)
      # Found workspace in cache, return the cached workspace
      return @cached_workspaces[object_id]
    else
      # workspace not found in cache - go to Rally
      workspace_query    		                   = RallyAPI::RallyQuery.new()
      workspace_query.project		               = nil
      workspace_query.type		                 = :workspace
      workspace_query.fetch		                 = "Name,State,ObjectID"
      workspace_query.query_string	           = "((ObjectID = \"#{object_id}\") AND (State = \"Open\"))"

      workspace_results   	                   = @rally.find(workspace_query)

      if workspace_results.total_result_count != 0 then
        # Workspace found via Rally query, return it
        workspace = workspace_results.first()
        return workspace
      else
        # Workspace not found in Rally _or_ cache - return Nil
        @logger.error "Rally Workspace: #{object_id} not found"
        return nil
      end
    end
  end

  def find_project(object_id)
    if @cached_projects.has_key?(object_id)
      # Found project in cache, return the cached project
      return @cached_projects[object_id]
    else
      # project not found in cache - go to Rally
      project_query    		                   = RallyAPI::RallyQuery.new()
      project_query.type		                 = :project
      project_query.fetch		                 = "Name,State,ObjectID"
      project_query.query_string	           = "((ObjectID = \"#{object_id}\") AND (State = \"Open\"))"

      project_results   	                   = @rally.find(project_query)

      if project_results.total_result_count != 0 then
        # Project found via Rally query, return it
        project = project_results.first()
        return project
      else
        # Project not found in Rally _or_ cache - return Nil
        @logger.error "Rally Project: #{object_id} not found"
        return nil
      end
    end
  end

  # Added for performance
  def cache_workspaces_projects()

    @cached_workspaces = {}
    @cached_projects = {}

    subscription_query = RallyAPI::RallyQuery.new()
    subscription_query.type = :subscription
    subscription_query.fetch = "Name,SubscriptionID,Workspaces,Name,State,ObjectID"
    subscription_query.page_size = 200 #optional - default is 200
    subscription_query.limit = 50000 #optional - default is 99999
    subscription_query.order = "Name Asc"

    results = @rally.find(subscription_query)

    # pre-populate workspace hash
    results.each do |this_subscription|

      @logger.info "This subscription has: #{this_subscription.Workspaces.length} workspaces."

      workspaces = this_subscription.Workspaces
      workspaces.each do |this_workspace|

        # Look for open projects within Workspace
        open_projects = get_open_projects(this_workspace)

        if this_workspace.State != "Closed" && open_projects != nil then
          @logger.info "Caching Workspace:  #{this_workspace.Name}."
          @cached_workspaces[this_workspace.ObjectID.to_s] = this_workspace
          @logger.info "Workspace: #{this_workspace.Name} has: #{open_projects.length} open projects."

          # Loop through open projects and Cache
          open_projects.each do | this_project |
            @logger.info "Caching Project: #{this_project.Name}"
            @cached_projects[this_project.ObjectID.to_s] = this_project
          end
        else
            @logger.warn "Workspace:  #{this_workspace.Name} is closed or has no open projects. Not added to cache."
        end
      end
    end

  end
  
  def update_workspace_permissions(workspace, user, permission, new_user)
    if new_user or workspace_permissions_updated?(workspace, user, permission)
      update_permission_workspacelevel(workspace, user, permission)
    else
      @logger.info "  #{user.UserName} #{workspace.Name} - No permission updates"
    end
  end

  def update_project_permissions(project, user, permission, new_user)
    if new_user or project_permissions_updated?(project, user, permission)
      update_permission_projectlevel(project, user, permission)
    else
      @logger.info "  #{user.UserName} #{project.Name} - No permission updates"
    end
  end
  
  def create_user(user_name, display_name, first_name, last_name)

    new_user_obj = {}

    new_user_obj["UserName"] = user_name.downcase
    new_user_obj["EmailAddress"] = user_name.downcase
    new_user_obj["DisplayName"] = display_name
    new_user_obj["FirstName"] = first_name
    new_user_obj["LastName"] = last_name

    new_user = nil

    begin
      if @create_flag
        new_user = @rally.create(:user, new_user_obj)
      end
      @logger.info "Created Rally user #{user_name.downcase}"
    rescue
      @logger.error "Error creating user: #{$!}"
      raise $!
    end

    # Grab full object of the created user and return so that we can use it later
    new_user_query = RallyAPI::RallyQuery.new()
    new_user_query.type = :user
    new_user_query.fetch = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,Project,ObjectID,TeamMemberships"
    new_user_query.query_string = "(UserName = \"#{user_name.downcase}\")"
    new_user_query.order = "UserName Asc"

    query_results = @rally.find(new_user_query)
    new_user_created = query_results.first

    # Cache the new user
    @cached_users[user_name.downcase] = new_user_created

    return new_user_created
  end

  def disable_user(user)
    if user.Disabled == 'False'
      if @create_flag
        fields = {}
        fields["Disabled"] = 'False'
        updated_user = @rally.update(:user, user._ref, fields) #by ref
      end
      
      @logger.info "#{user.UserName} disabled in Rally"
    else
      @logger.info "#{user.UserName} already disabled from Rally"
      return false
    end   
    return true
  end
  
  def enable_user(user)
    if user.Disabled == 'True'
      fields = {}
      fields["Disabled"] = 'True'
      updated_user = @rally.update(:user, user._ref, fields) if @create_flag
      @logger.info "#{user.UserName} enabled in Rally"
      return true
    else
      @logger.info "#{user.UserName} already enabled in Rally"
      return false
    end
  end

  # Updates team membership. Note - this utilizes un-documented and un-supported Rally endpoint
  # that is not part of WSAPI REST
  # it also digs down into rally_api to directly PUT against this endpoint
  # not guaranteed to work forever

  def update_team_membership(user, project_oid, project_name, team_member_setting)

    # look up user
    these_team_memberships = user["TeamMemberships"]
    this_user_oid = user["ObjectID"]

    # Default for whether user is member or not
    is_member = false

    # loop through team memberships to see if User is already a member
    if these_team_memberships != nil then
      these_team_memberships.each do |this_membership|

        this_membership_ref = this_membership._ref
        this_membership_oid = this_membership_ref.split("\/")[-1].split("\.")[0]

        if this_membership_oid == project_oid then
          is_member = true
        end
      end
    end

    url_base = make_team_member_url(this_user_oid, project_oid)

    # if User isn't a team member and update value is Yes then make them one
    if is_member == false && team_member_setting.downcase == TEAMMEMBER_YES.downcase then

      # Construct payload object
      my_payload = {}
      my_team_member_setting = {}
      my_team_member_setting ["TeamMember"] = "true"
      my_payload["projectuser"] = my_team_member_setting

      args = {:method => :put}
      args[:payload] = my_payload

      # @rally_json_connection does a to_json on object to convert
      # payload object to JSON: {"projectuser":{"TeamMember":"true"}}
      response = @rally_json_connection.send_request(url_base, args)
      @logger.info "  #{user.UserName} #{project_name} - Team Membership set to #{team_member_setting}"

      # if User is a team member and update value is No then remove them from team
    elsif is_member == true && team_member_setting.downcase == TEAMMEMBER_NO.downcase then

      # Construct payload object
      my_payload = {}
      my_team_member_setting = {}
      my_team_member_setting ["TeamMember"] = "false"
      my_payload["projectuser"] = my_team_member_setting

      args = {:method => :put}
      args[:payload] = my_payload

      # @rally_json_connection will convert payload object to JSON: {"projectuser":{"TeamMember":"false"}}
      response = @rally_json_connection.send_request(url_base, args)
      @logger.info "  #{user.UserName} #{project_name} - Team Membership set to #{team_member_setting}"
    else
      @logger.info "  #{user.UserName} #{project_name} - No changes to Team Membership"
    end
  end
  
  # Create Admin, User, or Viewer permissions for a Workspace
  def create_workspace_permission(user, workspace, permission)
    # Keep backward compatibility of our old permission names
    if permission == VIEWER || permission == EDITOR
      permission = USER
    end

    if permission != NOACCESS
      new_permission_obj = {}
      new_permission_obj["Workspace"] = workspace._ref
      new_permission_obj["User"] = user._ref
      new_permission_obj["Role"] = permission

      if @create_flag then new_permission = @rally.create(:workspacepermission, new_permission_obj) end
    end
  end
  
  #--------- Private methods --------------
  private
  
  # Takes the name of the permission and returns the last token which is the permission
  def parse_permission(name)
    if name.reverse.index(VIEWER.reverse)
      return VIEWER
    elsif name.reverse.index(EDITOR.reverse)
      return EDITOR
    elsif name.reverse.index(USER.reverse)
      return USER
    elsif name.reverse.index(ADMIN.reverse)
      return ADMIN
    else
      @logger.info "Error in parsing permission"
    end
    nil
  end

  # Creates a team membership URL for request against (undocumented, non-WSAPI and non-supported)
  # team membership endpoint.
  # Method: PUT
  # URL Format:
  # https://rally1.rallydev.com/slm/webservice/x/project/12345678910/projectuser/12345678911.js
  # Payload: {"projectuser":{"TeamMember":"true"}}
  # Where 12345678910 => Project OID
  # And   12345678911 => User OID

  def make_team_member_url(input_user_oid, input_project_oid)

    rally_url = @rally.rally_url + "/webservice/"
    wsapi_version = @rally.wsapi_version

    make_team_member_url = rally_url + wsapi_version +
        "/project/" + input_project_oid.to_s +
        "/projectuser/" + input_user_oid.to_s + ".js"

    return make_team_member_url
  end
  
  # check if the new permissions are different than what the user currently has
  # if we don't do this, we will delete and recreate permissions each time and that
  # will make the revision history on user really, really, really, really ugly
  def project_permissions_updated?(project, user, new_permission)

    # set default return value
    project_permission_changed = false

    # first try to lookup against cached user list -- much faster than re-querying Rally
    if @cached_users != nil then

      number_matching_projects = 0

      # Pull user from cached users hash
      if @cached_users.has_key?(user.UserName) then

        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, has it changed

        user_permissions = this_user.UserPermissions

        user_permissions.each do |this_permission|
          if this_permission._type == "ProjectPermission" then
            # user has existing permissions in this project - let's compare new role against existing
            if this_permission.Project.ObjectID == project.ObjectID then
              number_matching_projects += 1
              if this_permission.Role != new_permission then
                project_permission_changed = true
              end
            end
          end
        end

        # This is a new project permission - set the changed bit to true
        if number_matching_projects == 0 then project_permission_changed = true end

      else # User isn't in user cache - this is a new user with all new permissions - set changed bit to true
        project_permission_changed = true
      end

    else # no cached users - query info from Rally
      puts "Got to ProjectPermission Comparison of Rally Lookup of UserPermissions"

      project_permission_query = RallyAPI::RallyQuery.new()
      project_permission_query.type = :projectpermission
      project_permission_query.fetch = "Project,Name,ObjectID,Role,User"
      project_permission_query.page_size = 200 #optional - default is 200
      project_permission_query.order = "Name Asc"
      project_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

      query_results = @rally.find(project_permission_query)

      project_permission_changed = false
      number_matching_projects = 0

      # Look to see if any existing ProjectPermissions for this user match the one we're examining
      # If so, check to see if the project permissions are any different
      query_results.each { |pp|

        if ( pp.Project.ObjectID == project.ObjectID)
          number_matching_projects+=1
          if pp.Role != new_permission then project_permission_changed = true end
        end
      }
      # This is a new project permission - set the changed bit to true
      if number_matching_projects == 0 then project_permission_changed = true end
    end
    return project_permission_changed
  end
  
  # check if the new permissions are different than what the user currently has
  # if we don't do this, we will delete and recreate permissions each time and that
  # will make the revision history on user really, really, really, really ugly

  def workspace_permissions_updated?(workspace, user, new_permission)

    # set default return value
    workspace_permission_changed = false

    # first try to lookup against cached user list -- much faster than re-querying Rally
    if @cached_users != nil then

      number_matching_workspaces = 0

      # Pull user from cached users hash
      if @cached_users.has_key?(user.UserName) then
        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, has it changed
        user_permissions = this_user.UserPermissions
        user_permissions.each do |this_permission|
          if this_permission._type == "WorkspacePermission" then
            if this_permission.Workspace.ObjectID == workspace.ObjectID then
              number_matching_workspaces += 1
              if this_permission.Role != new_permission then workspace_permission_changed = true end
            end
          end
        end
        # This is a new workspace permission - set the changed bit to true
        if number_matching_workspaces == 0 then workspace_permission_changed = true end
      else # User isn't in user cache - this is a new user with all new permissions - set changed bit to true
        workspace_permission_changed = true
      end

    else # no cached users - query info from Rally
      workspace_permission_query = RallyAPI::RallyQuery.new()
      workspace_permission_query.type = :workspacepermission
      workspace_permission_query.fetch = "Workspace,Name,ObjectID,Role,User"
      workspace_permission_query.page_size = 200 #optional - default is 200
      workspace_permission_query.order = "Name Asc"
      workspace_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

      query_results = @rally.find(workspace_permission_query)

      workspace_permission_changed = false
      number_matching_workspaces = 0

      # Look to see if any existing WorkspacePermissions for this user match the one we're examining
      # If so, check to see if the workspace permissions are any different
      query_results.each { |wp|
        if ( wp.Workspace.ObjectID == workspace.ObjectID)
          number_matching_workspaces+=1
          if wp.Role != new_permission then workspace_permission_changed = true end
        end
      }
      # This is a new workspace permission - set the changed bit to true
      if number_matching_workspaces == 0 then workspace_permission_changed = true end
    end
    return workspace_permission_changed
  end
  
  # Create User or Viewer permissions for a Project
  def create_project_permission(user, project, permission)
  # Keep backward compatibility of our old permission names
    if permission == USER
      permission = EDITOR
    end

    if permission != NOACCESS
      this_workspace = project["Workspace"]
      new_permission_obj = {}
      new_permission_obj["Workspace"] = this_workspace._ref
      new_permission_obj["Project"] = project._ref
      new_permission_obj["User"] = user._ref
      new_permission_obj["Role"] = permission

      if @create_flag then new_permission = @rally.create(:projectpermission, new_permission_obj) end
    end
  end
  
  # Project permissions are automatically deleted in this case
  # TODO: There may be a bug in removing permissions once you have them, not sure though
  def delete_workspace_permission(user, workspace)
    # queries on permissions are a bit limited - to only one filter parameter
    workspace_permission_query = RallyAPI::RallyQuery.new()
    workspace_permission_query.type = :workspacepermission
    workspace_permission_query.fetch = "Workspace,Name,ObjectID,Role,User,UserName"
    workspace_permission_query.page_size = 200 #optional - default is 200
    workspace_permission_query.order = "Name Asc"
    workspace_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

    query_results = @rally.find(workspace_permission_query)

    query_results.each do |this_workspace_permission|

      this_workspace = this_workspace_permission.Workspace
      this_workspace_oid = this_workspace.ObjectID

      if this_workspace_permission != nil && this_workspace_oid == workspace.ObjectID
        begin
          this_workspace_permission.delete
        rescue Exception => ex
          this_user = this_workspace_permission.User
          this_user_name = this_user.Name

          @logger.warn "Cannot remove WorkspacePermission: #{this_workspace_permission.Name}."
          @logger.warn "WorkspacePermission either already NoAccess, or would remove the only WorkspacePermission in Subscription."
          @logger.warn "User #{this_user_name} must have access to at least one Workspace within the Subscription."
        end
      end
    end
  end

  def delete_project_permission(user, project)
    # queries on permissions are a bit limited - to only one filter parameter
    project_permission_query = RallyAPI::RallyQuery.new()
    project_permission_query.type = :projectpermission
    project_permission_query.fetch = "Project,Name,ObjectID,Role,User,UserName"
    project_permission_query.page_size = 200 #optional - default is 200
    project_permission_query.order = "Name Asc"
    project_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

    query_results = @rally.find(project_permission_query)

    query_results.each do |this_project_permission|

      this_project = this_project_permission.Project
      this_project_oid = this_project.ObjectID

      if this_project_permission != nil && this_project_oid == project.ObjectID
        begin
          this_project_permission.delete
        rescue Exception => ex
          this_user = this_project_permission.User
          this_user_name = this_user.Name

          @logger.warn "Cannot remove ProjectPermission: #{this_project_permission.Name}."
          @logger.warn "ProjectPermission either already NoAccess, or would remove the only ProjectPermission in Workspace."
          @logger.warn "User #{this_user_name} must have access to at least one Project within the Workspace."
        end
      end
    end
  end
  
  def update_permission_workspacelevel(workspace, user, permission)
    @logger.info "  #{user.UserName} #{workspace.Name} - Permission set to #{permission}"
    if permission == ADMIN
      create_workspace_permission(user, workspace, permission)
    elsif permission == NOACCESS
      delete_workspace_permission(user, workspace)
    elsif permission == USER || permission == VIEWER || permission == EDITOR
      create_workspace_permission(user, workspace, permission)
    else
      @logger.error "Invalid Permission - #{permission}"
    end
  end

  def update_permission_projectlevel(project, user, permission)
    @logger.info "  #{user.UserName} #{project.Name} - Permission set to #{permission}"
    if permission == ADMIN
      create_project_permission(user, project, permission)
    elsif permission == NOACCESS
      delete_project_permission(user, project)
    elsif permission == USER || permission == VIEWER || permission == EDITOR
      create_project_permission(user, project, permission)
    else
      @logger.error "Invalid Permission - #{permission}"
    end
  end

end