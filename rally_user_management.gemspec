Gem::Specification.new do | spec |
  spec.name        = 'rally_user_management'
  spec.version     = '0.5.4'
  spec.date        = '2014-05-30'
  spec.summary     = "Rally User Management Tool 2"
  spec.description = "User Management for Rally"
  spec.authors     = ["Rally Software"]
  spec.email       = 'rallysupport@rallydev.com'
  spec.files       = [
    "lib/rally_user_management.rb",
    "lib/rally_user_helper.rb",
    "lib/go_user_permissions_summary.rb",
    "lib/go_user_permissions_loader.rb",
    "lib/go_user_permissions_template_generator.rb",
    "lib/version.rb",
    "lib/multi_io.rb"
  ]
  spec.homepage    =
    'http://rubygems.org/gems/rally_user_management'
  spec.license       = 'MIT'
end