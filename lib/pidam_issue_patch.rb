require_dependency 'issue'

module ParentIssueDatesAreMainPlugin
  module IssuePatch
    def self.included(base)
      base.extend(ClassMethods)

      base.send(:include, InstanceMethods)

      base.class_eval do
        validates_presence_of :due_date

        alias_method_chain :validate_issue, :pidam
        alias_method_chain :recalculate_attributes_for, :pidam
        alias_method_chain :"safe_attributes=", :pidam
        if Rails::VERSION::MAJOR < 3
          alias_method_chain :reschedule_after, :pidam
        else
          alias_method_chain :"reschedule_on!", :pidam
        end
      end

    end

    module ClassMethods
    end

    module InstanceMethods
      def safe_attributes_with_pidam=(attrs, user=User.current)
        return unless attrs.is_a?(Hash)

        # User can change issue attributes only if he has :edit permission or if a workflow transition is allowed
        attrs = delete_unsafe_attributes(attrs, user)
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
            %w(priority_id done_ratio estimated_hours).include?(k)
          }
        end

        if attrs['parent_issue_id'].present?
          attrs.delete('parent_issue_id') unless Issue.visible(user).exists?(attrs['parent_issue_id'].to_i)
        end

        # mass-assignment security bypass
        if Rails::VERSION::MAJOR < 3
          self.send :attributes=, attrs, false
        else
          assign_attributes attrs, :without_protection => true
        end
      end

      def validate_issue_with_pidam
        validate_issue_without_pidam
        # Checks parent issue assignment
        if @parent_issue
          errors.add :start_date, :invalid  unless start_date && @parent_issue.start_date < start_date
          errors.add :due_date, :invalid    unless due_date && @parent_issue.due_date > due_date
        end
      end

      def recalculate_attributes_for_with_pidam(issue_id)
        if issue_id && p = Issue.find_by_id(issue_id)
          # priority = highest priority of children
          if priority_position = p.children.maximum("#{IssuePriority.table_name}.position", :joins => :priority)
            p.priority = IssuePriority.find_by_position(priority_position)
          end

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
          p.save(false)
        end
      end

      if Rails::VERSION::MAJOR < 3
        def reschedule_after_with_pidam(date)
          return if date.nil?
          if children?
            leaves.each do |leaf|
              leaf.reschedule_after(date)
            end
          end
        end
      else
        def reschedule_on_with_pidam!(date)
          return if date.nil?
          if children?
            leaves.each do |leaf|
              if leaf.start_date
                # Only move subtask if it starts at the same date as the parent
                # or if it starts before the given date
                if start_date == leaf.start_date || date > leaf.start_date
                  leaf.reschedule_on!(date)
                end
              else
                leaf.reschedule_on!(date)
              end
            end
          end
        end
      end

    end
  end
end
