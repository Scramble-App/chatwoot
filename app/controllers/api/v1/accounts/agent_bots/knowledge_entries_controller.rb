class Api::V1::Accounts::AgentBots::KnowledgeEntriesController < Api::V1::Accounts::AgentBots::BaseController
  RESULTS_PER_PAGE = 50
  QUESTIONS_LIMIT = 20
  SORT_ORDERS = {
    'key' => { key: :asc },
    'asked_count' => { asked_count: :desc, key: :asc },
    'updated_at' => { updated_at: :desc, key: :asc }
  }.freeze

  before_action -> { authorize @agent_bot, :manage_knowledge? }
  before_action :knowledge_entry, only: [:show, :update, :destroy]

  # The status counts follow the search and category filters, not the status filter
  def index
    entries = searched_entries
    @status_counts = status_counts(entries)
    entries = entries.where(status: params[:status]) if AgentBotKnowledgeEntry.statuses.key?(params[:status])
    @categories = @agent_bot.knowledge_entries.where.not(category: [nil, '']).distinct.order(:category).pluck(:category)
    @knowledge_entries = entries.order(SORT_ORDERS.fetch(params[:sort].to_s, SORT_ORDERS['key'])).page(params[:page]).per(RESULTS_PER_PAGE)
  end

  def show
    @questions = @knowledge_entry.questions.includes(:conversation).order(created_at: :desc, id: :desc).limit(QUESTIONS_LIMIT)
  end

  def create
    @knowledge_entry = @agent_bot.knowledge_entries.create!(permitted_params)
  end

  def update
    @knowledge_entry.update!(permitted_params)
  end

  def destroy
    @knowledge_entry.destroy!
    head :ok
  end

  # A dry run returns the counts and the row errors without saving; an import with row errors saves nothing
  def import
    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    result = AgentBotKnowledge::CsvImportService.new(agent_bot: @agent_bot, file: params[:file], dry_run: dry_run).perform
    if result[:errors].present? && !dry_run
      render json: { errors: result[:errors] }, status: :unprocessable_entity
    else
      render json: result
    end
  rescue AgentBotKnowledge::CsvImportService::Error => e
    render_could_not_create_error(e.message)
  end

  def export
    send_data AgentBotKnowledge::CsvExportService.new(agent_bot: @agent_bot).perform,
              filename: "knowledge-base-#{@agent_bot.id}.csv", type: 'text/csv; charset=utf-8'
  end

  private

  def knowledge_entry
    @knowledge_entry = @agent_bot.knowledge_entries.find(params[:id])
  end

  def searched_entries
    entries = @agent_bot.knowledge_entries
    entries = entries.where(category: params[:category]) if params[:category].present?
    params[:q].present? ? entries.search(params[:q]) : entries
  end

  def status_counts(entries)
    counts = entries.group(:status).count
    AgentBotKnowledgeEntry.statuses.keys.index_with { |status| counts.fetch(status, 0) }
  end

  # Blank fields are stored as nil, as the CSV import stores them, so a blank key gets the next KB- number
  def permitted_params
    params.permit(:key, :category, :frequency, :question, :alternative_questions, :short_answer, :answer, :selling_point, :status)
          .transform_values(&:presence)
  end
end
