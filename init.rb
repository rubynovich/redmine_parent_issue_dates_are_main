require 'redmine'
require 'dispatcher'
require 'issue_patch'

Dispatcher.to_prepare do
  Issue.send(:include, ParentIssueDatesAreMain) unless Issue.include? ParentIssueDatesAreMain
end

Redmine::Plugin.register :redmine_parent_issue_dates_are_main do
  name 'Redmine Parent Issue Dates Are Main plugin'
  author 'Roman Shipiev'
  description 'Parent issue dates will be main'
  version '0.0.2'
  url 'https://github.com/rubynovich/redmine_parent_issue_dates_are_main'
  author_url 'http://roman.shipiev.me'
end
