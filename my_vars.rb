$my_username		        = 'user@company.com'
$my_password		        = 'topsecret'
$my_base_url		        = "https://rally1.rallydev.com/slm"

#API Version
$wsapi_version          = "1.41"

# The $enable_cache parameter applies only when using the user_permissions_loader.rb script

# Note: When creating many users, pre-fetching UserPermissions, Workspaces and Projects
# can radically improve performance since it also allows for
# a memory cache of existing Workspace/Projects and Workspace/Project permissions in Rally.
#This avoids the need to go back to Rally with a query in order to check for Workspace/Project existence and
# if a Permission update represents a change with respect to what's already there.
# Doing this in memory makes the code run much faster

# However, when creating/updating only one or two users, the up-front cost of caching is probably more expensive
# than the time saved, so setting this flag to false probably makes sense when creating/updating small
# numbers of users
$enable_cache           = true