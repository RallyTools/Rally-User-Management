# Copyright (c) 2013 Rally Software Development
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

# Usage to enable: ruby enable_or_disable_users.rb enable
# Usage to disable: ruby enable_or_disable_users.rb disable

require 'rally_api'
require './user_mgmt_version'
require 'csv'

$my_base_url                   = "https://rally1.rallydev.com/slm"

$my_username                   = "user@company.com"
$my_password                   = "password"
$default_filename              = 'users_enable_or_disable.txt'

$wsapi_version                 = "1.43"

# Constants
$enable_flag                   = "enable"
$disable_flag                  = "disable"

$enabled_status                = "enabled"
$disabled_status               = "disabled"

$enabled_boolean               = "False"
$disabled_boolean              = "True"

$userlist_filename = ARGV[0]

if $userlist_filename == nil
# This is the default of the file to be used for uploading user permissions
  $userlist_filename               = $default_filename
end

if File.exists?(File.dirname(__FILE__) + "/" + $userlist_filename) == false
  puts "User enable/disable file #{$userlist_filename} not found. Exiting."
  exit
end

$permission_flag = ARGV[1]
$usage="Usage: ruby enable_or_disable_users.rb list_of_users.txt enable"

if $permission_flag != $enable_flag && $permission_flag != $disable_flag
  puts "Missing command line argument:"
  puts $usage
  exit
end

if $permission_flag == $enable_flag
  $update_boolean = $enabled_boolean
  $post_update_status = $enabled_status
elsif $permission_flag == $disable_flag
  $update_boolean = $disabled_boolean
  $post_update_status = $disabled_status
end

# Load (and maybe override with) my personal/private variables from a file...
my_vars= File.dirname(__FILE__) + "/my_vars.rb"
if FileTest.exist?( my_vars ) then require my_vars end

def update_user(header, row)
  username                  = row[header[0]]

  user_query                = RallyAPI::RallyQuery.new()
  user_query.type           = :user
  user_query.fetch          = "ObjectID,UserName,FirstName,LastName,Disabled"
  user_query.query_string   = "(UserName = \"" + username + "\")"
  user_query.order          = "UserName Asc"

  rally_user = @rally.find(user_query)

  if rally_user.total_result_count == 0
    puts "Rally user #{username} not found"
  else
    begin
      rally_user_toupdate = rally_user.first()
      fields = {}
      fields["Disabled"] = $update_boolean
      rally_user_updated = @rally.update(:user, rally_user_toupdate.ObjectID, fields) #by ObjectID
      puts "Rally user #{username} successfully #{$post_update_status}."
    rescue => ex
      puts "Rally user #{username} not updated due to error"
      puts ex
    end
  end
end

begin

  #==================== Making a connection to Rally ====================

  #Setting custom headers
  @user_mgmt_version      = UserManagementVersion.new()
  $headers                = RallyAPI::CustomHttpHeader.new()
  $headers.name           = "Ruby User Management Tool 2::User Enabler-Disabler"
  $headers.vendor         = "Rally Labs"
  $headers.version        = user_mgmt_version.revision()

  config                  = {:base_url => $my_base_url}
  config[:username]       = $my_username
  config[:password]       = $my_password
  config[:version]        = $wsapi_version
  config[:headers]        = $my_headers #from RallyAPI::CustomHttpHeader.new()

  @rally = RallyAPI::RallyRestJson.new(config)

  input  = CSV.read($userlist_filename)
  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    update_user(header, row)
  end
end
