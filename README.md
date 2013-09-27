Rally-User-Management
=====================

## License

Copyright (c) Rally Software Development Corp. 2013 Distributed under the MIT License.

## Warranty

The Rally User Management toolkit is available on an as-is basis. 

## Support

Rally Software does not actively maintain or support this toolkit. If you have a question or problem, we recommend posting it to Stack Overflow: http://stackoverflow.com/questions/ask?tags=rally

## Description

The Rally-User-Management kit is an enhanced toolset for Rally subscription administrators who want to bulk
create/update users in their Rally subscription, enable/disable users, and assign permissions.

Rally-User-Management provides the following updates and enhancements from the original user_mgmt toolkit:

- Updated to use rally_api gem instead of rally_rest_api
- rally_api greatly improves speed and reliability.
- Provides bulk permission management granular to Projects (original provisioned at Workspace level only)
- Provides capability to bulk assign or update team membership

Rally-User-Management requires:
- Ruby 1.9.3
- rally_api 0.9.1 or higher
- You can install rally_api and dependent gems by using:
- gem install rally_api

The Rally user management toolkit takes a set of users formatted in a Tab-Delimited text file
and performs the following functions:
- Creates the users in your Rally subscription if they do not exist, and
- Assigns and/or updates permissions to users across workspaces and projects.
- Assigns and/or updates team memberships for users across projects
- Enables or disables user in your Rally subscription

The contents of this Github repository include:

- change_usernames_template.csv                 - Template file showing format for username/email bulk update mapping
- change_usernames.rb                           - Script to bulk update usernames and email addresses
- enable_or_disable_users.rb                    - Script to bulk enable or disable users
- enable_or_disable_users_template.txt          - Template file contain list of users to enable/disable
- ldap_username_load.rb                         - Script to update Onprem Ldap Username field when enabling LDAP for Rally On-Premise
- ldap_username_load_template.csv               - Template file contain list of Username and OnpremLdapUsername values.
- my_vars.rb                                    - User configurable variables
- new_user_list_template.txt                    - START HERE! This is the list of users/attributes you want to create
- user_helper.rb                                - Helper class with many utility functions
- user_permissions_loader.rb                    - Script to upload users and permissions
- user_permissions_loader_template.txt          - Template file showing what an upload file should look like
- user_permissions_summary.rb                   - Script to output summary of user permissions AND Team Membership for all users
- user_permissions_template_generator.rb        - Script to generate template of WorkspacePermissions and
-                                                 ProjectPermissions for all users in the new_user_list file
- user_team_membership_summary.rb               - Script that summarizes just team membership(s) for all users
- README.docx                                   - User guide Word document
- README.md                                     - This README
- README.pdf                                    - User guide PDF

Please clone the repo and save to a folder on your local drive.