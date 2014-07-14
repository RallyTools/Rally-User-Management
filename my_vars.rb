$my_username                = 'subadmin@companv.com'
$my_password                = 'topsecret'
$my_base_url                = 'https://rally1.rallydev.com/slm'

#API Version
$wsapi_version              = '1.43'

# User-configurable settings:
#============================

# Parameter:
# $user_update_mode
#
# Scripts Using this Parameter:
# change_usernames.rb
#
# Description:
# Toggles mode for User update. See Valid Settings.
#
# Valid Settings:
# :usernameandemail => resets both UserName and Email to the updated value
# :usernameonly => only resets UserName. Email address remains unchanged
$user_update_mode           = :usernameandemail

# Parameter:
# $max_cache_age
#
# Scripts Using:
# user_permissions_loader.rb
# user_permissions_template_generator.rb
#
# Description:
# Maximum age of workspace/project cache in days before triggering
# automatic refresh. Setting $max_cache_age = 0 will force refresh
# every time user does a run.
#
# Note: keeping local cache of workspaces/projects improves
# speed if you're doing multiple runs in a single work session
$max_cache_age              = 1

# Parameter:
# $enable_user_cache
#
# Scripts Using:
# user_permissions_loader.rb

# Description: When creating or updating many users, pre-fetching UserPermissions
# can sometimes improve performance. However, for large subscriptions and in general
# when creating/updating only one or two users, the up-front cost of caching is
# probably more expensive than the time saved, so setting this flag to false
# probably makes sense when creating/updating small numbers of users
$enable_user_cache          = false

# Parameter:
# $summary_mode
#
# Scripts Using this Parameter:
# user_permissions_summary.rb
#
# Description:
# Toggles output mode for User Permissions Summary Output. See Valid Settings.
#
# Valid Settings:
# :standard => Outputs permission attributes only
# :extended => Outputs enhanced field list including:
#              LastLoginDate
#              Enabled/Disabled
#              NetworkID
#              Role
#              CostCenterDepartment
#              OfficeLocation
$summary_mode               = :standard

# Parameter:
# $summarize_enabled_only
#
# Scripts Using this Parameter:
# user_permissions_summary.rb
#
# Description:
# Summarizes permissions for only Enabled users when true
#
# Valid Settings:
# $summarize_enabled_only = true
# $summarize_enabled_only = false
$summarize_enabled_only     = true

# Parameter:
# $sync_team_memberships
#
# Scripts Using this Parameter:
# user_permissions_syncer.rb
#
# Description:
# Synchronizes team memberships between source and target users, in addition
# to user permissions, when true
#
# Valid Settings:
# $sync_team_memberships = true
# $sync_team_memberships = false
$sync_team_memberships              = true

# Parameter:
# $sync_workspace_permissions
#
# Scripts Using this Parameter:
# user_permissions_syncer.rb
#
# Description:
# Synchronizes Workspace permissions between source and target users, in addition
# to project permissions, when true
#
# Valid Settings:
# $sync_workspace_permissions = true
# $sync_workspace_permissions = false
$sync_workspace_permissions         = false

# Parameter:
# $sync_project_permissions
#
# Scripts Using this Parameter:
# user_permissions_syncer.rb
#
# Description:
# Synchronizes Project permissions between source and target users, in addition
# to project permissions, when true
#
# Valid Settings:
# $sync_project_permissions = true
# $sync_project_permissions = false
$sync_project_permissions           = true

# Parameter:
# $upgrade_only_mode

# Scripts Using this Parameter:
# user_permissions_loader.rb

# Description:
# When running with $upgrade_only_mode == true, the script will check existing permissions before applying a change.
# It will then apply the change _only_ if the proposed permissions are an upgrade in comparison to existing permissions.

# Example one:
# Existing Permissions: Viewer
# Proposed Permissions: Editor
# Permission change occurs

# Example two:
# Existing Permissions: Editor
# Proposed Permissions: Viewer
# NO Permission change occurs

# This is convenient when seeking to grant Viewer level access to all users, without downgrading
# existing editors, as an example

# Valid Settings:
# $upgrade_only_mode = true
# $upgrade_only_mode = false
$upgrade_only_mode                  = false

# Parameter:
# $file_encoding
#
# Scripts Using this Parameter:
# change_usernames.rb
# enable_or_disable_users.rb
# ldap_username_load.rb
# simple_user_loader.rb
# update_project_permissions.rb
# update_user_attributes.rb
# user_helper.rb
# user_permissions_loader.rb
# user_permissions_summary.rb
# user_permissions_syncer.rb
# user_permissions_template_generator.rb
# user_team_membership_summary.rb
#
# Description
# Sets character encoding to use when reading/writing files
# Valid Settings (examples):
#
# $file_encoding = 'US-ASCII'
# $file_encoding = 'UTF-8'
$file_encoding                      = 'UTF-8'

# Parameter:
# $logger_mode
#
# Scripts Using this Parameter:
# simple_user_loader.rb
# update_user_attributes.rb
# user_helper.rb
# user_permissions_loader.rb
# user_permissions_summary.rb
# user_permissions_syncer.rb
# user_permissions_template_generator.rb
# user_team_membership_summary.rb
#
# Description
# Specifies whether to send log output to stdout AND log, or to file only
# Valid Settings (examples):
#
# $logger_mode = :stdout
# $logger_mode = :file
$logger_mode                        = :stdout

# Parameter:
# $ignore_default_permissions
#
# Scripts Using this Parameter:
# simple_user_loader.rb
#
# Description
# Rally allows Workspace and Project Admins to set a Default Permission that New Users will receive
# for the Workspace or Project of interest. This means that users created by any Rally admin
# will receive permissions into these Workspaces or Projects, irrespective of whether or not the
# creating admin intends this, or, has permissions to the Default Workspace,Project of interest
#
# When this flag is set to true, Users provisioned via the simple_user_loader.rb script will ignore
# the Default Workspace,Project permissions, and will receive _only_ those permissions specified
# via the input file (via the source user permissions, for example)
# NOTE: $upgrade_only_mode MUST also be set to false for this parameter to function as expected
#
# $ignore_default_permissions = false
# $ignore_default_permissions = true
$ignore_default_permissions        = false