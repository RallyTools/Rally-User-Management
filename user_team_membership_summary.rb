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

#!/usr/bin/ruby
########################################################################
util_name = "user_team_membership_summary"
########################################################################

require 'rally_api'
require 'csv'

$my_username            = 'user@company.com'
$my_password            = 'password'
$my_base_url            = "https://rally1.rallydev.com/slm"

$my_page_size           = 50
$my_fetch               = "true"
$my_workspace           = "My Workspace"
$my_project             = "My Project"

$my_output_file             = "user_team_membership_summary.txt"

# Output file delimiter
$my_delim = "\t"

$output_fields              =  %w{UserID MembershipNumber TeamName}

#Setting custom headers
$headers                    = RallyAPI::CustomHttpHeader.new()
$headers.name               = "Ruby User Management Tool 2::Ruby Team Membership Summary Report"
$headers.vendor             = "Rally Labs"
$headers.version            = "0.50"

#API Version
$wsapi_version              = "1.43"

# Load (and maybe override with) my personal/private variables from a file...
my_vars= File.dirname(__FILE__) + "/my_vars.rb"
if FileTest.exist?( my_vars ) then require my_vars end

#==================== Making a connection to Rally ====================
config                  = {:base_url => $my_base_url}
config[:username]       = $my_username
config[:password]       = $my_password
config[:version]        = $wsapi_version
config[:headers]        = $headers #from RallyAPI::CustomHttpHeader.new()

puts "Connecting to Rally: #{$my_base_url} as #{$my_username}..."
@rally = RallyAPI::RallyRestJson.new(config)

#==================== Querying Rally ==========================
user_query = RallyAPI::RallyQuery.new()
user_query.type = :user
user_query.fetch = "UserName,FirstName,LastName,DisplayName,TeamMemberships,Name,Role,Project"
user_query.page_size = 200 #optional - default is 200
user_query.limit = 50000 #optional - default is 99999
user_query.order = "UserName Asc"

# Query for users
puts "Querying users..."

results = @rally.find(user_query)

number_users = results.total_result_count
puts "Found #{number_users} users."

# Start output of summary
# Output CSV header
summary_csv = CSV.open($my_output_file, "w", {:col_sep => $my_delim})
summary_csv << $output_fields

# loop through all users and output permissions summary
puts "Summarizing users and writing permission summary output file..."

# Step thru all users
count = 0
results.each do |this_User|

    count = count + 1
    number_team_memberships = this_User.TeamMemberships != nil ? this_User.TeamMemberships.length : 0

    if number_team_memberships > 0
      ct = 0
        this_User.TeamMemberships.each do |this_Team|
          # Print user info...

          output_record = []
          output_record << this_User.UserName
          output_record << "#%02d"%ct
          output_record << this_Team.Name

          summary_csv << output_record
          ct = ct + 1
        end
    else
      output_record = []
      output_record << this_User.UserName
      output_record << "#00"
      output_record << "No Team Memberships"
      summary_csv << output_record
    end
end

puts "Done! User team membership summary written to #{$my_output_file}."