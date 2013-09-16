# Copyright 2002-2013 Rally Software Development Corp. All Rights Reserved.

require 'rally_api'
require 'csv'

rally_url        = "https://10.32.10.120/slm"
rally_user       = "subadmin@company.com"
rally_password   = "topsecret"
rally_ws_version = "1.33"
filename         = 'ldap_username_load_template.csv'

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

begin

  #==================== Making a connection to Rally ====================

  #Setting custom headers
  $headers = RallyAPI::CustomHttpHeader.new()
  $headers.name = "Ruby LDAP User Load Script"
  $headers.vendor = "Rally Software"
  $headers.version = "0.20"

  config                  = {:base_url => rally_url}
  config[:username]       = rally_user
  config[:password]       = rally_password
  config[:version]        = rally_ws_version
  config[:headers]        = $headers #from RallyAPI::CustomHttpHeader.new()

  @rally = RallyAPI::RallyRestJson.new(config)

  input  = CSV.read(filename)
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
