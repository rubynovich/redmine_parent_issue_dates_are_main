require 'redmine'
require 'dispatcher'
require_dependency 'issue_patch'

Dispatcher.to_prepare do
  Issue.send(:include, IssuePatch) unless Issue.include? IssuePatch
end

Redmine::Plugin.register :redmine_parent_issue_dates_are_main do
  name 'Redmine Parent Issue Dates Are Main plugin'
  author 'Roman Shipiev'
  description 'Parent issue dates will be main'
  version '0.0.1'
  url 'https://github.com/rubynovich/redmine_parent_issue_dates_are_main'
  author_url 'http://roman.shipiev.me'
end
