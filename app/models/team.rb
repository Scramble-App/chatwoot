# == Schema Information
#
# Table name: teams
#
#  id                    :bigint           not null, primary key
#  allow_auto_assign     :boolean          default(TRUE)
#  description           :text
#  name                  :string           not null
#  reassign_on_shift_end :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#
# Indexes
#
#  index_teams_on_account_id           (account_id)
#  index_teams_on_name_and_account_id  (name,account_id) UNIQUE
#
class Team < ApplicationRecord
  include AccountCacheRevalidator

  belongs_to :account
  has_many :team_members, dependent: :destroy_async
  has_many :members, through: :team_members, source: :user
  has_many :conversations, dependent: :nullify

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :account_id }

  before_validation do
    self.name = name.downcase if attribute_present?('name')
  end

  # Adds multiple members to the team
  # @param user_ids [Array<Integer>] Array of user IDs to add as members
  # @return [Array<User>] Array of newly added members
  def add_members(user_ids, team_lead_ids = [])
    team_members_to_create = user_ids.map do |user_id|
      { user_id: user_id, team_lead: team_lead_ids.include?(user_id) }
    end
    created_members = team_members.create(team_members_to_create)
    added_users = created_members.filter_map(&:user)

    update_account_cache
    added_users
  end

  # Removes multiple members from the team
  # @param user_ids [Array<Integer>] Array of user IDs to remove
  # @return [void]
  def remove_members(user_ids)
    team_members.where(user_id: user_ids).destroy_all
    update_account_cache
  end

  def update_team_leads(user_ids)
    team_members.find_each do |team_member|
      team_member.update!(team_lead: user_ids.include?(team_member.user_id))
    end
    update_account_cache
  end

  def messages
    account.messages.where(conversation_id: conversations.pluck(:id))
  end

  def reporting_events
    account.reporting_events.where(conversation_id: conversations.pluck(:id))
  end

  def push_event_data
    {
      id: id,
      name: name
    }
  end
end

Team.include_mod_with('Audit::Team')
