module AiGeneratableEndpoint
  extend ActiveSupport::Concern

  def create
    generation = find_or_create_generation

    unless !generation.previously_new_record? && generation.in_progress? && !generation.stale?
      generation.reset_for_retry!(reset_attributes)
      generation_job.perform_later(generation.id)
    end

    render json: generation.push_event_data, status: :accepted
  end

  def show
    generation = existing_generation
    return head :no_content if generation.blank?

    render json: generation.push_event_data
  end

  def destroy
    existing_generation&.destroy!
    head :no_content
  end

  private

  def existing_generation
    generation_model.find_by(conversation: @conversation, user: Current.user)
  end

  def find_or_create_generation
    generation_model.find_or_create_by!(
      account: Current.account,
      conversation: @conversation,
      user: Current.user
    )
  end

  # Subclasses override this when a new request must persist its input.
  def reset_attributes
    {}
  end
end
