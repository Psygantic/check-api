class Project < ActiveRecord::Base

  has_paper_trail on: [:create, :update]
  belongs_to :user
  belongs_to :team
  has_many :project_sources
  has_many :sources , through: :project_sources
  has_many :project_medias
  has_many :medias , through: :project_medias

  mount_uploader :lead_image, ImageUploader

  before_validation :set_description_and_team_and_user, on: :create

  validates_presence_of :title
  validates :lead_image, size: true

  has_annotations

  notifies_slack on: :create,
                 if: proc { |p| User.current.present? && p.team.setting(:slack_notifications_enabled).to_i === 1 },
                 message: proc { |p| I18n.t(:slack_create_project, default: "*%{user}* created a project: <%{url}>", user: User.current.name, url: "#{CONFIG['checkdesk_client']}/#{p.team.slug}/project/#{p.id}|*#{p.title}*") },
                 channel: proc { |p| p.setting(:slack_channel) || p.team.setting(:slack_channel) },
                 webhook: proc { |p| p.team.setting(:slack_webhook) }

  notifies_pusher on: :create,
                  event: 'project_created',
                  targets: proc { |p| [p.team] },
                  data: proc { |p| p.to_json }

  include CheckdeskSettings

  def user_id_callback(value, _mapping_ids = nil)
    user_callback(value)
  end

  def team_id_callback(value, mapping_ids = nil)
    mapping_ids[value]
  end

  def lead_image_callback(value, _mapping_ids = nil)
    image_callback(value)
  end

  def avatar
    CONFIG['checkdesk_base_url'] + self.lead_image.url
  end

  def as_json(options = {})
    project = {
      dbid: self.id,
      title: self.title,
      id: Base64.encode64("Project/#{self.id}")
    }
    unless options[:without_team]
      project[:team] = {
        id: Base64.encode64("Team/#{self.id}"),
        dbid: self.team_id,
        projects: { edges: self.team.projects.collect{ |p| { node: p.as_json(without_team: true) } } }
      }
    end
    project
  end

  def medias_count
    self.project_medias.count
  end

  def slack_notifications_enabled=(enabled)
    self.send(:set_slack_notifications_enabled, enabled)
  end

  def slack_channel=(channel)
    self.send(:set_slack_channel, channel)
  end

  private

  def set_description_and_team_and_user
    self.description ||= ''
    if !User.current.nil? && !self.team_id
      self.team = User.current.current_team
    end
    self.user ||= User.current
  end
end
