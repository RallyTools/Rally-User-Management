$my_username		        = 'julien.parouty@ni.com'
$my_password		        = 'eVAqw4rz'
$my_base_url		        = "https://rally1.rallydev.com/slm"

#API Version
$wsapi_version                  = "1.41"

# The $enable_user_cache parameter applies only when using the user_permissions_loader.rb script

# Note: When creating or updating many users, pre-fetching UserPermissions
# can improve performance

# However, when creating/updating only one or two users, the up-front cost of caching is probably more expensive
# than the time saved, so setting this flag to false probably makes sense when creating/updating small
# numbers of users
$enable_user_cache              = false