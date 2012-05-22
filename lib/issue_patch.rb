require_dependency 'issue'

module IssuePatch
  def self.included(base)
    base.extend(ClassMethods)
    
    base.send(:include, InstanceMethods)
    
    base.class_eval do
    
    end

  end
    
  module ClassMethods
  end
  
  module InstanceMethods
    def validate_issue_with_fix
      validate_issue_without_fix
      # Checks parent issue assignment
      if @parent_issue
        unless @parent_issue.start_date < start_date
          errors.add :start_date, :invalid
        end
        unless @parent_issue.due_date > due_date
          errors.add :due_date, :invalid
        end
      end
    end
    
    def recalculate_attributes_for_with_fix(issue_id)
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
    
    alias_method_chain :validate_issue, :fix
    alias_method_chain :recalculate_attributes_for, :fix
  end
end
