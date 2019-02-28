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

#include for rally json library gem
require 'rally_api'
require 'csv'
require './lib/multi_io.rb'
require './lib/rally_user_helper.rb'
require './lib/go_update_project_permissions.rb'

#
# Command line options can be one of two different styles:
#   1) ruby update_project_permissions.rb file:MyPPP.csv            # Get Project/Permission pairs from file 'MyPPP.csv'
#   2) ruby update_project_permissions.rb "My Project" "Editor"     # Use the Project Name
#       ruby update_project_permissions 12345678910 "No Access"     # Use the Project ObjectID
#

put_usage = false # Assume all is well

case ARGV.length
# ----------------------------------------
when 1
    if ARGV[0][0..4] != 'file:'
        puts "ERROR: When using only 1 arguemnt, it must begin with the string 'file:'"
        put_usage = true
    end
    input_file = ARGV[0][5..-1]

    all_projects = []
    CSV.foreach(input_file,  {:col_sep => ",", :encoding => 'UTF-8'}) do |row|
        if row[0][0] != '#'  # ignore comment lines in input_file
            all_projects.push(row)
        end
    end
# ----------------------------------------
when 2
    $project_identifier_arg = ARGV[0]
    $new_permission_arg = ARGV[1]
    all_projects = [[$project_identifier_arg, $new_permission_arg]]
# ----------------------------------------
else
    put_usage = true
end

if put_usage == true
    puts "Usage: This script can be invoked one of two ways:"
    puts "\t1) ruby #{PROGRAM_NAME} file:MyPPP.csv            # Get Project/Permission pairs from file 'MyPPP.csv'"
    puts "\t2) ruby #{PROGRAM_NAME} 'My Project' 'Editor'     # Use the Project Name"
    puts "\t   ruby #{PROGRAM_NAME} 12345678910' 'No Access'  # Use the Project ObjectID"
    exit(-1)
end

begin
    all_projects.each_with_index do |this_project, this_project_index|
        $project_identifier_arg = this_project[0]
        $new_permission_arg     = this_project[1]
        puts "(#{this_project_index+1} of #{all_projects.length}) Processing Project='#{$project_identifier_arg}'  Permissions='#{$new_permission_arg}'"
        go_update_project_permissions($project_identifier_arg, $new_permission_arg)
    end
end
