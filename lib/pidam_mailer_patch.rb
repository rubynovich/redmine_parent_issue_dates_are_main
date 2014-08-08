# -*- coding: utf-8 -*-
require_dependency 'issue'

module ParentIssueDatesAreMainPlugin
    module MailerPatch
      def self.included(base)
        base.send(:include, InstanceMethods)

        base.class_eval do          
          include Rails.application.routes.url_helpers
        end
      end

      module InstanceMethods

        def parent_priority_was_changed(user, issue, priorities)
          set_language_if_valid user.language
          @issue = issue
          @issue_title = "##{@issue.id} \"#{@issue.subject}\""
          @old_p = priorities["old_p"]
          @new_p = priorities["new_p"]
          @author = User.where(id: @issue.author_id).name
          @status = IssueStatus.where(id: @issue.status_id).name
          @priority = IssuePriority.where(id: @issue.priority_id).name
          @assigned_to = User.where(id: @issue.assigned_to_id).name
          mail :to => user.mail, 
               :subject => l(:subject_parent_priority_was_changed, project_and_issue: "#{@issue.project.name} - ##{@issue.id}", iss_subject: @issue.subject)
        end


      end
    end
end
