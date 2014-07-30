require 'redmine'

Redmine::Plugin.register :redmine_parent_issue_dates_are_main do
  name 'Parent issue dates are main'
  author 'Roman Shipiev'
  description 'Changes the behavior of the parent issue. By default, if the sub-issue deadlines changed, the parent issue automatically adjusts its time under the sub-issue. This module fixes deadlines parent issue so that the timing of sub-issues they fit.'
  version '0.0.3'
  url 'https://github.com/rubynovich/redmine_parent_issue_dates_are_main'
  author_url 'http://roman.shipiev.me'
end

if Rails::VERSION::MAJOR < 3
  require 'dispatcher'
  object_to_prepare = Dispatcher
else
  object_to_prepare = Rails.configuration
end

object_to_prepare.to_prepare do
  [:issue, :mailer].each do |cl|
    require "pidam_#{cl}_patch"
  end

  [
    [Issue,  ParentIssueDatesAreMainPlugin::IssuePatch],
    [Mailer, ParentIssueDatesAreMainPlugin::MailerPatch]
  ].each do |cl, patch|
    cl.send(:include, patch) unless cl.included_modules.include? patch
  end
end
