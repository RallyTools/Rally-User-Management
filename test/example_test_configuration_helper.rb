module TestConfig

  # MAKE YOUR OWN VERSION OF THIS and name it
  # test_configuration_helper.rb
  #
  # DO NOT CHECK IT IN

  #this file contains information about a rally instance and objects that the automated tests can run with.  

  # rally connection information
  RALLY_USER = "someone@somewhere.com"
  RALLY_PASSWORD = "Password"
  RALLY_URL = "https://rally1.rallydev.com/slm"
  RALLY_WORKSPACE = "MyWorkspace"
  RALLY_API_KEY = "_adfasefasd"
  RALLY_PROJECT_REF = 1234
  RALLY_PROJECT_REF_1 = 12345
  RALLY_PROJECT_REF_2 = 12346
  RALLY_PROJECT_REF_3 = 12347

  RALLY_SOURCE_USERNAME_FOR_PERMISSIONS_COPY = "dave@acme.com"
  RALLY_PROJECT_OID_PAID_TIME_OFF = 745298
  # fun with flowdock
  RALLY_WORKSPACE_ACME_OID = 729424

  RALLY_FLOWDOCK_KEY = "abc"

  RALLY_USERNAME_PROJECTS_ONLY = "projectuser@test.com" #user with only access to projects
  RALLY_USERNAME_WORKSPACE_ADMIN_ONLY = "wsadmin@test.com" #user with access to proect and workspace admin

end

