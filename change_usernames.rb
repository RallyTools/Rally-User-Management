# Copyright 2002-2011 Rally Software Development Corp. All Rights Reserved.

require 'rally_api'
require 'csv'

$my_base_url       = "https://rally1.rallydev.com/slm"

$my_username       = "user@company.com"
$my_password       = "password"
$wsapi_version     = "1.41"

# Mode options:
# :usernameandemail => resets both UserName and Email to the updated value
# :usernameonly => only resets UserName. Email address remains unchanged
$mode              = :usernameonly
# $mode = :usernameonly

$users_filename = ARGV[0]

if $users_filename == nil
# This is the default of the file to be used for uploading user permissions
  $users_filename               = 'change_usernames_template.csv'
end

if File.exists?(File.dirname(__FILE__) + "/" + $users_filename) == false
  puts "Username mapping file: #{$users_filename} not found. Exiting."
  exit
end

# Load (and maybe override with) my personal/private variables from a file...
my_vars= File.dirname(__FILE__) + "/my_vars.rb"
if FileTest.exist?( my_vars ) then require my_vars end

def update_username(header, row)
  exist_username        = row[header[0]].strip
  new_username          = row[header[1]].strip
  
  user_query = RallyAPI::RallyQuery.new()
  user_query.type = :user
  user_query.fetch = "ObjectID,UserName,EmailAddress,FirstName,LastName,Disabled"
  user_query.query_string = "(UserName = \"" + exist_username + "\")"
  user_query.order = "UserName Asc"

  rally_user = @rally.find(user_query)

  if rally_user.total_result_count == 0
    puts "Rally user #{exist_username} not found...skipping"
  else
    begin
      rally_user_toupdate = rally_user.first()
      fields = {}
      fields["UserName"] = new_username
      if $mode == :usernameandemail then
        fields["EmailAddress"] = new_username
      end
      rally_user_updated = @rally.update(:user, rally_user_toupdate.ObjectID, fields) #by ObjectID
      puts "Rally user #{exist_username} successfully changed to #{new_username}"
    rescue => ex
      puts "Rally user #{exist_username} not updated due to error"
      puts ex
    end
  end
end

begin

  #==================== Making a connection to Rally ====================

  #Setting custom headers
  $headers                            = RallyAPI::CustomHttpHeader.new()
  $headers.name                       = "Ruby User Management Tool 2: Change Usernames"
  $headers.vendor                     = "Rally Labs"
  $headers.version                    = "0.10"

  config                  = {:base_url => $my_base_url}
  config[:username]       = $my_username
  config[:password]       = $my_password
  config[:headers]        = $my_headers #from RallyAPI::CustomHttpHeader.new()
  config[:version]        = $wsapi_version

  @rally = RallyAPI::RallyRestJson.new(config)

  input  = CSV.read($users_filename)

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    update_username(header, row)
  end
end
