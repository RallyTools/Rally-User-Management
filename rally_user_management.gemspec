Gem::Specification.new do | spec |
  spec.name        = 'rally_user_management'
  spec.version     = '0.5.6'
  spec.date        = '2014-05-31'
  spec.summary     = "Rally User Management Tool 2"
  spec.description = "User Management for Rally"
  spec.authors     = ["Rally Labs"]
  spec.email       = 'mwilliams@rallydev.com'
  spec.homepage    = "https://github.com/RallyTools/Rally-User-Management"
  spec.summary     = "A Ruby Toolkit to help with bulk management of users and permissions in Rally"
  spec.description = "Rally User Management tool for ruby"
  spec.required_ruby_version = '>= 1.9.3'
  spec.add_dependency('httpclient', '~> 2.3.0')
  spec.add_dependency('rally_api', '~> 1.0.1')

  spec.files       = [
    "lib/rally_user_management.rb",
    "lib/rally_user_helper.rb",
    "lib/version.rb",
    "lib/multi_io.rb"
  ]
  spec.homepage    =
    'http://rubygems.org/gems/rally_user_management'
  spec.license       = 'MIT'
  spec.has_rdoc      = false

end