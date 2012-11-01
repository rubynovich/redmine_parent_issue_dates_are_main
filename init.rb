require 'redmine'

if Rails::VERSION::MAJOR < 3
  require 'dispatcher'
  object_to_prepare = Dispatcher
else
  object_to_prepare = Rails.configuration
end

object_to_prepare.to_prepare do
  [:issue].each do |cl|
    require "pidam_#{cl}_patch"
  end

  [ 
    [Issue, ParentIssueDatesAreMainPlugin::IssuePatch]
  ].each do |cl, patch|
    cl.send(:include, patch) unless cl.included_modules.include? patch
  end
end

Redmine::Plugin.register :redmine_parent_issue_dates_are_main do
  name 'Даты родительской задачи важнее'
  author 'Roman Shipiev'
  description 'Изменяет поведение родительской задачи (parent issue). По-умолчанию, если в подзадаче изменяются сроки выполнения, то родительская задача автоматически подстраивает свои сроки под подзадачу. Данный модуль фиксирует сроки выполнения родительской задачи так, чтобы сроки подзадач в них укладывались.'
  version '0.0.3'
  url 'https://github.com/rubynovich/redmine_parent_issue_dates_are_main'
  author_url 'http://roman.shipiev.me'
end
