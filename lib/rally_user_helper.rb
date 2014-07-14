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

module RallyUserManagement

  require 'rally_api'
  require 'pp'
  require 'date'

  class UserHelper

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
    TEAMMEMBER_YES        = 'Yes'
    TEAMMEMBER_NO         = 'No'

    # Parameters for cache files
    SUB_CACHE           = "_cached_subscription.txt"
    WORKSPACE_CACHE     = "_cached_workspaces.txt"
    PROJECT_CACHE       = "_cached_projects.txt"
    CACHE_COL_DELIM     = "\t"
    CACHE_ROW_DELIM     = "\n"
    CACHE_WRITE_MODE    = "wb"

    SUB_CACHE_FIELDS            =  %w{SubscriptionID Name}
    WORKSPACE_CACHE_FIELDS      =  %w{ObjectID Name State}
    PROJECT_CACHE_FIELDS        =  %w{ObjectID ProjectName State WorkspaceName WorkspaceOID}

    def initialize(config)

      @rally                     = config[:rally_api]
      @rally_json_connection     = @rally.rally_connection
      @logger                    = config[:logger]
      @create_flag               = config[:create_flag]
      @cached_users              = {}
      @cached_sub_id             = 0
      @cached_subscription       = {}
      @cached_workspaces         = {}
      @cached_projects           = {}
      @cached_workspaces_by_name = {}
      @cached_projects_by_name   = {}

      # Provides lookup of projects per workspace
      @workspace_hash_of_projects = {}

      # Maximum age in days of the Workspace/Project cache before refresh
      @max_cache_age = config[:max_cache_age] || 1

      # upgrade_only_mode - when running in upgrade_only_mode, check existing permissions
      # first, and only apply the change if it represents an upgrade over existing permissions
      @upgrade_only_mode = config[:upgrade_only_mode] || false

      # File encoding format
      @file_encoding = config[:file_encoding] || "UTF-8"

      # User filter for ENABLED users only
      # For purposes of speed/efficiency, summarize Enabled Users ONLY
      @summarize_enabled_only = true
      @enabled_only_filter = "(Disabled = \"False\")"

      # fetch data
      @initial_user_fetch            = "UserName,FirstName,LastName,DisplayName"
      @detail_user_fetch             = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,Project,ObjectID,TeamMemberships,UserProfile,SubscriptionAdmin"

    end

    def get_cached_users()
      return @cached_users
    end

    def get_cached_workspaces()
      return @cached_workspaces
    end

    def get_cached_projects()
      return @cached_projects
    end

    def get_workspace_project_hash()
      return @workspace_hash_of_projects
    end

    def get_cached_workspaces_by_nane()
      return @cached_workspaces_by_name
    end

    def get_cached_projects_by_name()
      return @cached_projects_by_name
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
      single_user_query.fetch = @detail_user_fetch
      single_user_query.page_size = 200 #optional - default is 200
      single_user_query.limit = 90000 #optional - default is 99999
      single_user_query.order = "UserName Asc"
      single_user_query.query_string = "(UserName = \"" + name + "\")"

      query_results = @rally.find(single_user_query)

      if query_results.total_result_count == 0
        return nil
      else
        # Cache user for use next time
        this_user = query_results.first
        @cached_users[this_user["UserName"].downcase] = this_user
        @logger.info "Caching User: #{this_user.UserName}"

        return this_user
      end
    end

    # Needed to refresh user object after updates, since user cache is stale after
    # user settings are changed by the helper
    def refresh_user(name)
      single_user_query = RallyAPI::RallyQuery.new()
      single_user_query.type = :user
      single_user_query.fetch = @detail_user_fetch
      single_user_query.page_size = 200 #optional - default is 200
      single_user_query.limit = 90000 #optional - default is 99999
      single_user_query.order = "UserName Asc"
      single_user_query.query_string = "(UserName = \"" + name + "\")"

      query_results = @rally.find(single_user_query)
      if query_results.total_result_count == 0
        return nil
      else
        # Cache user for use next time
        this_user = query_results.first
        @cached_users[this_user["UserName"].downcase] = this_user
        @logger.info "Refreshed User: #{this_user.UserName}"

        return this_user
      end
    end

    #==================== Get a list of OPEN projects in Workspace  ========================
    #
    def get_open_projects (input_workspace)
      project_query                          = RallyAPI::RallyQuery.new()
      project_query.workspace                = input_workspace
      project_query.project                  = nil
      project_query.project_scope_up         = true
      project_query.project_scope_down       = true
      project_query.type                     = :project
      project_query.fetch                    = "Name,State,ObjectID,Workspace,ObjectID"
      project_query.query_string             = "(State = \"Open\")"

      begin
        open_projects     = @rally.find(project_query)
      rescue Exception => ex
        open_projects = nil
      end
      return (open_projects)
    end

    #added for performance
    def cache_users()

      user_query = RallyAPI::RallyQuery.new()
      user_query.type = :user
      user_query.fetch = @initial_user_fetch
      user_query.page_size = 200 #optional - default is 200
      user_query.limit = 90000 #optional - default is 99999
      user_query.order = "UserName Asc"

        # Filter for enabled only
      if @summarize_enabled_only then
        user_query.query_string = @enabled_only_filter
        number_found_suffix = "Enabled Users."
      else
        number_found_suffix = "Users."
      end

      initial_query_results = @rally.find(user_query)

      number_users = initial_query_results.total_result_count
      count = 1
      notify_increment = 25
      @cached_users = {}
      initial_query_results.each do | initial_user |
        notify_remainder=count%notify_increment
        if notify_remainder==0 then @logger.info "Cached #{count} of #{number_users} #{number_found_suffix}" end

        # Follow-up user-by-user query of Rally for Detailed User Properties
        user_query.fetch = @detail_user_fetch

        # Setup query parameters for Rally query of detailed user info
        this_user_name = initial_user["UserName"]
        query_string = "(UserName = \"#{this_user_name}\")"
        user_query.query_string = query_string

        # Query Rally for single-user detailed info, including Permissions, Projects, and
        # Team Memberships
        detail_user_query_results = @rally.find(user_query)

        # If found, cache the user
        number_found = detail_user_query_results.total_result_count
        if number_found > 0 then
          this_user = detail_user_query_results.first
          @cached_users[this_user.UserName] = this_user
          count+=1
        else
          @logger.warn "User: #{this_user_name} not found in follow-up query. Skipping..."
          next
        end

      end
    end

    def find_workspace(object_id)
      if @cached_workspaces.has_key?(object_id)
        # Found workspace in cache, return the cached workspace
        return @cached_workspaces[object_id]
      else
        # workspace not found in cache - go to Rally
        workspace_query                    = RallyAPI::RallyQuery.new()
        workspace_query.project            = nil
        workspace_query.type               = :workspace
        workspace_query.fetch              = "Name,State,ObjectID"
        workspace_query.query_string       = "((ObjectID = \"#{object_id}\") AND (State = \"Open\"))"

        workspace_results                  = @rally.find(workspace_query)

        if workspace_results.total_result_count != 0 then
          # Workspace found via Rally query, return it
          workspace = workspace_results.first()

          # Cache it for use next time
          @cached_workspaces[workspace["ObjectID"]] = workspace
          @logger.info "Caching Workspace: #{workspace['Name']}"

          # Return workspace object
          return workspace
        else
          # Workspace not found in Rally _or_ cache - return Nil
          @logger.warn "Rally Workspace: #{object_id} not found"
          return nil
        end
      end
    end

    def find_workspace_by_name(workspace_name)
      is_duplicate = false
      if @cached_workspaces_by_name.has_key?(workspace_name)
        # Found workspace in cache, return the cached workspace
        if @dup_workspace_names.include?(workspace_name) then
          is_duplicate = true
          @logger.warn "More than one Workspace of name: #{workspace_name} found."
          @logger.warn "Returning only the first instance found!"
        end
        return @cached_workspaces_by_name[workspace_name], is_duplicate
      else
        # workspace not found in cache - go to Rally
        workspace_query                    = RallyAPI::RallyQuery.new()
        workspace_query.project            = nil
        workspace_query.type               = :workspace
        workspace_query.fetch              = "Name,State,ObjectID"
        workspace_query.query_string       = "((Name = \"#{workspace_name}\") AND (State = \"Open\"))"

        workspace_results                  = @rally.find(workspace_query)

        if workspace_results.total_result_count != 0 then
          # Workspace found via Rally query, return it
          workspace = workspace_results.first()

          # Cache it for use next time
          @cached_workspaces_by_name[workspace["Name"]] = workspace
          @logger.info "Caching Workspace: #{workspace['Name']}"

          if workspace_results.total_result_count > 1 then
            # More than one Workspace matching this name found
              is_duplicate = true
              @logger.warn "More than one Workspace of name: #{workspace_name} found."
            @logger.warn "Returning only the first instance found!"
          end

          # Return workspace object
          return workspace, is_duplicate
        else
          # Workspace not found in Rally _or_ cache - return Nil
          @logger.warn "Rally Workspace: #{workspace_name} not found"
          return nil, is_duplicate
        end
      end
    end

    def find_project_by_name(project_name)
      is_duplicate = false
      if @cached_projects_by_name.has_key?(project_name)
        # Found project in cache, return the cached project
        # check to see if it's a duplicate name
        if @dup_project_names.include?(project_name) then
            is_duplicate = true
            @logger.warn "More than one Project of name: #{project_name} found."
            @logger.warn "Returning only the first instance found!"
        end
        return @cached_projects_by_name[project_name], is_duplicate
      else
        # project not found in cache - go to Rally
        project_query                    = RallyAPI::RallyQuery.new()
        project_query.workspace          = nil
        project_query.type               = :project
        project_query.fetch              = "Name,State,ObjectID"
        project_query.query_string       = "((Name = \"#{project_name}\") AND (State = \"Open\"))"

        project_results                  = @rally.find(project_query)

        if project_results.total_result_count != 0 then
          # Workspace found via Rally query, return it
          project = project_results.first()

          # Cache it for use next time
          @cached_projects_by_name[project["Name"]] = project
          @logger.info "Caching Project: #{project['Name']}"

          if project_results.total_result_count > 1 then
            # More than one Project matching this name found
            is_duplicate = true
            @logger.warn "More than one Project of name: #{project_name} found."
            @logger.warn "Returning only the first instance found!"
          end

          # Return project object
          return project, is_duplicate
        else
          # Project not found in Rally _or_ cache - return Nil
          @logger.warn "Rally Project: #{project_name} not found"
          return nil, is_duplicate
        end
      end
    end

    def find_project(object_id)
      if @cached_projects.has_key?(object_id)
        # Found project in cache, return the cached project
        return @cached_projects[object_id]
      else
        # project not found in cache - go to Rally
        project_query                    = RallyAPI::RallyQuery.new()
        project_query.type               = :project
        project_query.fetch              = "Name,State,ObjectID,Workspace,ObjectID"
        project_query.query_string       = "((ObjectID = \"#{object_id}\") AND (State = \"Open\"))"

        project_results                  = @rally.find(project_query)

        if project_results.total_result_count != 0 then
          # Project found via Rally query, return it
          project = project_results.first()

          # Cache it for use next time
          @cached_projects[project["ObjectID"]] = project
          @logger.info "Caching Project: #{project['Name']}"

          # Return it
          return project
        else
          # Project not found in Rally _or_ cache - return Nil
          @logger.warn "Rally Project: #{object_id} not found"
          return nil
        end
      end
    end

    # Check to see if a project is within a particular workspace.
    def is_project_in_workspace(project, workspace)
      test_project_oid = project["ObjectID"]
      this_workspace_oid = workspace["ObjectID"]

      object_id_matches = false
      these_projects = @workspace_hash_of_projects[this_workspace_oid]
      these_projects.each do | this_project |
        this_project_oid = this_project["ObjectID"]
        if test_project_oid == this_project_oid then
          object_id_matches = true
        end
      end
      return object_id_matches
    end

    # Get current SubID
    def get_current_sub_id()

      subscription_query = RallyAPI::RallyQuery.new()
      subscription_query.type = :subscription
      subscription_query.fetch = "Name,SubscriptionID"
      subscription_query.page_size = 200 #optional - default is 200
      subscription_query.limit = 50000 #optional - default is 99999
      subscription_query.order = "Name Asc"

      results = @rally.find(subscription_query)

      this_subscription = results.first
      this_sub_id = this_subscription["SubscriptionID"]

      return this_sub_id
    end

    # Given the name of a file, calculates age of that file
    def calc_file_age(filename)
      today = Time.now

      # Return really big number to prompt refresh if files not found
      file_age = 10000

      if !FileTest.exist?(filename) then
        # Maintain "really big" age and return
        return file_age
      end

      file_reference = File.new(filename, "r")
      # Round fractional days up
      file_age = ((today - file_reference.mtime)/86400).ceil
      return file_age
    end

    # Determine cache age
    def get_cache_age()

      subscription_cache_filename = File.dirname(__FILE__) + "/" + SUB_CACHE
      workspace_cache_filename = File.dirname(__FILE__) + "/" + WORKSPACE_CACHE
      project_cache_filename = File.dirname(__FILE__) + "/" + PROJECT_CACHE

      # Default to really big number to prompt refresh if files not found
      cache_age = 10000

      if !FileTest.exist?(subscription_cache_filename) ||
        !FileTest.exist?(workspace_cache_filename) ||
        !FileTest.exist?(project_cache_filename) then
          # Maintain "really big" age and return
          return cache_age
      end

      age_array = [
        calc_file_age(subscription_cache_filename),
        calc_file_age(workspace_cache_filename),
        calc_file_age(project_cache_filename)
      ]
      min_age = age_array.min

      # return the age of the youngest cache file (should all be the same though)
      cache_age = min_age
      return cache_age
    end

    # Determine whether or not to refresh local sub/workspace/project cache
    def cache_refresh_needed()

      refresh_needed = false
      reason = ""
      subscription_cache_filename = File.dirname(__FILE__) + "/" + SUB_CACHE
      workspace_cache_filename = File.dirname(__FILE__) + "/" + WORKSPACE_CACHE
      project_cache_filename = File.dirname(__FILE__) + "/" + PROJECT_CACHE

      if !FileTest.exist?(subscription_cache_filename) ||
         !FileTest.exist?(workspace_cache_filename) ||
         !FileTest.exist?(project_cache_filename) then
         refresh_needed = true
         reason = "One or more cache files is not found."
         return refresh_needed, reason
      end

      cache_age = get_cache_age()
      if cache_age > @max_cache_age then
        refresh_needed = true
        reason = "Age of workspace/project cache is greater than specified max of #{@max_cache_age}"
        return refresh_needed, reason
      end

      read_subscription_cache()
      cached_subscription_id = @cached_sub_id
      current_subscription_id = get_current_sub_id()

      if current_subscription_id != cached_subscription_id then
        refresh_needed = true
        reason = "Specified SubID: #{current_subscription_id} is different from cached SubID: #{cached_subscription_id}"
        return refresh_needed, reason
      end

      # If we've fallen through to here, no refresh is needed
      reason = "No workspace/project cache refresh currently required"
      return refresh_needed, reason
    end

    # Create ref from oid
    def make_ref_from_oid(object_type, object_id)
      return "/#{object_type}/#{object_id}"
    end

    # Add row to subscription cache
    def cache_subscription_entry(header, row)
      subscription_id                       = row[header[0]].strip
      subscription_name                     = row[header[1]].strip

      this_subscription                     = {}
      this_subscription["SubscriptionID"]   = subscription_id
      this_subscription["Name"]             = subscription_name

      @cached_sub_id                        = subscription_id.to_i
      @cached_subscription[subscription_id] = this_subscription
    end

    # Read subscription cache
    def read_subscription_cache()

      subscription_cache_filename = File.dirname(__FILE__) + "/" + SUB_CACHE
      @logger.info "Started reading subscription cache from #{subscription_cache_filename}"

      # Read in Subscription cache items (should be only 1)
      subscription_cache_input  = CSV.read(subscription_cache_filename, {:col_sep => CACHE_COL_DELIM, :encoding => @file_encoding})

      header = subscription_cache_input.first #ignores first line

      rows   = []
      (1...subscription_cache_input.size).each { |i| rows << CSV::Row.new(header, subscription_cache_input[i]) }

      number_processed = 0

      rows.each do |row|
        if !row.nil? then
          cache_subscription_entry(header, row)
          number_processed += 1
        end
      end

      @logger.info "Completed reading subscription cache from #{subscription_cache_filename}"
    end

    # Add row to workspace cache
    def cache_workspace_entry(header, row)
      workspace_id               = row[header[0]].strip
      workspace_name             = row[header[1]].strip
      workspace_state            = row[header[2]].strip

      this_workspace = {}
      this_workspace["ObjectID"] = workspace_id
      this_workspace["Name"]     = workspace_name
      this_workspace["State"]    = workspace_state
      this_workspace["_ref"]     = make_ref_from_oid("workspace", workspace_id)

      @cached_workspaces[workspace_id] = this_workspace
      if !@cached_workspaces_by_name.has_key?(workspace_name) then
        @cached_workspaces_by_name[workspace_name] = this_workspace
      else
        @logger.warn "  Warning caching Workspace by Name: #{workspace_name}. Duplicate name found!"
        @logger.warn "  Only first instance of this Workspace name will be cached."
      end
    end

    # Read workspace cache
    def read_workspace_cache()

      workspace_cache_filename = File.dirname(__FILE__) + "/" + WORKSPACE_CACHE
      @logger.info "Started reading workspace cache from #{workspace_cache_filename}"

      # Read in workspace cache items (should be only 1)
      workspace_cache_input  = CSV.read(workspace_cache_filename, {:col_sep => CACHE_COL_DELIM, :encoding => @file_encoding})

      header = workspace_cache_input.first #ignores first line

      rows   = []
      (1...workspace_cache_input.size).each { |i| rows << CSV::Row.new(header, workspace_cache_input[i]) }

      number_processed = 0

      rows.each do |row|
        if !row.nil? then
          cache_workspace_entry(header, row)
          number_processed += 1
        end
      end
      @logger.info "Completed reading workspace cache from #{workspace_cache_filename}"
      @logger.info "Read and cached a total of #{number_processed} workspaces from local cache file."
    end

    def cache_project_entry(header, row)
      project_id                   = row[header[0]].strip
      project_name                 = row[header[1]].strip
      project_state                = row[header[2]].strip
      project_workspace_name       = row[header[3]].strip
      project_workspace_oid        = row[header[4]].strip

      this_project = {}
      this_project["ObjectID"]     = project_id
      this_project["Name"]         = project_name
      this_project["State"]        = project_state
      this_project["_ref"]         = make_ref_from_oid("project", project_id)
      this_workspace               = {}
      this_workspace["Name"]       = project_workspace_name
      this_workspace["ObjectID"]   = project_workspace_oid
      this_workspace["_ref"]       = make_ref_from_oid("workspace", project_workspace_oid)
      this_project["Workspace"]    = this_workspace
      @cached_projects[project_id] = this_project

      if !@cached_projects_by_name.has_key?(project_name) then
        @cached_projects_by_name[project_name] = this_project
      else
        @dup_project_names.push(project_name)
        @logger.warn "  Warning caching Project by Name: #{project_name}. Duplicate name found!"
        @logger.warn "  Only first instance of this Project name will be cached."
      end

      return this_project, project_workspace_oid

    end

    # Read project cache
    def read_project_cache()

      project_cache_filename = File.dirname(__FILE__) + "/" + PROJECT_CACHE
      @logger.info "Started reading project cache from #{project_cache_filename}"

      # Read in project cache items (should be only 1)
      project_cache_input  = CSV.read(project_cache_filename, {:col_sep => CACHE_COL_DELIM, :encoding => @file_encoding})

      header = project_cache_input.first #ignores first line

      rows   = []
      (1...project_cache_input.size).each { |i| rows << CSV::Row.new(header, project_cache_input[i]) }

      number_processed = 0

      current_workspace_oid_string = "-9999"
      these_projects = []

      rows.each do |row|
        if !row.nil? then
          this_project, this_workspace_oid = cache_project_entry(header, row)

          # make sure workspace OID is a string
          this_workspace_oid_string = this_workspace_oid.to_s

          if @workspace_hash_of_projects.has_key?(this_workspace_oid_string) then
            these_projects = @workspace_hash_of_projects[this_workspace_oid_string]
          else
            these_projects = []
          end

          these_projects.push(this_project)
          @workspace_hash_of_projects[this_workspace_oid_string] = these_projects

          number_processed += 1
        end

      end
      @logger.info "Completed reading project cache from #{project_cache_filename}"
      @logger.info "Read and cached a total of #{number_processed} projects from local cache file."
    end

    # Write subscription/workspace/project cache
    def write_subscription_cache()

      subscription_cache_filename = File.dirname(__FILE__) + "/" + SUB_CACHE
      @logger.info "Started writing subscription cache to #{subscription_cache_filename}"

      # Output CSV header
      subscription_csv = CSV.open(
        subscription_cache_filename,
        CACHE_WRITE_MODE,
        {:col_sep => CACHE_COL_DELIM, :encoding => @file_encoding}
      )
      subscription_csv << SUB_CACHE_FIELDS

      # Output cache to file
      # Record for CSV output
      @cached_subscription.each_pair do | sub_id, this_subscription |

        data = []
        data << sub_id
        data << this_subscription

        subscription_csv << CSV::Row.new(SUB_CACHE_FIELDS, data)
      end

      @logger.info "Finished writing subscription cache to #{subscription_cache_filename}"
    end

    def write_workspace_cache()
      workspace_cache_filename = File.dirname(__FILE__) + "/" + WORKSPACE_CACHE
      @logger.info "Started writing workspace cache to #{workspace_cache_filename}"

      # Output CSV header
      workspace_csv = CSV.open(
        workspace_cache_filename,
        CACHE_WRITE_MODE,
        {:col_sep => CACHE_COL_DELIM, :encoding => @file_encoding}
      )
      workspace_csv << WORKSPACE_CACHE_FIELDS

      # Output cache to file
      # Record for CSV output
      @cached_workspaces.each_pair do | workspace_id, this_workspace |

        data = []

        workspace_id = this_workspace["ObjectID"]
        workspace_name = this_workspace["Name"]
        workspace_state = this_workspace["State"]

        data << workspace_id
        data << workspace_name
        data << workspace_state

        workspace_csv << CSV::Row.new(WORKSPACE_CACHE_FIELDS, data)
      end

      @logger.info "Finished writing workspace cache to #{workspace_cache_filename}"
    end

    def write_project_cache()
      project_cache_filename = File.dirname(__FILE__) + "/" + PROJECT_CACHE
      @logger.info "Started writing project cache to #{project_cache_filename}"

      # The following results in an array of two-element arrays. The first element of each 2-element array
      # is the ProjectOID, or the key for the project hash. The second element is the value part of the hash
      projects_sorted_by_workspace = @cached_projects.sort_by {|key, value| value["WorkspaceOIDNumeric"]}

      # Output CSV header
      project_csv = CSV.open(
        project_cache_filename,
        CACHE_WRITE_MODE,
        {:col_sep => CACHE_COL_DELIM, :encoding => @file_encoding}
      )
      project_csv << PROJECT_CACHE_FIELDS

      # Output cache to file
      # Record for CSV output
      projects_sorted_by_workspace.each do | project_element |

        this_project = project_element[1]

        data = []

        project_id = this_project["ObjectID"]
        project_name = this_project["Name"]
        project_state = this_project["State"]
        project_workspace = this_project["Workspace"]
        workspace_name = project_workspace["Name"]
        workspace_oid = project_workspace["ObjectID"]

        data << project_id
        data << project_name
        data << project_state
        data << workspace_name
        data << workspace_oid

        project_csv << CSV::Row.new(PROJECT_CACHE_FIELDS, data)
      end

      @logger.info "Finished writing project cache to #{project_cache_filename}"
    end

    def read_workspace_project_cache()
      # Caches by OID
      @cached_subscription = {}
      @cached_workspaces = {}
      @cached_projects = {}

      @cached_workspaces_by_name = {}
      @cached_projects_by_name = {}
      @dup_workspace_names = []
      @dup_project_names = []

      @workspace_hash_of_projects = {}

      read_subscription_cache()
      read_workspace_cache()
      read_project_cache()
    end

    # Added for performance
    def cache_workspaces_projects()
      @cached_subscription = {}
      @cached_workspaces = {}
      @cached_projects = {}

      @cached_workspaces_by_name = {}
      @cached_projects_by_name = {}
      @dup_workspace_names = []
      @dup_project_names = []

      @workspace_hash_of_projects = {}

      subscription_query = RallyAPI::RallyQuery.new()
      subscription_query.type = :subscription
      subscription_query.fetch = "Name,SubscriptionID,Workspaces,Name,State,ObjectID"
      subscription_query.page_size = 200 #optional - default is 200
      subscription_query.limit = 50000 #optional - default is 99999
      subscription_query.order = "Name Asc"

      results = @rally.find(subscription_query)

      # pre-populate workspace hash
      results.each do | this_subscription |

        this_subscription_id = this_subscription["SubscriptionID"]
        @cached_subscription[this_subscription_id] = this_subscription
        @cached_sub_id = this_subscription_id

        @logger.info "This subscription has: #{this_subscription.Workspaces.length} workspaces."

        workspaces = this_subscription.Workspaces
        workspaces.each do |this_workspace|

          this_workspace_oid_string = this_workspace["ObjectID"].to_s

          # Look for open projects within Workspace
          open_projects = get_open_projects(this_workspace)
          @workspace_hash_of_projects[this_workspace_oid_string] = open_projects

          if this_workspace.State != "Closed" && open_projects != nil then
            @logger.info "Caching Workspace:  #{this_workspace['Name']}."
            @cached_workspaces[this_workspace_oid_string] = this_workspace

            if !@cached_workspaces_by_name.has_key?(this_workspace["Name"]) then
              @cached_workspaces_by_name[this_workspace["Name"]]
            else
              @dup_workspace_names.push(this_workspace["Name"])
              @logger.warn "  Warning caching Workspace by Name: #{this_workspace["Name"]}. Duplicate name found!"
              @logger.warn "  Only first instance of this Workspace name will be cached."
            end

            @logger.info "Workspace: #{this_workspace['Name']} has: #{open_projects.length} open projects."

            # Loop through open projects and Cache
            open_projects.each do | this_project |
              this_project["WorkspaceOIDNumeric"] = this_workspace["ObjectID"]
              @cached_projects[this_project.ObjectID.to_s] = this_project

              if !@cached_projects_by_name.has_key?(this_project["Name"]) then
                @cached_projects_by_name[this_project["Name"]] = this_project
              else
                  @dup_project_names.push(this_project["Name"])
                  @logger.warn "  Warning caching Project by Name: #{this_project["Name"]}. Duplicate name found!"
                @logger.warn "  Only first instance of this Project name will be cached."
              end
            end
          else
              @logger.warn "Workspace:  #{this_workspace['Name']} is closed or has no open projects. Not added to cache."
          end
        end
      end

      write_subscription_cache()
      write_workspace_cache()
      write_project_cache()
    end

    # Mirrors ProjectPermission set from a source user to a target user
    # Note that creation of a ProjectPermission will automatically create
    # the minimum needed WorkspacePermission for the "owning" Workspace,
    # if a WorkspacePermission does not already exist. Thus there's
    # no need for a sync_workspace_permissions method
    def sync_project_permissions(source_user_id, target_user_id)
      source_user = find_user(source_user_id)
      target_user = find_user(target_user_id)
      if source_user.nil? then
        @logger.warn "  Source user: #{source_user_id} Not found. Skipping sync of permissions to #{target_user_id}."
        return
      elsif target_user.nil then
        @logger.warn "  Target user: #{target_user_id} Not found. Skipping sync of permissions for #{target_user_id}."
      end

      permissions_existing = target_user.UserPermissions
      source_permissions = source_user.UserPermissions

      # build permission hashes by Project ObjectID
      source_permissions_by_project = {}
      source_permissions.each do | this_source_permission |
        if this_source_permission._type == "ProjectPermission" then
          source_permissions_by_project[this_source_permission.Project.ObjectID.to_s] = this_source_permission
        end
      end

      permissions_existing_by_project = {}
      permissions_existing.each do | this_permission |
        if this_permission._type == "ProjectPermission" then
          permissions_existing_by_project[this_permission.Project.ObjectID.to_s] = this_permission
        end
      end

      # Prepare arrays of permissions to update, create, or delete
      permissions_to_update = []
      permissions_to_create = []
      permissions_to_delete = []

      # Check target permissions list for permissions to create and/or update
      source_permissions_by_project.each_pair do | this_source_project_oid, this_source_permission |

        # If target hash doesn't contain the OID referenced in the source permission set, it's a new
        # permission we need to create
        if !permissions_existing_by_project.has_key?(this_source_project_oid) then
          permissions_to_create.push(this_source_permission)

        # We found the OID key, so there is an existing permission for this Project. Is it different
        # from the target permission?
        else
          this_source_role = this_source_permission.Role
          this_source_project = find_project(this_source_project_oid)
          this_source_project_name = this_source_project["Name"]

          if project_permissions_different?(this_source_project, target_user, this_source_role) then
            existing_permission = permissions_existing_by_project[this_source_project_oid]
            this_existing_project = existing_permission.Project
            this_existing_project_name = this_existing_project["Name"]
            this_existing_role = existing_permission.Role
            @logger.info "Existing Permission: #{this_existing_project_name}: #{this_existing_role}"
            @logger.info "Updated Permission: #{this_source_project_name}: #{this_source_role}"
            permissions_to_update.push(this_source_permission)
          end
        end
      end

      # Loop through target permissions list and check for Project Permissions that don't exist
      # in source permissions template, indicating they need to be removed
      permissions_existing_by_project.each_pair do | this_existing_project_oid, this_existing_permission |
        if !source_permissions_by_project.has_key?(this_existing_project_oid) then
          permissions_to_delete.push(this_existing_permission)
        end
      end

      # Process creates
      number_new_permissions = 0
      permissions_to_create.each do | this_new_permission |
        this_project = find_project(this_new_permission.Project.ObjectID.to_s)
        if !this_project.nil? then

          this_project = this_new_permission.Project
          this_workspace = this_project.Workspace
          this_workspace.read

          this_project_name = this_new_permission.Project.Name
          this_workspace_name = this_workspace.Name

          this_role = this_new_permission.Role

          @logger.info "Workspace: #{this_workspace_name}"
          @logger.info "Creating #{this_role} permission on #{this_project_name} from #{source_user_id} to: #{target_user_id}."
          create_project_permission(target_user, this_project, this_role)
          number_new_permissions += 1
        end
      end

      # Process updates
      number_updated_permissions = 0
      permissions_to_update.each do | this_new_permission |
        this_project = find_project(this_new_permission.Project.ObjectID.to_s)
        if !this_project.nil? then
          this_project = this_new_permission.Project
          this_workspace = this_project.Workspace
          this_workspace.read

          this_project_name = this_new_permission.Project.Name
          this_workspace_name = this_workspace.Name

          this_role = this_new_permission.Role

          @logger.info "Workspace: #{this_workspace_name}"
          @logger.info "Updating #{this_role} permission on #{this_project_name} from #{source_user_id} to: #{target_user_id}."
          create_project_permission(target_user, this_project, this_role)
          number_updated_permissions += 1
        end
      end

      # Process deletes
      number_removed_permissions = 0
      permissions_to_delete.each do | this_deleted_permission |
        this_project = find_project(this_deleted_permission.Project.ObjectID.to_s)
        if !this_project.nil? then
          this_project = this_deleted_permission.Project
          this_workspace = this_project.Workspace
          this_workspace.read

          this_project_name = this_deleted_permission.Project.Name
          this_workspace_name = this_workspace.Name

          this_role = this_deleted_permission.Role

          @logger.info "Workspace: #{this_workspace_name}"
          @logger.info "Removing #{this_role} permission to #{this_project_name} from #{target_user_id} since it is not present on source: #{source_user_id}."
          if !@upgrade_only_mode then
            delete_project_permission(target_user, this_project)
            number_removed_permissions += 1
          else
            @logger.info "  #{target_user_id} - upgrade_only_mode == true."
            @logger.info "  Proposed Permission removal would downgrade permissions. No permission removal applied."
          end
        end
      end
      @logger.info "#{number_new_permissions} Permissions Created; #{number_updated_permissions} Permissions Updated; #{number_removed_permissions} Permissions Removed."
    end

    # Mirrors WorkspacePermission set from a source user to a target user
    def sync_workspace_permissions(source_user_id, target_user_id)
      source_user = find_user(source_user_id)
      target_user = find_user(target_user_id)
      if source_user.nil? then
        @logger.warn "  Source user: #{source_user_id} Not found. Skipping sync of permissions to #{target_user_id}."
        return
      elsif target_user.nil then
        @logger.warn "  Target user: #{target_user_id} Not found. Skipping sync of permissions for #{target_user_id}."
      end

      permissions_existing = target_user.UserPermissions
      source_permissions = source_user.UserPermissions

      # build permission hashes by Workspace ObjectID
      source_permissions_by_workspace = {}
      source_permissions.each do | this_source_permission |
        if this_source_permission._type == "WorkspacePermission" then
          source_permissions_by_workspace[this_source_permission.Workspace.ObjectID.to_s] = this_source_permission
        end
      end

      permissions_existing_by_workspace = {}
      permissions_existing.each do | this_permission |
        if this_permission._type == "WorkspacePermission" then
          permissions_existing_by_workspace[this_permission.Workspace.ObjectID.to_s] = this_permission
        end
      end

      # Prepare arrays of permissions to update, create, or delete
      permissions_to_update = []
      permissions_to_create = []
      permissions_to_delete = []

      # Check target permissions list for permissions to create and/or update
      source_permissions_by_workspace.each_pair do | this_source_workspace_oid, this_source_permission |

        # If target hash doesn't contain the OID referenced in the source permission set, it's a new
        # permission we need to create
        if !permissions_existing_by_workspace.has_key?(this_source_workspace_oid) then
          permissions_to_create.push(this_source_permission)

        # We found the OID key, so there is an existing permission for this Workspace. Is it different
        # from the target permission?
        else
          this_source_role = this_source_permission.Role
          this_source_workspace = find_workspace(this_source_workspace_oid)
          this_source_workspace_name = this_source_workspace["Name"]

          if workspace_permissions_different?(this_source_workspace, target_user, this_source_role) then
            existing_permission = permissions_existing_by_workspace[this_source_workspace_oid]
            this_existing_workspace = existing_permission.Workspace
            this_existing_workspace_name = this_existing_workspace["Name"]
            this_existing_role = existing_permission.Role
            @logger.info "Existing Permission: #{this_existing_workspace_name}: #{this_existing_role}"
            @logger.info "Updated Permission: #{this_source_workspace_name}: #{this_source_role}"
            permissions_to_update.push(this_source_permission)
          end
        end
      end

      # Loop through target permissions list and check for Workspace Permissions that don't exist
      # in source permissions template, indicating they need to be removed
      permissions_existing_by_workspace.each_pair do | this_existing_workspace_oid, this_existing_permission |
        if !source_permissions_by_workspace.has_key?(this_existing_workspace_oid) then
          permissions_to_delete.push(this_existing_permission)
        end
      end

      # Process creates
      number_new_permissions = 0
      permissions_to_create.each do | this_new_permission |
        this_workspace = find_workspace(this_new_permission.Workspace.ObjectID.to_s)
        if !this_workspace.nil? then
          this_workspace_name = this_workspace["Name"]
          this_role = this_new_permission.Role

          @logger.info "Workspace: #{this_workspace_name}"
          @logger.info "Creating #{this_role} permission on #{this_workspace_name} from #{source_user_id} to: #{target_user_id}."
          create_workspace_permission(target_user, this_workspace, this_role)
          number_new_permissions += 1
        end
      end

      # Process updates
      number_updated_permissions = 0
      permissions_to_update.each do | this_new_permission |
        this_workspace = find_workspace(this_new_permission.Workspace.ObjectID.to_s)
        if !this_workspace.nil? then
          this_workspace_name = this_workspace["Name"]
          this_role = this_new_permission.Role

          @logger.info "Workspace: #{this_workspace_name}"
          @logger.info "Updating #{this_role} permission on #{this_workspace_name} from #{source_user_id} to: #{target_user_id}."
          create_workspace_permission(target_user, this_workspace, this_role)
          number_updated_permissions += 1
        end
      end

      # Process deletes
      number_removed_permissions = 0
      permissions_to_delete.each do | this_deleted_permission |
        this_workspace = find_workspace(this_deleted_permission.Workspace.ObjectID.to_s)
        if !this_workspace.nil? then
          this_workspace_name = this_workspace["Name"]
          this_role = this_deleted_permission.Role

          @logger.info "Workspace: #{this_workspace_name}"
          @logger.info "Removing #{this_role} permission to #{this_workspace_name} from #{target_user_id} since it is not present on source: #{source_user_id}."
          if !@upgrade_only_mode then
            delete_workspace_permission(target_user, this_workspace)
            number_removed_permissions += 1
          else
            @logger.info "  #{target_user_id} - upgrade_only_mode == true."
            @logger.info "  Proposed Permission removal would downgrade permissions. No permission removal applied."
          end
        end
      end
      @logger.info "#{number_new_permissions} Permissions Created; #{number_updated_permissions} Permissions Updated; #{number_removed_permissions} Permissions Removed."
    end

      # Mirrors team membership set from a source user to a target user
    def sync_team_memberships(source_user_id, target_user_id)
      source_user = find_user(source_user_id)
      target_user = find_user(target_user_id)
      if source_user.nil? then
        @logger.warn "  Source user: #{source_user_id} Not found. Skipping sync of permissions to #{target_user_id}."
        return
      elsif target_user.nil then
        @logger.warn "  Target user: #{target_user_id} Not found. Skipping sync of permissions for #{target_user_id}."
      end

      memberships_existing = target_user["TeamMemberships"]
      source_memberships = source_user["TeamMemberships"]

      # build membership lists by Project ObjectID
      source_membership_oids = []
      source_memberships.each do | this_source_membership |
        source_membership_oids.push(get_membership_oid_from_membership(this_source_membership))
      end

      memberships_existing_oids = []
      memberships_existing.each do | this_membership |
        memberships_existing_oids.push(get_membership_oid_from_membership(this_membership))
      end

      # build Target User Permissions list by Project ObjectID
      # Needed to make sure that user to whom we're trying to set team membership for
      # is an editor
      permissions_existing = target_user.UserPermissions
      permissions_existing_by_project = {}
      permissions_existing.each do | this_permission |
        if this_permission._type == "ProjectPermission" then
          permissions_existing_by_project[this_permission.Project.ObjectID.to_s] = this_permission
        end
      end

      memberships_to_add = []
      source_membership_oids.each do | this_membership_oid |
        if !memberships_existing_oids.include?(this_membership_oid) then
          memberships_to_add.push(this_membership_oid)
        end
      end

      memberships_to_remove = []
      memberships_existing_oids.each do | this_membership_oid |
        if !source_membership_oids.include?(this_membership_oid) then
          memberships_to_remove.push(this_membership_oid)
        end
      end

      number_memberships_added = 0
      memberships_to_add.each do | this_membership_oid |

        this_permission = permissions_existing_by_project[this_membership_oid]
        if !this_permission.nil? then
          this_role = this_permission.Role
          if !this_role.eql?(EDITOR) && !this_role.eql(PROJECTADMIN) then
            @logger.warn "  Target User: #{target_user_id} must be an Editor or Project Admin to make them a Team Member. Skipping."
            return
          end

          this_project = find_project(this_membership_oid)
          if !this_project.nil? then
            number_memberships_added += 1
            this_project_name = this_project["Name"]
            @logger.info "Updating TeamMembership on #{this_project_name} from #{source_user_id} to: #{target_user_id}."
            update_team_membership(target_user, this_membership_oid, this_project_name, TEAMMEMBER_YES)
          end
        end

      end

      number_memberships_removed = 0
      memberships_to_remove.each do | this_membership_oid |
        this_project = find_project(this_membership_oid)
        if !this_project.nil? then
          number_memberships_removed += 1
          this_project_name = this_project["Name"]
          @logger.info "Removing TeamMembership on #{this_project_name} from #{target_user_id} since source: #{source_user_id} is not a TeamMember."
          update_team_membership(target_user, this_membership_oid, this_project_name, TEAMMEMBER_NO)
        end
      end

      @logger.info "Team Memberships Added: #{number_memberships_added}; Team Memberships Removed: #{number_memberships_removed}"

    end

    def update_workspace_permissions(workspace, user, permission, new_user)
      if new_user or workspace_permissions_different?(workspace, user, permission)
        if @upgrade_only_mode then
          is_upgrade, existing_permission = is_workspace_permission_upgrade?(workspace, user, permission)
          if is_upgrade then
            update_permission_workspacelevel(workspace, user, permission)
          else
            @logger.info "  #{user["UserName"]} #{workspace["Name"]} - upgrade_only_mode == true."
            @logger.warn "  Existing Permission: #{existing_permission}"
            @logger.warn "  Proposed Permission: #{permission}"
            @logger.info "  Proposed Permission change would downgrade permissions. No permission updates applied."
          end
        else
          update_permission_workspacelevel(workspace, user, permission)
        end
      else
        @logger.info "  #{user["UserName"]} #{workspace["Name"]} - Existing/new permission same. No permission updates applied."
      end
    end

    def update_project_permissions(project, user, permission, new_user)
      if new_user or project_permissions_different?(project, user, permission)
        if @upgrade_only_mode then
          is_upgrade, existing_permission = is_project_permission_upgrade?(project, user, permission)
          if is_upgrade then
            update_permission_projectlevel(project, user, permission)
          else
            @logger.warn "  #{user["UserName"]} #{project["Name"]} - upgrade_only_mode == true."
            @logger.warn "  Existing Permission: #{existing_permission}"
            @logger.warn "  Proposed Permission: #{permission}"
            @logger.warn "  Proposed Permission change would downgrade permissions. No permission updates applied."
          end
        else
          update_permission_projectlevel(project, user, permission)
        end
      else
        @logger.info "  #{user["UserName"]} #{project["Name"]} - Existing/new permission same. No permission updates applied."
      end
    end

    def create_user(user_name, fields = user_fields)

      new_user_obj = {}

      new_user_obj["UserName"] = user_name.downcase
      new_user_obj["EmailAddress"] = user_name.downcase

      fields.each_pair do | key, value |
        new_user_obj[key] = value
      end

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

    def update_user(user, fields = user_fields)

      user_name = user["UserName"]
      begin
        if @create_flag
          updated_user = user.update(fields)
        end
        @logger.info "Updated Rally user #{user_name.downcase}"
      rescue
        @logger.error "Error creating user: #{$!}"
        raise $!
      end

      # Grab full object of the created user and return so that we can use it later
      updated_user_query = RallyAPI::RallyQuery.new()
      updated_user_query.type = :user
      updated_user_query.fetch = "UserName,FirstName,LastName,DisplayName,UserPermissions,Name,Role,Workspace,ObjectID,Project,ObjectID,TeamMemberships"
      updated_user_query.query_string = "(UserName = \"#{user_name.downcase}\")"
      updated_user_query.order = "UserName Asc"

      query_results = @rally.find(updated_user_query)
      updated_user_object = query_results.first

      # Cache the new user
      @cached_users[user_name.downcase] = updated_user_object
      return
    end

    def disable_user(user)
      if user.Disabled == 'False'
        if @create_flag
          fields = {}
          fields["Disabled"] = 'False'
          updated_user = @rally.update(:user, user._ref, fields) #by ref
        end

        @logger.info "#{user["UserName"]} disabled in Rally"
      else
        @logger.info "#{user["UserName"]} already disabled from Rally"
        return false
      end
      return true
    end

    def enable_user(user)
      if user.Disabled == 'True'
        fields = {}
        fields["Disabled"] = 'True'
        updated_user = @rally.update(:user, user._ref, fields) if @create_flag
        @logger.info "#{user["UserName"]} enabled in Rally"
        return true
      else
        @logger.info "#{user["UserName"]} already enabled in Rally"
        return false
      end
    end

    # Checks to see if input record is using:
    # Text string (i.e. Editor, Viewer)
    # Or
    # User (i.e. john.doe@company.com)
    # as source of default permissions
    def check_default_permission_type(value)

        type = :stringsource
        if !value.match(/@/).nil? then
            type = :usersource
        end
        return type
    end

    # Pulls Project OID off of team membership _ref
    def get_membership_oid_from_membership(team_membership)
      this_membership_ref = team_membership._ref
      this_membership_oid = this_membership_ref.split("\/")[-1].split("\.")[0]
      return this_membership_oid
    end

    # Checks to see if a user is a Team Member for a particular project
    def is_team_member(project_oid, user)

      # Default values
      is_member = false
      return_value = "No"

      team_memberships = user["TeamMemberships"]

      # First check if team_memberships are nil then loop through and look for a match on
      # Project OID
      if team_memberships != nil then

        team_memberships.each do |this_membership|

          # Grab the Project OID off of the ref URL
          this_membership_oid = get_membership_oid_from_membership(this_membership)
          if this_membership_oid == project_oid then
            is_member = true
          end
        end
      end

      if is_member then return_value = "Yes" end
      return return_value
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
      is_member = is_team_member(project_oid, user)

      url_base = make_team_member_url(this_user_oid, project_oid)

      # if User isn't a team member and update value is Yes then make them one
      if is_member == "No" && team_member_setting.downcase == TEAMMEMBER_YES.downcase then

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
        @logger.info "  #{user["UserName"]} #{project_name} - Team Membership set to #{team_member_setting}"

        # if User is a team member and update value is No then remove them from team
      elsif is_member == "Yes" && team_member_setting.downcase == TEAMMEMBER_NO.downcase then

        # Construct payload object
        my_payload = {}
        my_team_member_setting = {}
        my_team_member_setting ["TeamMember"] = "false"
        my_payload["projectuser"] = my_team_member_setting

        args = {:method => :put}
        args[:payload] = my_payload

        # @rally_json_connection will convert payload object to JSON: {"projectuser":{"TeamMember":"false"}}
        response = @rally_json_connection.send_request(url_base, args)
        @logger.info "  #{user["UserName"]} #{project_name} - Team Membership set to #{team_member_setting}"
      else
        @logger.info "  #{user["UserName"]} #{project_name} - No creation of or changes to Team Membership"
      end
    end

    # Gets a list of users for a specified project.
    # Note - this utilizes un-documented and un-supported Rally endpoint
    # that is not part of WSAPI REST. It also digs down into rally_api to
    # directly GET against this endpoint. This is not guaranteed to work forever
    def get_project_users(project_oid)
        project_users_url = make_project_users_url(project_oid)
        args = {:method => :get}
        params = {:fetch => "UserName", :order=> "UserName ASC"}
        results_json = @rally_json_connection.get_all_json_results(project_users_url, args, params, limit = 99999)

        these_project_users = []
        results = results_json["QueryResult"]["Results"]
        results.each do | this_user_hash |
            username = this_user_hash["UserName"]
            user = find_user(username)
            these_project_users.push(user)
        end
        return these_project_users
    end

    # Create Admin, User, or Viewer permissions for a Workspace
    def create_workspace_permission(user, workspace, permission)
      # Keep backward compatibility of our old permission names
      if permission == VIEWER || permission == EDITOR
        permission = USER
      end

      if permission != NOACCESS
        new_permission_obj = {}
        new_permission_obj["Workspace"] = workspace["_ref"]
        new_permission_obj["User"] = user._ref
        new_permission_obj["Role"] = permission

        if @create_flag then new_permission = @rally.create(:workspacepermission, new_permission_obj) end
      end
    end

    # Check to see if User has _any_ permission within a specific workspace
    def does_user_have_workspace_permission?(workspace, user)
      # set default return value
      workspace_permission_exists = false

      use_cache = false

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if @cached_users != nil then
        if @cached_users.has_key?(user.UserName) then use_cache = true end
      end

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if use_cache then

        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, has it changed
        user_permissions = this_user.UserPermissions
        user_permissions.each do | this_permission |
          if this_permission._type == "WorkspacePermission" then
            if this_permission.Workspace.ObjectID.to_s == workspace["ObjectID"].to_s then
              workspace_permission_exists = true
              break
            end
          end
        end

      else # Cache does not exist or user isn't in it - query info from Rally
        workspace_permission_query = RallyAPI::RallyQuery.new()
        workspace_permission_query.type = :workspacepermission
        workspace_permission_query.fetch = "Workspace,Name,ObjectID,Role,User"
        workspace_permission_query.page_size = 200 #optional - default is 200
        workspace_permission_query.order = "Name Asc"
        workspace_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

        query_results = @rally.find(workspace_permission_query)

        workspace_permission_exists = false

        # Look to see if any existing WorkspacePermissions for this user match the one we're examining
        # If so, check to see if the workspace permissions are any different
        query_results.each { |wp|
          if ( wp.Workspace.ObjectID == workspace["ObjectID"])
            workspace_permission_exists = true
            break
          end
        }
      end
      return workspace_permission_exists
    end

    # Check to see if User has _any_ permission within a specific project
    def does_user_have_project_permission?(project, user)

      # set default return value
      project_permission_exists = false

      use_cache = false

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if @cached_users != nil then
        if @cached_users.has_key?(user.UserName) then use_cache = true end
      end

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if use_cache then

        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, has it changed

        user_permissions = this_user.UserPermissions

        user_permissions.each do |this_permission|

          if this_permission._type == "ProjectPermission" then
            # user has existing permissions in this project - let's compare new role against existing
            if this_permission.Project.ObjectID.to_s == project["ObjectID"].to_s then
              project_permission_exists = true
              break
            end
          end
        end

      else # Cache does not exist or user isn't in it - query info from Rally

        project_permission_query = RallyAPI::RallyQuery.new()
        project_permission_query.type = :projectpermission
        project_permission_query.fetch = "Project,Name,ObjectID,Role,User"
        project_permission_query.page_size = 200 #optional - default is 200
        project_permission_query.order = "Name Asc"
        project_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

        query_results = @rally.find(project_permission_query)

        project_permission_exists = false

        # Look to see if any existing ProjectPermissions for this user match the one we're examining
        # If so, check to see if the project permissions are any different
        query_results.each { |pp|

          if ( pp.Project.ObjectID == project["ObjectID"])
            project_permission_exists = true
            break
          end
        }
      end
      return project_permission_exists
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

    # Creates a project users URL for request against (undocumented, non-WSAPI and non-supported)
    # project users list endpoint.
    # Method: GET
    # URL Format:
    # https://rally1.rallydev.com/slm/webservice/x/project/12345678910/projectusers.js
    def make_project_users_url(input_project_oid)
        rally_url = @rally.rally_url + "/webservice/"
        wsapi_version = @rally.wsapi_version

        make_project_users_url = rally_url + wsapi_version +
            "/project/" + input_project_oid.to_s +
            "/projectusers.js"

        return make_project_users_url
    end

    # check if the new permissions are an upgrade vs. what the user currently has
    def is_project_permission_upgrade?(project, user, new_permission)

      # set default return value
      project_permission_upgrade = false

      # set a default existing_permission conservatively at Project Admin
      existing_permission = PROJECTADMIN_READ
      use_cache = false

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if @cached_users != nil then
        if @cached_users.has_key?(user.UserName) then use_cache = true end
      end

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if use_cache then

        number_matching_projects = 0
        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, is our proposed change an upgrade
        user_permissions = this_user.UserPermissions
        user_permissions.each do | this_permission |

          if this_permission._type == "ProjectPermission" then
            # user has existing permissions in this project - let's compare new role against existing
            if this_permission.Project.ObjectID.to_s == project["ObjectID"].to_s then
              existing_permission = this_permission.Role
              case existing_permission

                # you can't upgrade a PROJECTADMIN, so return false
                when PROJECTADMIN_READ
                  project_permission_upgrade = false
                when EDITOR
                  if new_permission.eql?(PROJECTADMIN_READ) then
                    project_permission_upgrade = true
                  end
                when VIEWER
                  if new_permission.eql?(EDITOR) || new_permission.eql?(PROJECTADMIN_READ) then
                    project_permission_upgrade = true
                  end
                # NOACCESS is denoted by non-existence of a permission so we don't
                # check that here
              end
              number_matching_projects += 1
            end
          end
        end

        # This is a new project permission - set the changed bit to true
        if number_matching_projects == 0 then
           project_permission_upgrade = true
        end

      else # Cache does not exist or user isn't in it - query info from Rally

        project_permission_query = RallyAPI::RallyQuery.new()
        project_permission_query.type = :projectpermission
        project_permission_query.fetch = "Project,Name,ObjectID,Role,User"
        project_permission_query.page_size = 200 #optional - default is 200
        project_permission_query.order = "Name Asc"
        project_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

        query_results = @rally.find(project_permission_query)

        project_permission_upgrade = false
        number_matching_projects = 0

        # Look to see if any existing ProjectPermissions for this user match the one we're examining
        # If so, check to see if the project permissions are any different
        query_results.each { |pp|

          if ( pp.Project.ObjectID == project["ObjectID"])
            number_matching_projects+=1
            existing_permission = pp.Role
            case existing_permission
                # you can't upgrade a PROJECTADMIN, so return false
                when PROJECTADMIN_READ
                    project_permission_upgrade = false
                when EDITOR
                    if new_permission.eql?(PROJECTADMIN_READ) then
                        project_permission_upgrade = true
                    end
                when VIEWER
                    if new_permission.eql?(EDITOR) || new_permission.eql?(PROJECTADMIN_READ) then
                        project_permission_upgrade = true
                    end
                # NOACCESS is denoted by non-existence of a permission so we don't
                # check that here
            end
          end
        }
        # This is a new project permission - set the upgrade bit to true
        if number_matching_projects == 0 then project_permission_upgrade = true end
      end
      return project_permission_upgrade, existing_permission
    end

    def is_workspace_permission_upgrade?(workspace, user, new_permission)

      # set default return values
      workspace_permission_upgrade = false

      # set a default existing_permission conservatively at Admin
      existing_permission = ADMIN
      use_cache = false

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if @cached_users != nil then
        if @cached_users.has_key?(user.UserName) then use_cache = true end
      end

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if use_cache then

        number_matching_workspaces = 0
        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, has it changed
        user_permissions = this_user.UserPermissions
        user_permissions.each do | this_permission |
          if this_permission._type == "WorkspacePermission" then
            if this_permission.Workspace.ObjectID.to_s == workspace["ObjectID"].to_s then
              existing_permission = this_permission.Role
              number_matching_workspaces += 1
              case existing_permission
                # Can't upgrade an admin, so return false
                when ADMIN
                  workspace_permission_upgrade = false
                when USER
                  if new_permission.eql?(ADMIN) then
                    workspace_permission_upgrade = true
                  end
                # No-Access is denoted by an absence of a Permission - we don't need to check that here
              end
            end
          end
        end
        # This is a new workspace permission - set the changed bit to true
        if number_matching_workspaces == 0 then workspace_permission_upgrade = true end

      else # Cache does not exist or user isn't in it - query info from Rally
        workspace_permission_query = RallyAPI::RallyQuery.new()
        workspace_permission_query.type = :workspacepermission
        workspace_permission_query.fetch = "Workspace,Name,ObjectID,Role,User"
        workspace_permission_query.page_size = 200 #optional - default is 200
        workspace_permission_query.order = "Name Asc"
        workspace_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

        query_results = @rally.find(workspace_permission_query)

        workspace_permission_upgrade = false
        number_matching_workspaces = 0

        # Look to see if any existing WorkspacePermissions for this user match the one we're examining
        # If so, check to see if the workspace permissions are any different
        query_results.each { |wp|
          if ( wp.Workspace.ObjectID == workspace["ObjectID"])
            existing_permission = wp.Role
            number_matching_workspaces+=1
            case existing_permission
              # Can't upgrade an admin, so return false
              when ADMIN
                workspace_permission_upgrade = false
              when USER
                if new_permission.eql?(ADMIN) then
                  workspace_permission_upgrade = true
                end
              # No-Access is denoted by an absence of a Permission - we don't need to check that here
            end
          end
        }
        # This is a new workspace permission - set the changed bit to true
        if number_matching_workspaces == 0 then workspace_permission_upgrade = true end
      end
      return workspace_permission_upgrade, existing_permission
    end

    # check if the new permissions are different than what the user currently has
    # if we don't do this, we will delete and recreate permissions each time and that
    # will make the revision history on user really, really, really, really ugly
    def project_permissions_different?(project, user, new_permission)

      # set default return value
      project_permission_changed = false
      use_cache = false

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if @cached_users != nil then
        if @cached_users.has_key?(user.UserName) then use_cache = true end
      end

      if use_cache then
        number_matching_projects = 0
        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, has it changed
        user_permissions = this_user.UserPermissions
        user_permissions.each do | this_permission |

          if this_permission._type == "ProjectPermission" then
            # user has existing permissions in this project - let's compare new role against existing
            if this_permission.Project.ObjectID.to_s == project["ObjectID"].to_s then
              number_matching_projects += 1
              if this_permission.Role != new_permission then
                project_permission_changed = true
              end
            end
          end
        end

        # This is a new project permission - set the changed bit to true
        if number_matching_projects == 0 then
            project_permission_changed = true
        end

      else # Cache does not exist or user isn't in it - query info from Rally

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

          if ( pp.Project.ObjectID == project["ObjectID"])
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

    def workspace_permissions_different?(workspace, user, new_permission)

      # set default return value
      workspace_permission_changed = false

      use_cache = false

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if @cached_users != nil then
        if @cached_users.has_key?(user.UserName) then use_cache = true end
      end

      # first try to lookup against cached user list -- much faster than re-querying Rally
      if use_cache then

        number_matching_workspaces = 0
        this_user = @cached_users[user.UserName]

        # loop through permissions and look to see if there's an existing permission for this
        # workspace, and if so, has it changed
        user_permissions = this_user.UserPermissions
        user_permissions.each do | this_permission |
          if this_permission._type == "WorkspacePermission" then
            if this_permission.Workspace.ObjectID.to_s == workspace["ObjectID"].to_s then
              number_matching_workspaces += 1
              if this_permission.Role != new_permission then workspace_permission_changed = true end
            end
          end
        end
        # This is a new workspace permission - set the changed bit to true
        if number_matching_workspaces == 0 then workspace_permission_changed = true end

      else # Cache does not exist or user isn't in it - query info from Rally
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
          if ( wp.Workspace.ObjectID == workspace["ObjectID"])
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
        new_permission_obj["Workspace"] = this_workspace["_ref"]
        new_permission_obj["Project"] = project["_ref"]
        new_permission_obj["User"] = user._ref
        new_permission_obj["Role"] = permission

        if @create_flag then new_permission = @rally.create(:projectpermission, new_permission_obj) end
      end
    end

    # Project permissions are automatically deleted in this case
    def delete_workspace_permission(user, workspace)

      if @upgrade_only_mode then
        @logger.info "  #{user["UserName"]} #{workspace["Name"]} - upgrade_only_mode == true."
        @logger.warn "  Proposed Permission: #{NOACCESS}"
        @logger.info "  Proposed Permission change would downgrade permissions. No permission updates applied."
        return
      end

      # queries on permissions are a bit limited - to only one filter parameter
      workspace_permission_query = RallyAPI::RallyQuery.new()
      workspace_permission_query.type = :workspacepermission
      workspace_permission_query.fetch = "Workspace,Name,ObjectID,Role,User,UserName"
      workspace_permission_query.page_size = 200 #optional - default is 200
      workspace_permission_query.order = "Name Asc"
      workspace_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

      query_results = @rally.find(workspace_permission_query)

      query_results.each do | this_workspace_permission |

        this_workspace = this_workspace_permission.Workspace
        this_workspace_oid = this_workspace["ObjectID"].to_s

        if this_workspace_permission != nil && this_workspace_oid == workspace["ObjectID"].to_s
          begin
            @rally.delete(this_workspace_permission["_ref"])
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

      if @upgrade_only_mode then
        @logger.info "  #{user["UserName"]} #{project["Name"]} - upgrade_only_mode == true."
        @logger.warn "  Proposed Permission: #{NOACCESS}"
        @logger.info "  Proposed Permission change would downgrade permissions. No permission updates applied."
        return
      end

      # queries on permissions are a bit limited - to only one filter parameter
      project_permission_query = RallyAPI::RallyQuery.new()
      project_permission_query.type = :projectpermission
      project_permission_query.fetch = "Project,Name,ObjectID,Role,User,UserName"
      project_permission_query.page_size = 200 #optional - default is 200
      project_permission_query.order = "Name Asc"
      project_permission_query.query_string = "(User.UserName = \"" + user.UserName + "\")"

      query_results = @rally.find(project_permission_query)
      query_results.each do | this_project_permission |

        this_project = this_project_permission.Project
        this_project_oid = this_project.ObjectID.to_s

        if this_project_permission != nil && this_project_oid == project["ObjectID"].to_s
          begin
            @rally.delete(this_project_permission["_ref"])
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
      @logger.info "  #{user.UserName} #{workspace["Name"]} - Permission set to #{permission}"
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
      @logger.info "  #{user.UserName} #{project["Name"]} - Permission set to #{permission}"
      if permission == PROJECTADMIN_READ
        # Hopefully temporary re-cast of "Admin" to "Project Admin"
        permission = PROJECTADMIN_CREATE
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
end
