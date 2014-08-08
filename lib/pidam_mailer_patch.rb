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
          mail :to => user.mail, 
               :subject => l(:subject_parent_priority_was_changed, 
                              project_and_issue: ("#{@issue.project.name} - " + l(:field_issue) + "##{@issue.id}"), iss_subject: @issue.subject)
        end


      end
    end
end
