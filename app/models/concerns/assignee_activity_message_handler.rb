module AssigneeActivityMessageHandler
  extend ActiveSupport::Concern

  private

  def create_assignee_change_activity(user_name)
    user_name = activity_message_owner(user_name)

    return unless user_name

    content = generate_assignee_change_activity_content(user_name)
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content)) if content
  end

  def generate_assignee_change_activity_content(user_name)
    return shift_reassignment_activity_content(user_name) if assignee_id && Current.assignment_event_source == 'shift_end'

    params = { assignee_name: assignee&.name || '', user_name: user_name }
    key = assignee_id ? 'assigned' : 'removed'
    key = 'self_assigned' if self_assign? assignee_id
    I18n.t("conversations.activity.assignee.#{key}", **params)
  end

  def shift_reassignment_activity_content(user_name)
    I18n.t('conversations.activity.assignee.shift_reassigned',
           previous_assignee_name: User.find_by(id: assignee_id_before_last_save)&.name,
           assignee_name: assignee.name,
           user_name: user_name)
  end

  def activity_message_owner(user_name)
    if !user_name && Current.executed_by.present?
      user_name = case Current.executed_by
                  when AssignmentPolicy
                    I18n.t('auto_assignment.policy_actor', policy_name: Current.executed_by.name)
                  when Inbox
                    I18n.t('auto_assignment.default_policy_name')
                  else
                    I18n.t('automation.system_name')
                  end
    end
    user_name
  end
end
