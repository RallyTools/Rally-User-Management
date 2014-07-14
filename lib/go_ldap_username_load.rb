# encoding: UTF-8
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

require 'rally_api'
require 'csv'

$rally_url              = "https://10.32.10.120/slm"
$rally_user             = "subadmin@company.com"
$rally_password         = "topsecret"

# Default to WSAPI 1.33 to accommodate potentially older On-Premise appliances
$rally_wsapi_version    = "1.33"
$input_filename         = 'ldap_username_load_template.csv'

# Encoding
$file_encoding          = "UTF-8"

def get_rally_users()
  user_query = RallyAPI::RallyQuery.new()
  user_query.type = :user
  user_query.fetch = "ObjectID,UserName,FirstName,LastName,OnpremLdapUsername"
  user_query.query_string = '(OnpremLdapUsername = "")'
  user_query.order = "UserName Asc"

  users = @rally.find(user_query)
  return users
end

#============Update user function================
def update_user(header, row)
  username        = row[header[0]]
  onprem_username = row[header[1]]

  user_query = RallyAPI::RallyQuery.new()
  user_query.type = :user
  user_query.fetch = "ObjectID,UserName,FirstName,LastName,OnpremLdapUsername"
  user_query.query_string = "(UserName = \"" + username + "\")"
  user_query.order = "UserName Asc"

  rally_user = @rally.find(user_query)

  if rally_user.total_result_count == 0
    puts "Rally user #{username} not found"
  else
    begin
      rally_user_toupdate = rally_user.first()
      fields = {}
      fields["OnpremLdapUsername"] = onprem_username
      rally_user_updated = @rally.update(:user, rally_user_toupdate.ObjectID, fields) #by ObjectID
      puts "Rally user #{username} updated successfully - onprem username set to #{rally_user_updated["OnpremLdapUsername"]}"

    rescue => ex
      puts " Rally user #{username} not updated due to error"
      puts ex
    end
  end
end
#=================End of function=============

def go_ldap_username_load(input_file)

  #==================== Making a connection to Rally ====================

  #Setting custom headers
  @user_mgmt_version      = RallyUserManagement::Version.new()
  $headers                = RallyAPI::CustomHttpHeader.new()
  $headers.name           = "Ruby User Management Tool 2"
  $headers.vendor         = "Rally Labs"
  $headers.version        = @user_mgmt_version.revision()

  config                  = {:base_url => $rally_url}
  config[:username]       = $rally_user
  config[:password]       = $rally_password
  config[:version]        = $rally_ws_version
  config[:headers]        = $headers #from RallyAPI::CustomHttpHeader.new()

  @rally                  = RallyAPI::RallyRestJson.new(config)

  $input_filename = input_file
  input  = CSV.read($input_filename, {:encoding => $file_encoding})
  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    update_user(header, row)
  end

  puts "Querying to find existing Rally Users without an OnpremLdapUsername attribute..."
  rally_users = get_rally_users()
  puts "Found: #{rally_users.total_result_count} that do not have an OnpremLdapUsername."
  puts "Listing..."
  rally_users.each do |user|
    puts "Rally user #{user["UserName"]} does not contain a ldap onprem username value"
  end
rescue => ex
  puts ex
  puts ex.backtrace
end