require_dependency 'issue'

module ParentIssueDatesAreMainPlugin
  module IssuePatch
    def self.included(base)
      base.extend(ClassMethods)

      base.send(:include, InstanceMethods)

      base.class_eval do
        include Redmine::I18n
        alias_method_chain :validate_issue, :pidam
        alias_method_chain :soonest_start, :pidam
        alias_method_chain :recalculate_attributes_for, :pidam
        alias_method_chain :"safe_attributes=", :pidam
        after_validation :remove_missing_errors
      end

    end

    module ClassMethods
    end

    module InstanceMethods
      def remove_missing_errors
        [:start_date, :due_date].each do |date|
          if errors[date].include? ::I18n.t(:not_a_date, scope: 'activerecord.errors.messages')
            errors.instance_eval{ @messages[date].clear }
            errors.add date, :not_a_date
          end
        end
      end

      def safe_attributes_with_pidam=(attrs, user=User.current)
        return unless attrs.is_a?(Hash)

        # User can change issue attributes only if he has :edit permission or if a workflow transition is allowed
        attrs = delete_unsafe_attributes(attrs, user)
        Rails.logger.error("priority = " + attrs.inspect.red)
        return if attrs.empty?

        # Project and Tracker must be set before since new_statuses_allowed_to depends on it.
        if p = attrs.delete('project_id')
          if allowed_target_projects(user).collect(&:id).include?(p.to_i)
            self.project_id = p
          end
        end

        if t = attrs.delete('tracker_id')
          self.tracker_id = t
        end

        if attrs['status_id']
          unless new_statuses_allowed_to(user).collect(&:id).include?(attrs['status_id'].to_i)
            attrs.delete('status_id')
          end
        end

        unless leaf?
          attrs.reject! {|k,v|
            #%w(priority_id done_ratio estimated_hours).include?(k)
            %w(done_ratio estimated_hours).include?(k)
          }
        end

        if attrs['parent_issue_id'].present?
          attrs.delete('parent_issue_id') unless Issue.visible(user).exists?(attrs['parent_issue_id'].to_i)
        end

        Rails.logger.error("priority1 = " + attrs.inspect.red)
        Rails.logger.error("priority1 = " + self.inspect.red)

        flag_mail = false
        if attrs['priority_id'].present? && self.priority_id.present? && attrs['priority_id'].to_i != self.priority_id
          flag_mail = true 
          priorities = { "old_p" => IssuePriority.where(id: self.priority_id).first.name, 
                         "new_p" => IssuePriority.where(id: attrs['priority_id'].to_i).first.name }
        end

        # mass-assignment security bypass
        if Rails::VERSION::MAJOR < 3
          self.send :attributes=, attrs, false
        else
          assign_attributes attrs, :without_protection => true
        end

        mail_from_parent(priorities) if flag_mail
        Rails.logger.error("priority2 = " + attrs.inspect.red)
        Rails.logger.error("priority2 = " + self.inspect.red)
      end

      def mail_from_parent(priorities)
        recipients = User.where(id: (self.descendants.map(&:assigned_to_id) + self.descendants.map(&:assigned_to_id)).uniq)
        if recipients.include?(User.current) && User.current.pref.no_self_notified
            recipients = recipients - [User.current]
        end
        recipients.each{|r| Mailer.parent_priority_was_changed(r, self, priorities).deliver }

      end

      def soonest_start_with_pidam(reload = false)
        nil
      end

      def validate_issue_with_pidam
        if due_date && start_date && due_date < start_date
          errors.add :due_date, :greater_than_start_date
        end

        if start_date && soonest_start && start_date < soonest_start
          errors.add :start_date, :invalid
        end

        if fixed_version
          if !assignable_versions.include?(fixed_version)
            errors.add :fixed_version_id, :inclusion
          elsif reopened? && fixed_version.closed?
            errors.add :base, I18n.t(:error_can_not_reopen_issue_on_closed_version)
          end
        end

        # Checks that the issue can not be added/moved to a disabled tracker
        if project && (tracker_id_changed? || project_id_changed?)
          unless project.trackers.include?(tracker)
            errors.add :tracker_id, :inclusion
          end
        end

        # Checks parent issue assignment
        if @invalid_parent_issue_id.present?
          errors.add :parent_issue_id, :invalid
        elsif @parent_issue
          if !valid_parent_project?(@parent_issue)
            errors.add :parent_issue_id, :invalid
          elsif (@parent_issue != parent) && (all_dependent_issues.include?(@parent_issue) || @parent_issue.all_dependent_issues.include?(self))
            errors.add :parent_issue_id, :invalid
          elsif !new_record?
            # moving an existing issue
            if @parent_issue.root_id != root_id
              # we can always move to another tree
            elsif move_possible?(@parent_issue)
              # move accepted inside tree
            else
              errors.add :parent_issue_id, :invalid
            end
          end
        end

        # Checks parent issue assignment
        if @parent_issue
          errors.add :start_date, :exceed  if start_date && @parent_issue.start_date > start_date
          errors.add :due_date, :exceed    if due_date && @parent_issue.due_date < due_date
        end
      end

      def recalculate_attributes_for_with_pidam(issue_id)
        if issue_id && p = Issue.find_by_id(issue_id)
              #Rails.logger.error("priority1 = " + attrs.inspect.red)

          # priority = highest priority of children
          #if priority_position = p.children.maximum("#{IssuePriority.table_name}.position", :joins => :priority)
          #  p.priority = IssuePriority.find_by_position(priority_position)
          #end

          # start/due dates = lowest/highest dates of children
  #        p.start_date = p.children.minimum(:start_date)
  #        p.due_date = p.children.maximum(:due_date)
  #        if p.start_date && p.due_date && p.due_date < p.start_date
  #          p.start_date, p.due_date = p.due_date, p.start_date
  #        end

          # done ratio = weighted average ratio of leaves
          unless Issue.use_status_for_done_ratio? && p.status && p.status.default_done_ratio
            leaves_count = p.leaves.count
            if leaves_count > 0
              average = p.leaves.average(:estimated_hours).to_f
              if average == 0
                average = 1
              end
              done = p.leaves.sum("COALESCE(estimated_hours, #{average}) * (CASE WHEN is_closed = #{connection.quoted_true} THEN 100 ELSE COALESCE(done_ratio, 0) END)", :joins => :status).to_f
              progress = done / (average * leaves_count)
              p.done_ratio = progress.round
            end
          end

          # estimate = sum of leaves estimates
          p.estimated_hours = p.leaves.sum(:estimated_hours).to_f
          p.estimated_hours = nil if p.estimated_hours == 0.0

          # ancestors will be recursively updated
          if Rails::VERSION::MAJOR < 3
            p.save(false)
          else
            p.save(:validate => false)
          end
        end
      end
    end
  end
end
