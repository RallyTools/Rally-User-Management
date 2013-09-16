$my_username		        = 'mdwilliams@rallydev.com'
$my_password		        = '970R@lly$mdw'
$my_base_url		        = "https://rally1.rallydev.com/slm"

#API Version
$wsapi_version              = "1.43"

# Maximum age of workspace/project cache in days before triggering
# automatic refresh. Setting $max_cache_age = 0 will force refresh
# every time user does a run.
# Note: keeping local cache of workspaces/projects really improves
# speed if you're doing multiple runs in a particular work session
$max_cache_age              = 1

# The $enable_user_cache parameter applies only when using the user_permissions_loader.rb script

# Note: When creating or updating many users, pre-fetching UserPermissions
# can improve performance

# However, when creating/updating only one or two users, the up-front cost of caching is probably more expensive
# than the time saved, so setting this flag to false probably makes sense when creating/updating small
# numbers of users
$enable_user_cache              = false