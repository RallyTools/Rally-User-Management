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
fileloc = File.dirname(__FILE__)

require 'rally_api'
require fileloc + '/rally_user_helper.rb'
require fileloc + '/multi_io.rb'
require fileloc + '/version.rb'
require 'csv'

$my_base_url                   = "https://rally1.rallydev.com/slm"

$my_username                   = "user@company.com"
$my_password                   = "password"
$wsapi_version                 = "1.43"

# Mode options:
# :usernameandemail => resets both UserName and Email to the updated value
# :usernameonly => only resets UserName. Email address remains unchanged
$user_update_mode              = :usernameandemail

# Encoding
$file_encoding                 = "UTF-8"

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
      if $user_update_mode == :usernameandemail then
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

def go_change_usernames(input_file)

  #==================== Making a connection to Rally ====================

  # Load (and maybe override with) my personal/private variables from a file...
  my_vars= File.dirname(__FILE__) + "/../my_vars.rb"
  if FileTest.exist?( my_vars ) then require my_vars end

  #Setting custom headers
  @user_mgmt_version      = RallyUserManagement::Version.new()
  $headers                = RallyAPI::CustomHttpHeader.new()
  $headers.name           = "Ruby User Management Tool 2"
  $headers.vendor         = "Rally Labs"
  $headers.version        = @user_mgmt_version.revision()

  config                  = {:base_url => $my_base_url}
  config[:username]       = $my_username
  config[:password]       = $my_password
  config[:headers]        = $my_headers #from RallyAPI::CustomHttpHeader.new()
  config[:version]        = $wsapi_version

  @rally = RallyAPI::RallyRestJson.new(config)

  $users_filename = input_file
  input  = CSV.read($users_filename, {:encoding => $file_encoding})

  header = input.first #ignores first line

  rows   = []
  (1...input.size).each { |i| rows << CSV::Row.new(header, input[i]) }

  rows.each do |row|
    update_username(header, row)
  end
end