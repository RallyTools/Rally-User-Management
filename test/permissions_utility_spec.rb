
require File.dirname(__FILE__) + "/spec_helper"
require 'rspec'

describe "Given the PermissionsUtil class and a user" do

  before(:all) do
    @logger = create_logger("permissions_utility_spec.log")
    @rally = create_rally_connection(TestConfig::RALLY_USER, TestConfig::RALLY_PASSWORD, @logger, TestConfig::RALLY_URL)
    config = {
        "rally_api_obj" => @rally,
        "logger" => @logger
    }
    @permissions_util = RallyUserManagement::PermissionUtil.new(config)
    user_name = unique_name() + "@test.com"
    @user = create_arbitrary_rally_object(@rally, "User", {"UserName" => user_name })

  end

  after(:all) do
    #@user.delete()
  end

  it "should return empty array if the username was not found when reading permissions" do
    permissions = @permissions_util.read_user_permissions("bogus@bogus.com")
    expect(permissions.length).to eq(0)
  end

  it "should read permissions even if user has none" do
    permissions = @permissions_util.read_user_permissions(@user.UserName)
    #we can't test for no length here, because often users are created with default permissions
    expect(permissions.kind_of?(Array)).to be true
  end

  it "should read team memberships even if the user has none" do
    team_memberships = @permissions_util.read_user_team_memberships(@user.UserName)

    expect(team_memberships.kind_of?(Array)).to be true
    expect(team_memberships.length).to eq(0)

  end

  it "should create a project permission for an admin" do
    project = find_object(@rally, "Project", TestConfig::RALLY_PROJECT_REF_1)
    role = "Project Admin"

    permissions = @permissions_util.read_user_permissions(@user.UserName)
    exists = has_permissions?(permissions, "Project", "Admin", project.ObjectID)
    expect(exists).to be false

    ret = @permissions_util.add_project_permission(@user, project.Workspace._ref, project._ref, role)
    expect(ret).not_to be_nil

    permissions = @permissions_util.read_user_permissions(@user.UserName)
    exists = has_permissions?(permissions, "Project", "Admin", project.ObjectID)
    expect(exists).to be true
  end

  it "should create a team membership for a user" do
    project = find_object(@rally, "Project", TestConfig::RALLY_PROJECT_OID_PAID_TIME_OFF)
    team_memberships = @permissions_util.read_user_team_memberships(@user.UserName)

    expect(team_memberships.length).to eq(0)

    @permissions_util.add_project_team_member(@user,project._ref)

    team_memberships = @permissions_util.read_user_team_memberships(@user.UserName)

    expect(team_memberships.length).to eq(1)
    expect(team_memberships[0].ObjectID).to eq(TestConfig::RALLY_PROJECT_OID_PAID_TIME_OFF)

    permissions = @permissions_util.read_user_permissions(@user.UserName)
    has_editor_permissions = has_permissions?(permissions, "Project", "Editor", TestConfig::RALLY_PROJECT_OID_PAID_TIME_OFF )
    expect(has_editor_permissions).to be true
  end

  it "should create a project permission for an editor" do
    project = find_object(@rally, "Project", TestConfig::RALLY_PROJECT_REF_2)
    role = "Editor"

    permissions = @permissions_util.read_user_permissions(@user.UserName)

    exists = has_permissions?(permissions, "Project", role, project.ObjectID)
    expect(exists).to be false

    original_length = permissions.length

    @permissions_util.add_project_permission(@user, project.Workspace._ref, project._ref, role)
    permissions = @permissions_util.read_user_permissions(@user.UserName)

    expect(permissions.length).to eq(original_length + 1)

    exists = has_permissions?(permissions, "Project", role, project.ObjectID)
    expect(exists).to be true
  end

  it "should create a project permission for an viewer" do

    project = find_object(@rally, "Project", TestConfig::RALLY_PROJECT_REF_3)
    role = "Viewer"

    permissions = @permissions_util.read_user_permissions(@user.UserName)
    original_length = permissions.length

    exists = has_permissions?(permissions, "Project", role, project.ObjectID)
    expect(exists).to be false

    @permissions_util.add_project_permission(@user, project.Workspace._ref, project._ref, role)
    permissions = @permissions_util.read_user_permissions(@user.UserName)

    expect(permissions.length).to eq(original_length + 1)

    exists = has_permissions?(permissions, "Project", role, project.ObjectID)
    expect(exists).to be true
  end

  it "should create a workspace permission for an admin" do

    workspace_ref = "/workspace/#{TestConfig::RALLY_WORKSPACE_ACME_OID}"
    role = "Admin"

    permissions = @permissions_util.read_user_permissions(@user.UserName)
    exists = has_permissions?(permissions, "Workspace", role, TestConfig::RALLY_WORKSPACE_ACME_OID)
    expect(exists).to be false

    original_length = permissions.length

    @permissions_util.add_workspace_permission(@user, workspace_ref, role)
    permissions = @permissions_util.read_user_permissions(@user.UserName)

    expect(permissions.length).to eq(original_length + 1)

    exists = has_permissions?(permissions, "Workspace", role, TestConfig::RALLY_WORKSPACE_ACME_OID)
    expect(exists).to be true
  end

  it "should copy permissions from one user to another but not downgrade permissions" do
    target_user_name = unique_name() + "@target.com"
    target_user = create_arbitrary_rally_object(@rally, "User", {"UserName" => target_user_name })

    source_permissions = @permissions_util.read_user_permissions(@user.UserName)
    old_target_permissions = @permissions_util.read_user_permissions(target_user.UserName)

    @permissions_util.replicate_permissions(source_permissions,target_user)

    new_target_permissions = @permissions_util.read_user_permissions(target_user.UserName)

    source_permissions.each do |permission|
      type = permission._type.downcase
      role = permission.Role

      if (type == "projectpermission")
         container_type = "Project"

      else
        container_type = "Workspace"
      end
      oid = permission[container_type].ObjectID
      exists = has_permissions?(new_target_permissions, container_type, role, oid)
      expect(exists).to be true
    end
  end

  it "should copy team memberships from one user to another" do
    target_user_name = unique_name() + "@target.com"
    target_user = create_arbitrary_rally_object(@rally, "User", {"UserName" => target_user_name })

    source_memberships = @permissions_util.read_user_team_memberships(@user.UserName)

    @permissions_util.replicate_team_memberships(source_memberships,target_user)

    new_target_memberships = @permissions_util.read_user_team_memberships(target_user.UserName)

    source = []
    target = []
    source_memberships.each do |membership|
      source.push(membership.ObjectID)
    end
    new_target_memberships.each do |membership|
      target.push(membership.ObjectID)
    end
    expect((source - target).empty?).to be true
  end

  it "should handle a nonexistant permission gracefully for a workspace" do
    workspace_ref = "/workspace/#{TestConfig::RALLY_WORKSPACE_ACME_OID}"
    role = "Bogus"

    permissions = @permissions_util.read_user_permissions(@user.UserName)
    original_length = permissions.length

    ret = @permissions_util.add_workspace_permission(@user, workspace_ref, role)

    permissions = @permissions_util.read_user_permissions(@user.UserName)

    expect(permissions.length).to eq(original_length)
    expect(ret).to be_nil
  end

  it "should handle a nonexistant permission gracefully for a project" do
    project = find_object(@rally, "Project", TestConfig::RALLY_PROJECT_REF_3)
    role = "Bogus"

    permissions = @permissions_util.read_user_permissions(@user.UserName)
    original_length = permissions.length

    ret = @permissions_util.add_project_permission(@user, project.Workspace._ref, project._ref, role)
    permissions = @permissions_util.read_user_permissions(@user.UserName)

    expect(permissions.length).to eq(original_length)
    expect(ret).to be_nil
  end

  it "should error gracefully if the running user does not have appropriate permissions" do

  end

  it "should not update permissions for a subscription administrator" do

  end

  it "should not copy permissions from a subscription administrator" do

  end

end