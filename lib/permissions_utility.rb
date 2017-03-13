module RallyUserManagement

  require 'rally_api'

  class PermissionUtil

    #Setup constants
    ADMIN                 = 'Admin'
    USER                  = 'User'
    # Different READ and CREATE attributes are imposed by WSAPI
    # Hopefully this is a temporary hack
    PROJECTADMIN_READ     = ADMIN
    PROJECTADMIN_CREATE   = 'Project Admin'
    EDITOR                = 'Editor'
    VIEWER                = 'Viewer'
    NOACCESS              = 'No Access'

    WORKSPACE_ADMIN = 'Workspace Admin'
    SUBSCRIPTION_ADMIN = 'Subscription Admin'

    PROJECT_PERMISSION = 'projectpermission'
    WORKSPACE_PERMISSION = 'workspacepermission'

    VALID_PERMISSIONS = [SUBSCRIPTION_ADMIN, WORKSPACE_ADMIN, ADMIN, EDITOR, USER, VIEWER, NOACCESS ]
    WORKSPACE_VALID_PERMISSIONS = [ADMIN]
    PROJECT_VALID_PERMISSIONS = [PROJECTADMIN_CREATE, EDITOR, VIEWER, NOACCESS]

    def initialize(config)
      @rally = config[:rally_api]
      @logger = config[:logger]

      @logger.info("Initializing Permissions Utility #{@rally}")

    end

    def add_workspace_permission(user, workspace_ref, permission)
      # Keep backward compatibility of our old permission names
      if permission == VIEWER || permission == EDITOR
        permission = USER
      end

      #there really is no reason to add workspace USER permissions...
      if permission == USER
        @logger.info("#{permission} is automatically added when project permissions are added in the workspace. Workspace User will not be explicitly applied for #{user.UserName}")
        return nil
      end

      if (!WORKSPACE_VALID_PERMISSIONS.include?(permission))
        @logger.warn("#{permission} is not a valid permission for a workspace.  No permission applied for #{user.UserName}")
        return nil
      end

      if permission != NOACCESS
        new_permission_obj = {}
        new_permission_obj["Workspace"] = workspace_ref
        new_permission_obj["User"] = user._ref
        new_permission_obj["Role"] = permission

        @logger.info("add_workspace_permission #{user.UserName} #{new_permission_obj}")

        new_permission = @rally.create(WORKSPACE_PERMISSION, new_permission_obj)
        return new_permission
      end
    end

    def add_project_permission(user_obj, workspace_ref, project_ref, permission)
      if permission == USER
        permission = EDITOR
      end

      if permission == ADMIN
        permission = PROJECTADMIN_CREATE
      end

      if (!PROJECT_VALID_PERMISSIONS.include?(permission))
        @logger.warn("add_project_permission:  #{permission} is not a valid permission for a project.  No permission applied for #{user_obj.UserName}.")
        return nil
      end

      @logger.info("Project #{project_ref} #{permission}")

      if permission != NOACCESS
        new_permission_obj = {}
        new_permission_obj["Workspace"] = workspace_ref
        new_permission_obj["Project"] = project_ref
        new_permission_obj["User"] = user_obj._ref
        new_permission_obj["Role"] = permission

        @logger.info("add_project_permission #{user_obj.UserName} #{new_permission_obj}")

        new_permission = @rally.create(PROJECT_PERMISSION, new_permission_obj)
        return new_permission
      end
    end

    def add_project_team_member(user_obj, project_ref)
        team_memberships = user_obj.TeamMemberships

        current_team_memberships = []
        needs_update = true
        ret = 0

        team_memberships.each do |project|
          current_team_memberships.push({"_ref" => project._ref})
          if project._ref == project_ref
            needs_update = false
            @logger.info("add_project_team_member #{user_obj.UserName} has team membership for #{project._refObjectName}")
            break
          end
        end

        if needs_update
          current_team_memberships.push({"_ref" => project_ref})

          @logger.info("add_project_team_member #{user_obj.UserName} #{current_team_memberships}")

          begin
            user_obj.update({ :TeamMemberships =>current_team_memberships })
            ret = current_team_memberships.length
          rescue Exception => ex
            @logger.warn "Cannot update Team Membership for #{user_obj.UserName}: #{ex.message}"
            ret = nil
          end
        end
        return ret
    end

    def replicate_permissions(souce_user_permissions, target_user_obj, force_downgrade = false)

      target_current_permissions = read_user_permissions(target_user_obj.UserName)
      ret = 0
      souce_user_permissions.each do |permission|

        if permission.Role == SUBSCRIPTION_ADMIN
          @logger.warn("Permissions cannot be copied from a Subscription Administrator (#{permission.User}).  Permissions will not be copied to #{target_user_obj.UserName}")
          ret = nil
          break
        end

        current_permission = find_permission(target_current_permissions, permission)
        is_higher = is_higher_privilege?(current_permission, permission)

        if (is_higher && force_downgrade)
          #we need to remove the permission but we can only do this for project permissions.
          @logger.warn("has higher permissions and force downgrade was requested, but we aren't forcing downgrades yet")
          #has_higher set flag to false so that it gets updated
          is_higher = false
        end

        if !is_higher
          workspace_ref = permission.Workspace._ref
          @logger.info("#{permission._type}, #{PROJECT_PERMISSION}")
          if permission._type.downcase == PROJECT_PERMISSION
            project_ref = permission.Project._ref
            addret = add_project_permission(target_user_obj,workspace_ref,project_ref,permission.Role)
          else
            addret = add_workspace_permission(target_user_obj,workspace_ref,permission.Role)
          end
          if !addret.nil?
            ret = ret + 1
          end
        end
      end

      return ret
    end

    def sync_project_permissions(source_user_name, target_user, sync_workspace_permissions = true )

        source_permissions = read_user_permissions(source_user_name)
        if source_permissions.nil?
          @logger.warn("sync_project_permissions SOURCE user #{source_user_name} has no permissions in open projects or the user was not found.")
          return
        end

        if target_user.nil?
          @logger.warn("sync_project_permissions TARGET user is nil.")
          return
        end

        #adding permissions first so that we don't get an error when removing permissions
        replicate_permissions(source_permissions, target_user, true)

        current_permissions = read_user_permissions(target_user.UserName)
        current_permissions.each do |permission|
          if !has_same_permission?(source_permissions, permission)
            delete_permission(permission)
          end
        end

        source_memberships = read_user_team_memberships(source_user_name)

        #we are not using "replicate_team_memberships" becuase we don't want to keep any others.
        replicate_team_memberships(source_memberships, target_user)
    end

    def has_same_permission?(permissions, permission)

      has_same = false
      permissions.each do |p|
        if p._type == permission._type && p.Role == permission.Role &&
            p.Workspace.ObjectID == permission.Workspace.ObjectID
          if p._type.downcase == WORKSPACE_PERMISSION
            has_same = true
            break
          end

          if p._type.downcase == PROJECT_PERMISSION && p.Project.ObjectID = permission.Project.ObjectID
            has_same = true
            break
          end
        end
      end
      return has_same
    end

    def delete_permission(permission)
      success = false
      begin
        @rally.delete(permission._ref)
        success = true
      rescue Exception => ex
        @logger.warn "Cannot remove Permission: #{permission.Name} from #{permission.User}."
        @logger.warn "ProjectPermission either already NoAccess, or would remove the only ProjectPermission in Workspace."
        @logger.warn "User #{permission.User} must have access to at least one Project within the Workspace."
      end
      return success
    end

    def replicate_team_memberships_from_user_name(source_user_name, target_user, keep_existing = true )
        source_team_memberships = read_user_permissions(source_user_name)
        return replicate_team_memberships(source_team_memberships, target_user, keep_existing)
    end

    def replicate_team_memberships(source_team_memberships, target_user_obj, keep_existing = true )

      new_memberships = []
      old_memberships = []
      ret = 0
      if keep_existing
        target_user_obj.TeamMemberships.each do |membership|
          old_memberships.push(membership)
          new_memberships.push({"_ref" => membership._ref})
        end
        @logger.info("replicate_team_memberships #{target_user_obj.UserName} has #{new_memberships.length} team memberships")
      else
        @logger.info("replicate_team_memberships removing existing memberships since keep_original = false")
      end

      source_team_memberships.each do |membership|
        found = old_memberships.find {|m| m._ref == membership._ref }
        @logger.info("replicate_team_memberships found #{found.nil?}, #{membership._ref}")
        if found.nil? || !found
          new_memberships.push({"_ref" => membership._ref })
        end
      end

      if (new_memberships.length > 0)
        begin
          @rally.update('User', target_user_obj.ObjectID, {'TeamMemberships' => new_memberships})
          #target_user_obj.update({:TeamMemberships => new_memberships})
          ret = new_memberships.length
          @logger.info("replicate_team_memberships: updated #{ret} team memberships for #{target_user_obj.UserName}")
        rescue Exception => ex
          @logger.warn "replicate_team_memberships:  Cannot update Team Membership for #{target_user_obj.UserName}: #{ex.message}"
          ret = nil
        end
      end
      return ret
    end

    def read_user_team_memberships(user_name)
      query = RallyAPI::RallyQuery.new()
      query.type = "User"
      query.fetch = "TeamMemberships,Name,Project,ObjectID,State"
      query.query_string = "(UserName = #{user_name})"
      query.limit = 99999

      results = @rally.find(query)
      team_memberships = []
      if results.total_result_count > 0
        results.first.TeamMemberships.each do |p|
          team_memberships.push(p)
        end
      end

      @logger.info("read_user_team_memberships #{user_name} #{team_memberships.length}")
      return team_memberships

    end

    def read_user_permissions(user_name, include_closed_containers = false)

      #automatically remove any closed projects or workspaces from the permissions list
      #unless include_closed_containers = true

      query = RallyAPI::RallyQuery.new()
      query.type = "UserPermission"
      query.fetch = "Name,Role,Workspace,Project,ObjectID,State"
      query.query_string = "(User.UserName = #{user_name})"
      query.limit = 99999

      results = @rally.find(query)
      ret = []
      results.each do |result|
        @logger.info "read_user_permissions Name: #{result.Name}, Type: #{result._type}"

        container_closed = is_container_closed?(result.Workspace) || is_container_closed?(result.Project)
        if (include_closed_containers || !container_closed)
          ret.push(result)
        end
      end

      @logger.info "read_user_permissions results count #{ret.length} "
      return ret
    end

    def is_container_closed?(container)
      if (container.nil?)
        return false
      end

      return container.State == "Closed"
    end

    def find_permission(permissions_objs, permission)
      #we are returning the permission that would correspond to the passed permission
      found_permission = nil
      permissions_objs.each do |po|
        if po._type == permission._type && po.Workspace.ObjectID == permission.Workspace.ObjectID
          if permission._type.downcase == WORKSPACE_PERMISSION.downcase
            found_permission = po
            break
          end

          if po.Project.ObjectID == permission.Project.ObjectID
             found_permission = po
             break
          end
        end
      end
      return found_permission
    end

    def is_higher_privilege?(permission_a, permission_b)

      if permission_a.nil?
        return false
      end

      if permission_b.nil?
        return true
      end

      index_a = VALID_PERMISSIONS.index(permission_a.Role)
      index_b = VALID_PERMISSIONS.index(permission_b.Role)

      if index_b.nil? && index_a.nil?
        return false
      end

      if index_a.nil?
        return false
      end

      if index_b.nil?
        return true
      end

      return index_a < index_b
    end

  end
end